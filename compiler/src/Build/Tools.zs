/// The programs a build runs (clang, zig, llvm-ar, pkg-config, git): run without a shell, their
/// output captured.

extern realpath : cstr -> cptr -> cstr

/// This program's executable, its symbolic links followed: where its library and runtime are
/// (Linux names it in /proc).
let selfPath () : string = String.ofCStr (realpath "/proc/self/exe" (Ptr.toCPtr (Ptr.null () : ptr<u8>)))

/// The first directory from dir upward that holds the file at `relative` (lib/prelude.zs): a
/// compiler built inside a checkout finds the checkout's library and runtime.
let rec findUp (dir: string) (relative: string) : option<string> =
  if File.exists (Path.combine dir relative) then Some dir
  else if dir = "" || dir = "/" then None
  else findUp (Path.getDirectoryName dir) relative

/// What a run left: its exit code and its output (standard output, then standard error when the
/// two are captured apart).
type Ran = { code: int; out: string; err: string }

// a piped stream read to its end
let private drain (r: option<IO.Reader>) : string =
  match r with
  | Some reader ->
    match IO.Reader.readToEnd reader with
    | Ok text -> text
    | Error _ -> ""
  | None -> ""

/// Runs the program with the arguments, its standard error into its standard output (so neither
/// pipe fills while the other is read); Error when it can't start.
let runMerged (program: string) (args: list<string>) : result<Ran, string> =
  // sh only joins the streams: the program and its arguments are its positional parameters
  let s : Diagnostics.ProcessStart = { program = "sh"; args = List.append [ "-c"; "exec \"$0\" \"$@\" 2>&1"; program ] args; stdin = Diagnostics.Null; stdout = Diagnostics.Piped }
  match Diagnostics.Process.start s with
  | Error e -> Error e
  | Ok p ->
    let out = drain p.stdout
    let code = Task.run (Diagnostics.Process.wait p)
    Dispose.dispose p
    Ok { code = code; out = out; err = "" }

/// Runs the program, its standard output and standard error captured apart (read one after the
/// other: for a program that writes little to the second, as git does).
let runSplit (program: string) (args: list<string>) : result<Ran, string> =
  let s : Diagnostics.ProcessStart = { program = program; args = args; stdin = Diagnostics.Null; stdout = Diagnostics.Piped; stderr = Diagnostics.Piped }
  match Diagnostics.Process.start s with
  | Error e -> Error e
  | Ok p ->
    let out = drain p.stdout
    let err = drain p.stderr
    let code = Task.run (Diagnostics.Process.wait p)
    Dispose.dispose p
    Ok { code = code; out = out; err = err }

// the list without its first n elements
let rec private drop (n: int) (xs: list<'a>) : list<'a> =
  if n <= 0 then
    xs
  else
    match xs with
    | _ :: rest -> drop (n - 1) rest
    | [] -> []

/// Runs the programs, at most `width` at a time (each its own process, its output collected):
/// how each went, in order, as `run` says it.
let runMany (width: int) (cmds: list<string * list<string>>) : list<result<unit, string>> =
  let start (cmd: string * list<string>) : result<Diagnostics.Process, string> =
    let (program, args) = cmd
    let s : Diagnostics.ProcessStart = { program = "sh"; args = List.append [ "-c"; "exec \"$0\" \"$@\" 2>&1"; program ] args; stdin = Diagnostics.Null; stdout = Diagnostics.Piped }
    Diagnostics.Process.start s
  let finish (cmd: string * list<string>) (started: result<Diagnostics.Process, string>) : result<unit, string> =
    let (program, _) = cmd
    match started with
    | Error e -> Error $"{program}: {e}"
    | Ok p ->
      let out = drain p.stdout
      let code = Task.run (Diagnostics.Process.wait p)
      Dispose.dispose p
      if code = 0 then Ok () else Error $"{program} failed: {String.trim out}"
  let rec batches (rest: list<string * list<string>>) (acc: list<result<unit, string>>) : list<result<unit, string>> =
    match rest with
    | [] -> List.rev acc
    | _ ->
      let these = List.take width rest
      let started = List.map start these
      let done = List.map2 finish these started
      batches (drop (List.length these) rest) (List.append (List.rev done) acc)
  batches cmds []

/// Runs a tool: Error with its name and output when it fails or can't start.
let run (program: string) (args: list<string>) : result<unit, string> =
  match runMerged program args with
  | Ok r -> if r.code = 0 then Ok () else Error $"{program} failed: {String.trim r.out}"
  | Error e -> Error $"{program}: {e}"

/// Runs a program in the foreground (its streams this program's): its exit code.
let runInherited (program: string) (args: list<string>) : result<int, string> =
  let s : Diagnostics.ProcessStart = { program = program; args = args }
  match Diagnostics.Process.start s with
  | Error e -> Error e
  | Ok p -> Ok(Task.run (Diagnostics.Process.wait p))

/// Whether a program is on PATH.
let onPath (program: string) : bool =
  match Environment.getVariable "PATH" with
  | Some path -> List.exists (fun (d: string) -> d <> "" && File.exists (Path.combine d program)) (String.split ":" path)
  | None -> false

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
