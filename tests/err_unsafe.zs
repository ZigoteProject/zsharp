// reading through a raw pointer is unsafe: it must be inside `unsafe`
let main () =
  let p: ptr<int> = Ptr.null ()
  let x = Ptr.read p
  println $"{x}"
  0
