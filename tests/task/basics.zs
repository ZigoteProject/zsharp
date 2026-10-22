// Tasks: timers in order, both and all, race and timeout (cancelling the loser, which closes
// what it bound with use), a scope with tasks started in it, and Task.blocking
type Resource = Resource of string

impl Dispose<Resource> =
  let dispose (Resource name) = println $"{name} closed"

let say (name: string) (ms: int) =
  task {
    do! Task.sleep ms
    println $"{name} after {ms} ms"
    return ms
  }

let slow () =
  task {
    use r = Resource "slow's resource"
    do! Task.sleep 1000
    println "slow finished"
    return 1
  }

let main () =
  let (a, b) = Task.run (Task.both (say "a" 30) (say "b" 10))
  println $"both: {a} {b}"
  let xs = Task.run (Task.all [ say "x" 20; say "y" 5; say "z" 10 ])
  println $"all: {xs}"
  let r = Task.run (Task.race (slow ()) (say "fast" 10))
  println $"race: {r}"
  let t = Task.run (Task.timeout 20 (slow ()))
  println $"timeout: {t}"

  let n =
    Task.run (
      Task.scope (fun s ->
        task {
          let p = Task.start s (say "child" 15)
          Task.start s (say "other" 5) |> ignore
          let! x = Task.wait p
          return x * 2
        })
    )

  println $"scope: {n}"
  println $"blocking: {Task.run (Task.blocking (fun () -> 6 * 7))}"

  // files read and written on the helper thread, while the event loop goes on
  let path = "/tmp/zs-task-basics.txt"

  let text =
    Task.run (
      task {
        let! w = File.writeAllTextAsync path "written by a task"
        let! r = File.readAllTextAsync path
        File.delete path |> ignore
        return r
      }
    )

  println $"file: {text}"
  0
