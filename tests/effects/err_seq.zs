let main () =
  let s = seq {
    yield 1
    Throw.throw "no" }
  0
