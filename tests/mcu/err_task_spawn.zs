// Task.spawn on a chip (0016): no threads there, an error at the call naming the chain
let serve () = Task.spawn (fun () -> Task.ret 1)

let main () = Task.run (serve ())
