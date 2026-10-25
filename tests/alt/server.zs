// Reppy's request/reply server: a client's request carries a reply channel and the nack of its
// branch, so the server chooses between giving the reply and seeing that the client gave up
// (its timeout won).
type Request = int * Ch<int> * Alt<unit>

// handles n requests in turn: the second is slow
let server (reqs: Mailbox<Request>) (n: int) =
  task {
    for i in 1 .. n do
      let! (x, reply, nack) = Alt.sync (Mailbox.take reqs)
      do! Task.sleep (if x = 2 then 20 else 0)
      let! r =
        Alt.sync (Alt.choose [ Alt.map (fun () -> $"served {x}") (Ch.give reply (2 * x))
            Alt.map (fun () -> $"abandoned {x}") nack ])
      println r
    return ()
  }

// a call: the request goes out at each sync, and the reply is the event
let rpc (reqs: Mailbox<Request>) (x: int) : Alt<int> =
  Alt.withNack (fun nack ->
    let reply = Ch.make ()
    Mailbox.post reqs (x, reply, nack)
    Ch.take reply)

let main () =
  let reqs = Mailbox.make ()
  Task.run (Task.scope (fun s ->
      task {
        Task.start s (server reqs 3) |> ignore
        let! a = Alt.sync (rpc reqs 1)
        println $"client got {a}"
        let! b =
          Alt.sync (Alt.choose [ Alt.map Some (rpc reqs 2); Alt.map (fun () -> None) (Alt.after 5) ])
        if Option.isNone b then println "client 2 timed out"
        let! c = Alt.sync (rpc reqs 3)
        println $"client got {c}"
        return ()
      }))
  0
