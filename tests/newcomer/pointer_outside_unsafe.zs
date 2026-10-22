// C: reading through a pointer; in Z# that's inside `unsafe`
let main () =
  let p = Ptr.alloc<int> 1
  Ptr.write p 0 7
  let x = Ptr.read p 0
  Ptr.free p
  x
