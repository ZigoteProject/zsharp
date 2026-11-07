/// The programs a build runs (clang, zig, llvm-ar, pkg-config, git): run without a shell, their
/// output captured.

extern zs_host_exe : unit -> cstr
extern zs_host_os : unit -> cstr
extern zs_host_env_count : unit -> i64
extern zs_host_env_at : i64 -> cstr

/// The operating system the compiler runs on: linux, macos or windows.
let hostOs () : string = String.ofCStr (zs_host_os ())

/// This compiler's release: src/zs.toml's version, which test.sh checks it against.
let version = "0.7.0"

/// This program's executable, its symbolic links followed: where its library and runtime are.
let selfPath () : string = String.ofCStr (zs_host_exe ())

/// The first directory from dir upward that holds the file at `relative` (lib/prelude.zs): a
/// compiler built inside a checkout finds the checkout's library and runtime.
let rec findUp (dir: string) (relative: string) : option<string> =
  if File.exists (Path.combine dir relative) then Some dir
  else if dir = "" || dir = "/" then None
  else findUp (Path.getDirectoryName dir) relative

/// What a run left: its exit code and its output (standard output, then standard error when the
/// two are captured apart).
type Ran = { code: int; out: string; err: string }

/// Whether a link item names a file (it has a directory separator: '/', or Windows' '\\', as
/// Path.combine joins there) rather than a library to link with -l.
let isFile (item: string) : bool = String.contains "/" item || String.contains "\\" item

/// Whether a program is on PATH.
let onPath (program: string) : bool =
  match Environment.getVariable "PATH" with
  | Some path -> List.exists (fun (d: string) -> d <> "" && File.exists (Path.combine d program)) (String.split ":" path)
  | None -> false

// a piped stream read to its end
let private drain (r: option<IO.Reader>) : string =
  match r with
  | Some reader ->
    match IO.Reader.readToEnd reader with
    | Ok text -> text
    | Error _ -> ""
  | None -> ""

// the program run with both streams piped, read one after the other: a program that writes over
// a pipe's worth to standard error while its standard output is open blocks (on Windows, where
// this is how runSplit runs everything, the runtime's pipes hold a megabyte)
let private runPiped (program: string) (args: list<string>) : result<Ran, string> =
  let s : Diagnostics.ProcessStart = { program = program; args = args; stdin = Diagnostics.Null; stdout = Diagnostics.Piped; stderr = Diagnostics.Piped }
  match Diagnostics.Process.start s with
  | Error e -> Error e
  | Ok p ->
    let out = drain p.stdout
    let err = drain p.stderr
    let code = Task.run (Diagnostics.Process.wait p)
    Dispose.dispose p
    Ok { code = code; out = out; err = err }

/// Runs the program, its standard output and standard error captured apart. Standard error goes
/// to a file while standard output is read, so neither can fill and block the program (libFuzzer
/// and a benchmark that logs write much to it); on Windows both are piped, read in turn.
let runSplit (program: string) (args: list<string>) : result<Ran, string> =
  // through sh only when the program is there to run: one that isn't is an Error, as it can't start
  if hostOs () = "windows" || not (String.contains "/" program || onPath program) then
    runPiped program args
  else
    match File.createTemp "zs-err-" with
    | Error _ -> runPiped program args
    | Ok errFile ->
      // sh only redirects: the file, the program and its arguments are its positional parameters
      let s : Diagnostics.ProcessStart =
        { program = "sh"
          args = List.append [ "-c"; "f=$1; shift; exec \"$@\" 2>\"$f\""; "sh"; errFile; program ] args
          stdin = Diagnostics.Null
          stdout = Diagnostics.Piped }
      let r =
        match Diagnostics.Process.start s with
        | Error e -> Error e
        | Ok p ->
          let out = drain p.stdout
          let code = Task.run (Diagnostics.Process.wait p)
          Dispose.dispose p
          let err =
            match File.readAllText errFile with
            | Ok t -> t
            | Error _ -> ""
          Ok { code = code; out = out; err = err }
      File.delete errFile |> ignore
      r

// this process's environment with `vars` set (an entry of the same name dropped, regardless of
// case on Windows, where names have none); an entry is split at its first '=' after the first
// character, as Windows' per-drive "=C:=C:\dir" ones start with one
let private environmentWith (vars: list<string * string>) : list<string * string> =
  let key (name: string) = if hostOs () = "windows" then String.ofChars (List.map Char.toUpper (String.chars name)) else name
  let given = Set.ofList (List.map (fun (n, _) -> key n) vars)
  let entry (e: string) : option<string * string> =
    match String.indexOf "=" (String.sub e 1 (max 0 (String.length e - 1))) with
    | Some i -> Some(String.sub e 0 (i + 1), String.sub e (i + 2) (String.length e - i - 2))
    | None -> None
  let own = List.choose entry (List.init (int (zs_host_env_count ())) (fun i -> String.ofCStr (zs_host_env_at (i64 i))))
  List.append (List.filter (fun (n, _) -> not (Set.contains (key n) given)) own) vars

// a pipe read to its end on a thread of its own: Task.blocking's jobs share one helper thread,
// so the other pipe's read would wait behind this one while the program, filling it, waits too
let private readPipe (fd: int) : Task<string> =
  Task.spawn (fun () -> Task.blocking (fun () -> if fd < 0 then "" else Result.defaultValue "" (IO.Reader.readToEnd (IO.Reader.ofFd fd))))

// the program's exit code, or 124 (as `timeout` gives) when it's still running after `ms`
// milliseconds, killed then; no limit for 0
let private waitBounded (p: Diagnostics.Process) (ms: int) : Task<int> =
  if ms <= 0 then
    Diagnostics.Process.wait p
  else
    let late () =
      Diagnostics.Process.kill p |> ignore
      124
    Task.map (fun (r: option<int>) -> match r with | Some code -> code | None -> late ()) (Task.timeout ms (Diagnostics.Process.wait p))

/// Runs the program with these variables added to this process's environment, its standard
/// output and standard error captured apart and read while it writes them, stopped after `ms`
/// milliseconds (no limit for 0) with the code 124. What `timeout` and `env` did, without them:
/// stock macOS has no timeout, and Windows' is another program.
let runBounded (vars: list<string * string>) (ms: int) (program: string) (args: list<string>) : result<Ran, string> =
  let s : Diagnostics.ProcessStart = { program = program; args = args; environment = Some(environmentWith vars); stdin = Diagnostics.Null; stdout = Diagnostics.Piped; stderr = Diagnostics.Piped }
  match Diagnostics.Process.start s with
  | Error e -> Error e
  | Ok p ->
    let fd (r: option<IO.Reader>) =
      match r with
      | Some x -> x.fd
      | None -> -1
    let ((out, err), code) = Task.run (Task.both (Task.both (readPipe (fd p.stdout)) (readPipe (fd p.stderr))) (waitBounded p ms))
    Dispose.dispose p
    Ok { code = code; out = out; err = err }

/// Runs the program with the arguments, its standard error into its standard output (so neither
/// pipe fills while the other is read); Error when it can't start.
let runMerged (program: string) (args: list<string>) : result<Ran, string> =
  if hostOs () = "windows" then
    // no sh: the two streams captured apart, then joined. Read one after the other, a tool that
    // writes more errors than a pipe holds before it ends waits for ever (`zig cc -v`'s search
    // list, which every check for a target reads, did at Windows' default size): the runtime's
    // pipes hold a megabyte there. ponytail: Diagnostics.ToOutput (2>&1) once stage 0's library
    // has it (0.7.0), which no amount of errors fills
    match runSplit program args with
    | Ok r -> Ok { r with out = r.out + r.err; err = "" }
    | Error e -> Error e
  else
    // sh only joins the streams: the program and its arguments are its positional parameters
    let s : Diagnostics.ProcessStart = { program = "sh"; args = List.append [ "-c"; "exec \"$0\" \"$@\" 2>&1"; program ] args; stdin = Diagnostics.Null; stdout = Diagnostics.Piped }
    match Diagnostics.Process.start s with
    | Error e -> Error e
    | Ok p ->
      let out = drain p.stdout
      let code = Task.run (Diagnostics.Process.wait p)
      Dispose.dispose p
      Ok { code = code; out = out; err = "" }

/// Runs a tool: Error with its name and output when it fails or can't start.
let run (program: string) (args: list<string>) : result<unit, string> =
  match runMerged program args with
  | Ok r -> if r.code = 0 then Ok () else Error $"{program} failed: {String.trim r.out}"
  | Error e -> Error $"{program}: {e}"

/// Runs the programs, as many at once as the pool has workers (a worker that's done starts the
/// next, as the F# compiler's did: batches waited for their slowest): how each went, in order, as
/// `run` says it.
let runMany (cmds: list<string * list<string>>) : list<result<unit, string>> =
  Array.toList (Array.Parallel.map (fun (cmd: string * list<string>) -> run (fst cmd) (snd cmd)) (Array.ofList cmds))

/// Runs a program in the foreground (its streams this program's): its exit code.
let runInherited (program: string) (args: list<string>) : result<int, string> =
  let s : Diagnostics.ProcessStart = { program = program; args = args }
  match Diagnostics.Process.start s with
  | Error e -> Error e
  | Ok p -> Ok(Task.run (Diagnostics.Process.wait p))

/// Creates a directory and the ones above it that it needs.
let rec makeDirectory (path: string) : unit =
  if path <> "" && path <> "/" && not (Directory.exists path) then
    makeDirectory (Path.getDirectoryName path)
    Directory.create path |> ignore

/// Where zs caches what it builds: $XDG_CACHE_HOME/zs, else ~/.cache/zs.
let cacheRoot () : string =
  match Environment.getVariable "XDG_CACHE_HOME" with
  | Some d when d <> "" -> Path.combine d "zs"
  | _ -> Path.combine (Path.combine (Option.defaultValue "" (Environment.getVariable "HOME")) ".cache") "zs"

/// Whether builds use what the cache keeps under keys of what it was made from (ZS_NO_CACHE=1:
/// only what's kept under a hash of its own contents).
let cacheOn () : bool = Option.isNone (Environment.getVariable "ZS_NO_CACHE")

/// A hash of the parts, 32 hex digits.
let hashOf (parts: list<string>) : string =
  Xxhash.hex (String.bytes (String.concat (List.map (fun (p: string) -> $"{String.length p}:{p}") parts)))

/// The compiler, as part of every key: a result holds only for the compiler that made it (its
/// binary, by its size and time).
let compilerId () : string =
  let exe = selfPath ()
  let size = Result.defaultValue (i64 0) (File.size exe)
  let time =
    match File.modifiedAt exe with
    | Ok t -> $"{t}"
    | Error _ -> ""
  $"{exe} {size} {time}"

/// Writes a file whole or not at all (a temporary file moved over it), for builds running at the
/// same time; a cache that can't be written is only not kept.
let writeWhole (path: string) (bytes: array<u8>) : unit =
  makeDirectory (Path.getDirectoryName path)
  // a name of its own beside it (the temporary directory may be another file system)
  match File.createTemp "zs-" with
  | Ok unique ->
    File.delete unique |> ignore
    let tmp = path + "." + Path.getFileName unique
    match File.writeAllBytes tmp bytes with
    | Ok () -> File.move tmp path |> ignore
    | Error _ -> File.delete tmp |> ignore
  | Error _ -> ()
