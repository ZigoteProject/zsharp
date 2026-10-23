extern each : callback<i32 -> unit> -> unit

let main () =
  each (fun x -> Yield.yield x)
  0
