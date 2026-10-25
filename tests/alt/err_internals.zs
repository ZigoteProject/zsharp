// Task's and Alt's plumbing is for them only: a program can't reach it, by name or through the
// public records' fields (a promise's waiting tasks, a scope's cancellation, a channel's or a
// mailbox's queues, an event's representation).
let names () =
  let p : Promise<int> = Task.promise ()
  drainCallbacks p.waiting false ignore
  let undo = Task.onCancel
  let cancel = Task.cancelNow
  let under = child
  ()

let fields () =
  let p : Promise<int> = Task.promise ()
  let n = Buffer.length p.waiting.entries
  let scope = Task.scope (fun s ->
    task {
      s.children.actions.counts.Value <- { next = 5; dead = 0 }
      return ()
    })
  let ch : Ch<int> = Ch.make ()
  ch.takers.head.Value <- 7
  let m : Mailbox<int> = Mailbox.make ()
  let emptied = { m.values with head = ref 5 }
  ()

let built () =
  let q = { cells = Buffer.empty; head = ref 0; dead = ref 0 }
  ()

let taken (m: Mailbox<int>) =
  let { head = h } = m.takers
  ()

let matched () =
  match (Alt.always 3).ev with
  | Prims _ -> ()
  | _ -> ()

let main () = 0
