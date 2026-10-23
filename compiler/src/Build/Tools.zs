/// The programs a build runs (clang, zig, llvm-ar, pkg-config, git): run without a shell, their
/// output captured.

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
