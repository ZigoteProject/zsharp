// What can't be shared between threads doesn't cross to one: a ref or a Buffer (captured, or
// through a local function or a record), or a ref sent on a channel. Phase 7's exit test.
type Counter = { name: string; count: ref<int> }

let captured () =
  let r = ref 0
  Parallel.for 0 10 (fun i -> r.Value <- r.Value + i)

let buffer () =
  let b = Buffer.create 4 0
  Parallel.both (fun () -> b.[0]) (fun () -> 1)

let throughLocal () =
  let r = ref 0
  let add () = r.Value <- 1
  Parallel.for 0 10 (fun i -> add ())

let inRecord () =
  let c = { name = "hits"; count = ref 0 }
  Parallel.for 0 10 (fun i -> c.count.Value <- i)

let sent () =
  let ch = Channel.make 2
  Channel.send ch (ref 0)

let main () = ()
