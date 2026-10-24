// logstat: summarises HTTP access logs.
//
//   zs run -- [-v] [--top N] [--timeout MS] <file.log | dir>...
//
// The program is App.run. Here it gets the real terminal and disk; the tests give it fakes.

let main () = Io.Real.terminal (fun () -> Io.Real.files (fun () -> App.run (Environment.args ())))
