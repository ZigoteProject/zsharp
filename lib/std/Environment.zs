/// The program's environment: its command-line arguments and environment variables.
/// `Environment.exit code` ends the program.
module Environment

/// The command-line arguments, without the program name.
let args () = List.init (Native.argc () - 1) (fun i -> Native.arg (i + 1))

/// The program name as it was started (`argv[0]`).
let programName () = Native.arg 0

/// The environment variable `name`, or `None` when it isn't set.
let getVariable (name: string) = if Native.hasVariable name then Some (Native.getVariable name) else None
