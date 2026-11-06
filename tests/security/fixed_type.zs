// Fixed.ofArray's panic names the type, whose text is as long as its element type's: here 197
// characters, which the runtime copied whole into a 160-byte message on the stack. It's cut to
// fit, ending "...".
type Four = string * string * string * string

type Row = Four * Four * Four * Four * Four

let main () =
  let f: fixed<Row, 1> = Fixed.ofArray [||]
  println $"{Fixed.length f}"
  0
