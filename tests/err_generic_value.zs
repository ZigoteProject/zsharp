// a top-level value computed at startup has one type: a generic one must be a constant (or a
// function)
let wrapped : list<option<'a>> = List.map Some []

let main () =
  println $"{List.length wrapped}"
  0
