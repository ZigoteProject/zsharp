/// Running other programs.
namespace Diagnostics

/// What a finished process left: its exit code and everything it wrote to standard output.
type ProcessResult =
  { /// The exit code (128 + the signal number if a signal ended it).
    code: int
    /// Standard output, captured. Standard error goes to this program's standard error.
    output: string }

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
