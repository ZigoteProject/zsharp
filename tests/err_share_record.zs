// A record with a plain function field doesn't cross threads, though one with a share<F> field does.
type Plain = { n: int; f: int -> int }
type Shared = { n: int; f: share<int -> int> }

let plain () =
  let c : Plain = { n = 1; f = fun x -> x + 1 }
  Task.spawn (fun () -> task { return c.f c.n })

let shared () =
  let c : Shared = { n = 1; f = fun x -> x + 1 }
  Task.spawn (fun () -> task { return c.f c.n })

let main () = ()
