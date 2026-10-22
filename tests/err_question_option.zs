// ? on an option where the rest of the block gives a result: the error names the conversion,
// with the caret under the ?
let parse (s: string) : result<int, string> =
  let c = List.tryHead [ s ]?
  Ok (String.length c)

let main () =
  println $"{parse "x"}"
  0
