// Process.wait holds no thread: a timeout around it is over at once (the process left running),
// and Task.blocking's helper thread stays free for other work meanwhile. A second wait gives the
// same code, and a kill after a wait leaves the process alone (its id may be another's by then).
let quiet (args: list<string>) : ProcessStart =
  { program = "sh"; args = args; stdin = Null; stdout = Null; stderr = Null }

let main () =
  match Process.start (quiet [ "-c"; "exit 5" ]) with
  | Ok p ->
    let first = Task.run (Process.wait p)
    let again = Task.run (Process.wait p)
    println $"waited: {first} {again}, then a kill: {Result.isOk (Process.kill p)}"
  | Error e -> println e
  match Process.start (quiet [ "-c"; "exec sleep 30" ]) with
  | Ok p ->
    let sw = Stopwatch.startNew ()
    let timed = Task.timeout 200 (Process.wait p)
    let (waited, n) = Task.run (Task.both timed (Task.blocking (fun () -> 42)))
    println $"timed out: {waited} {n}, at once: {sw.ElapsedMilliseconds < 10000}"
    println $"killed: {Result.isOk (Process.kill p)} {Task.run (Process.wait p)}"
  | Error e -> println e
  0
