// unused-value (0021): a statement's value is dropped; `ignore` says it's on purpose, and
// [<NoWarn "unused-value">] silences a declaration's
let twice x = x * 2

[<NoWarn "unused-value">]
let quiet () =
  twice 1
  ()

let main () =
  twice 3
  twice 4 |> ignore
  [ 1; 2 ]
  quiet ()
  0
