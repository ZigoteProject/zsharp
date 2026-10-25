// withNack's nack happens when the sync commits to a branch outside its function's, or the
// task is cancelled while it waits, and never when one of its own commits; it's given at the
// commit, before the syncing task goes on. A guard runs at each sync, before any branch is
// polled, and is cancelled with the task.
type Resource = Resource of string * ref<list<string>>

impl Dispose<Resource> =
  let dispose (Resource (name, log)) = log.Value <- $"{name} closed" :: log.Value

// takes n (label, nack) pairs from the box, and for each says whether the nack happens in 20 ms
let watch (s: Scope) (box: Mailbox<string * Alt<unit>>) (n: int) =
  task {
    for i in 1 .. n do
      let! (label, nack) = Alt.sync (Mailbox.take box)
      Task.start s (task {
          let! r = Task.timeout 20 (Alt.sync nack)
          println (label + (if Option.isSome r then "nack" else "none"))
          return ()
        }) |> ignore
    return ()
  }

// e's events, with its nack posted to the box under label
let watched (box: Mailbox<string * Alt<unit>>) (label: string) (e: Alt<'a>) : Alt<'a> =
  Alt.withNack (fun nack ->
    Mailbox.post box (label, nack)
    e)

let main () =
  let box = Mailbox.make ()
  let a = Ch.make ()
  let b = Ch.make ()
  let c = Ch.make ()

  // b is ready: the nack of the branch on a is given before the client goes on
  Task.run (Task.scope (fun s ->
      task {
        Task.start s (watch s box 1) |> ignore
        Task.start s (Ch.send b 2) |> ignore
        let! x = Alt.sync (Alt.choose [ watched box "" (Ch.take a); Ch.take b ])
        println $"got b {x}"
        return ()
      }))

  // the branch under the nack commits: no nack
  Task.run (Task.scope (fun s ->
      task {
        Task.start s (watch s box 1) |> ignore
        Task.start s (Ch.send a 1) |> ignore
        let! x = Alt.sync (Alt.choose [ watched box "own branch won: " (Ch.take a); Ch.take b ])
        return ()
      }))

  // cancelled while it waits: the nack is given
  Task.run (Task.scope (fun s ->
      task {
        Task.start s (watch s box 1) |> ignore
        let! r = Task.timeout 5 (Alt.sync (watched box "" (Ch.take a)))
        println $"cancelled: {r}"
        return ()
      }))

  // nested: b commits, which is under the outer nack's function but not the inner's
  Task.run (Task.scope (fun s ->
      task {
        Task.start s (watch s box 2) |> ignore
        Task.start s (Ch.send b 3) |> ignore
        let inner = Alt.choose [ watched box "inner " (Ch.take a); Ch.take b ]
        let! x = Alt.sync (Alt.choose [ watched box "outer " inner; Ch.take c ])
        println $"got b {x}"
        return ()
      }))

  let runs = ref 0
  let counted =
    Alt.guard (task {
        runs.Value <- runs.Value + 1
        return Alt.always runs.Value
      })
  let mutable last = 0
  for i in 1 .. 3 do
    last <- Task.run (Alt.sync counted)
  println $"guard ran {runs.Value} times in {last} syncs"

  // the guard waits, and only then are the branches polled: its own comes first
  let late = Alt.guard (task {
      do! Task.sleep 5
      return Alt.always "late"
    })
  println $"a guard that waits runs before polling: {Task.run (Alt.sync (Alt.choose [ late; Alt.always "now" ]))}"

  let log = ref []
  let slow = Alt.guard (task {
      use r = Resource ("r", log)
      do! Task.sleep 60000
      return Alt.always 1
    })
  let t = Task.run (Task.timeout 5 (Alt.sync slow))
  println $"guard cancelled while it waits: {String.concat log.Value}, {t}"

  // a withNack function cancels its own task: its nack is given, and the later ones never run
  let ran = ref false
  let a = Ch.make ()
  Task.run (Task.scope (fun outer ->
      task {
        do! Task.scope (fun s ->
          task {
            let first = Alt.withNack (fun n ->
              Mailbox.post box ("cancelled by its own function: ", n)
              Task.cancel s
              Ch.take a)
            let second = Alt.withNack (fun n ->
              ran.Value <- true
              Ch.take a)
            Task.start outer (watch outer box 1) |> ignore
            Task.start s (Alt.sync (Alt.choose [ first; second ])) |> ignore
            return ()
          })
        return ()
      }))
  println $"the next withNack function ran after the cancel: {ran.Value}"
  0
