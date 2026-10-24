// Every mistake of a declaration, not only its first (0020): three in one function and two in
// another, five errors in file order, the same from zs check and from zs lsp (tests/lsp/many.sh).
let area (w: int) (h: int) : int =
  let wide = w + "1"
  let tall: string = h
  let both = missing * 2
  w * h

let main () =
  let shown: bool = 4
  let named: string = area 2 3
  println "done"
