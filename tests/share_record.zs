// A share<F> held in a record's field is laid out as the function it is: alone, in a list, in a
// tuple, and in a record a spawned task captures and calls on another thread.
type Cfg = { n: int; f: share<int -> int> }
type Hooks = { fs: list<share<int -> int>> }
type Sink = { port: int; log: int * share<string -> string> }

let main () =
  let c : Cfg = { n = 1; f = fun x -> x + 1 }
  println $"field: {c.f c.n}"

  let h : Hooks = { fs = [ (fun x -> x + 1); (fun x -> x * 10) ] }
  println $"list: {List.map (fun (f: share<int -> int>) -> f 4) h.fs}"

  let s : Sink = { port = 80; log = (7, fun m -> m + "!") }
  let (id, log) = s.log
  let line = log "logged"
  println $"tuple: {line} {id} {s.port}"

  let r = Task.run (Task.spawn (fun () -> task { return c.f c.n }))
  println $"spawned: {r}"
