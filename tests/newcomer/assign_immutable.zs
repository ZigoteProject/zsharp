// C: every variable is assignable; in Z# only a `let mutable` is
let main () =
  let i = 0
  i <- i + 1
  i
