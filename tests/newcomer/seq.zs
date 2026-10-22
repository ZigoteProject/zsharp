// F#: seq { }; lazy sequences come with phase 10's effect handlers; lists and arrays are the collections today
let main () =
  let evens = seq { for i in 0 .. 10 do if i % 2 = 0 then yield i }
  Seq.length evens
