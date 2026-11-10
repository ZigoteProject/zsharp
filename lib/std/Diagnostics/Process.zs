/// Running other programs.
namespace Diagnostics

/// What a finished process left: its exit code and everything it wrote to standard output.
type ProcessResult =
  { /// The exit code (128 + the signal number if a signal ended it).
    code: int
    /// Standard output, captured. Standard error goes to this program's standard error.
    output: string }

/// How a started process's standard stream is connected (`ProcessStart`'s `stdin`, `stdout` and
/// `stderr`).
type Pipe =
  /// This program's own stream.
  | Inherit
  /// A pipe: the `Process` record's `stdin`, `stdout` or `stderr`.
  | Piped
  /// Nothing: reading gets the end at once, and what's written is dropped.
  | Null
  /// `stderr` only: where standard output goes (its pipe, when that's `Piped`), as a shell's
  /// `2>&1`. One reader then sees both, in the order they were written, and neither can fill
  /// while the other waits to be read.
  | ToOutput

/// What `Process.start` runs, naming only what it changes from the defaults:
/// `Process.start { program = "clang"; args = [ "-c"; f ]; stderr = Piped }`.
type ProcessStart =
  { /// The program, looked up on PATH unless it has a `/`; a relative path is from this
    /// program's working directory, not `directory`.
    program: string
    /// Its arguments (no shell reads them; a Windows batch file's are quoted for `cmd.exe`, as
    /// `Process.run` says).
    args: list<string> = []
    /// Its whole environment, as names and values; `None` gives it this program's.
    environment: option<list<string * string>> = None
    /// Its working directory; `None` gives it this program's.
    directory: option<string> = None
    /// Its standard input.
    stdin: Pipe = Inherit
    /// Its standard output.
    stdout: Pipe = Inherit
    /// Its standard error.
    stderr: Pipe = Inherit }

/// A process running: its id, and this end of each stream that was `Piped`. `use` closes the
/// pipes (it doesn't wait for the process: `Process.wait` does).
type Process =
  { /// Its process id.
    pid: int
    /// The runtime's number for it, which `Process.wait` and `Process.kill` go by: unlike a
    /// process id, never another process's once this one has been waited for.
    handle: int
    /// Its standard input, when piped.
    stdin: option<Writer>
    /// Its standard output, when piped.
    stdout: option<Reader>
    /// Its standard error, when piped.
    stderr: option<Reader> }

/// Functions for running programs.
module Process =
  // a function: a value computed at startup can't be in a library C links (zs build --lib)
  let private nul () = String.ofByte (u8 0)

  // the runtime's arguments: each ended by a NUL, so "" is one too
  let private ended (args: list<string>) =
    String.concat (List.map (fun (a: string) -> a + nul ()) args)

  // a NUL ends a C string: an argument "a\0b" would reach the program as two, a name or directory
  // as a shorter one, so a process given one isn't started
  let private refused (program: string) (strings: list<string>) : option<string> =
    if List.exists (fun (x: string) -> String.contains (nul ()) x) (program :: strings) then
      Some $"cannot run {program}: an argument, the directory or the environment holds a NUL byte"
    else
      None

  /// Runs `program` (looked up on PATH) with the arguments, without a shell, and waits for it.
  /// An `Error` means it couldn't start (or be waited for); a failing program is an `Ok` with a
  /// nonzero code. On Windows a batch file (`.bat`, `.cmd`) runs in `cmd.exe`, its arguments
  /// quoted for it, and one with a line break (CR or LF), which `cmd.exe` can't be given, is an
  /// `Error`.
  let run (program: string) (args: list<string>) =
    match refused program args with
    | Some e -> Error e
    | None ->
      let output = Native.runProcess program (ended args)
      if Native.ioOk () then
        Ok { code = Native.exitCode (); output = output }
      else
        Error (Native.ioError ())

  // a stream's mode for the runtime: 0 inherited, 1 piped, 2 /dev/null, 3 standard output's
  let private mode (p: Pipe) =
    match p with
    | Inherit -> 0
    | Piped -> 1
    | Null -> 2
    | ToOutput -> 3

  let private toOutput (p: Pipe) =
    match p with
    | ToOutput -> true
    | _ -> false

  /// Starts the program (looked up on PATH unless it has a `/`; a relative path is from this
  /// program's working directory, not `directory`), without a shell; each stream that is `Piped`
  /// is the `Process`'s to use. `Process.wait` gives its exit code. A Windows batch file's
  /// arguments are as `Process.run` passes them.
  let start (s: ProcessStart) : result<Process, string> =
    let vars = Option.defaultValue [] s.environment |> List.map (fun (k, v) -> k + "=" + v)
    let dir = Option.defaultValue "" s.directory
    match refused s.program (dir :: List.append s.args vars) with
    | Some e -> Error e
    | None when toOutput s.stdin || toOutput s.stdout ->
      Error $"cannot run {s.program}: ToOutput is for stderr"
    | None ->
      let env = Option.map (fun _ -> String.join (nul ()) vars) s.environment
      let h =
        Native.processStart s.program (ended s.args) (Option.defaultValue "" env) (Option.isSome env) dir (mode s.stdin) (mode s.stdout) (mode s.stderr)
      if h < 0 then
        Error $"cannot run {s.program}: {Native.errorText h}"
      else
        let pipe k = Native.processPipe k
        let input = if pipe 0 >= 0 then Some (Writer.ofFd (pipe 0)) else None
        let output = if pipe 1 >= 0 then Some (Reader.ofFd (pipe 1)) else None
        let errors = if pipe 2 >= 0 then Some (Reader.ofFd (pipe 2)) else None
        Ok { pid = Native.processId h; handle = h; stdin = input; stdout = output; stderr = errors }

  /// Waits for the process to end: its exit code (128 plus the signal's number when a signal
  /// ended it, -1 when it can't be had). Other tasks go on meanwhile, and a wait that's
  /// cancelled (`Task.timeout`) is over at once, the process left running. Waiting again gives
  /// the same code.
  let wait (p: Process) : Task<int> =
    let h = p.handle

    task {
      // readable once the process has ended; -1: waited for already, its code at hand
      let fd = Native.processWaiter h
      if fd = -1 then
        return Native.processWait h
      else if fd < 0 then
        return! Task.blocking (fun () -> Native.processWait h)
      else
        do! Task.fromCallback (fun k -> Native.loopWait fd false k) (fun () -> Native.fdClose fd)
        Native.fdClose fd
        return Native.processWait h
    }

  /// Ends the process at once (SIGKILL). One that has been waited for has ended, and is left
  /// alone.
  let kill (p: Process) : result<unit, string> =
    let e = Native.processKill p.handle
    if e < 0 then Error (Native.errorText e) else Ok ()

/// `use` closes the process's pipes (it doesn't wait for it: `Process.wait` does).
impl Dispose<Process> =
  let dispose (p: Process) =
    match p.stdin with
    | Some w -> Dispose.dispose w
    | None -> ()
    match p.stdout with
    | Some r -> Dispose.dispose r
    | None -> ()
    match p.stderr with
    | Some r -> Dispose.dispose r
    | None -> ()
