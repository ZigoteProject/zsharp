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

/// What `Process.start` runs, naming only what it changes from the defaults:
/// `Process.start { program = "clang"; args = [ "-c"; f ]; stderr = Piped }`.
type ProcessStart =
  { /// The program, looked up on PATH unless it has a `/`.
    program: string
    /// Its arguments (no shell reads them).
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
    /// Its standard input, when piped.
    stdin: option<Writer>
    /// Its standard output, when piped.
    stdout: option<Reader>
    /// Its standard error, when piped.
    stderr: option<Reader> }

/// Functions for running programs.
module Process =
  /// Runs `program` (looked up on PATH) with the arguments, without a shell, and waits for it.
  /// An `Error` means it couldn't start; a failing program is an `Ok` with a nonzero code.
  let run (program: string) (args: list<string>) =
    let output = Native.runProcess program (String.join (String.ofByte (u8 0)) args)
    if Native.ioOk () then
      Ok { code = Native.exitCode (); output = output }
    else
      Error (Native.ioError ())

  // a stream's mode for the runtime: 0 inherited, 1 piped, 2 /dev/null
  let private mode (p: Pipe) =
    match p with
    | Inherit -> 0
    | Piped -> 1
    | Null -> 2

  /// Starts the program (looked up on PATH unless it has a `/`), without a shell; each stream
  /// that is `Piped` is the `Process`'s to use. `Process.wait` gives its exit code.
  let start (s: ProcessStart) : result<Process, string> =
    let nul = String.ofByte (u8 0)
    let env =
      s.environment
      |> Option.map (fun vars -> String.join nul (List.map (fun (k, v) -> k + "=" + v) vars))
    let args = String.join nul s.args
    let dir = Option.defaultValue "" s.directory
    let pid =
      Native.processStart s.program args (Option.defaultValue "" env) (Option.isSome env) dir (mode s.stdin) (mode s.stdout) (mode s.stderr)
    if pid < 0 then
      Error $"cannot run {s.program}: {Native.errorText pid}"
    else
      let pipe k = Native.processPipe k
      let input = if pipe 0 >= 0 then Some (Writer.ofFd (pipe 0)) else None
      let output = if pipe 1 >= 0 then Some (Reader.ofFd (pipe 1)) else None
      let errors = if pipe 2 >= 0 then Some (Reader.ofFd (pipe 2)) else None
      Ok { pid = pid; stdin = input; stdout = output; stderr = errors }

  /// Waits for the process to end: its exit code (128 plus the signal's number when a signal
  /// ended it), on `Task.blocking`'s thread so other tasks go on.
  let wait (p: Process) : Task<int> =
    let pid = p.pid
    Task.blocking (fun () -> Native.processWait pid)

  /// Ends the process at once (SIGKILL).
  let kill (p: Process) : result<unit, string> =
    let e = Native.processKill p.pid
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
