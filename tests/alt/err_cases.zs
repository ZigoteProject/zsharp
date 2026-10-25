// An event is made by the functions of Alt, Ch and Mailbox: the cases it's made of are private.
let main () =
  let a : Alt<int> = Prims []
  let b : Alt<int> = Guard (Task.ret (Alt.always 4))
  0
