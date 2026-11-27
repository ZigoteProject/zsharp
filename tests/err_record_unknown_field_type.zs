// a record whose field type is unknown, then built with an expected type: the unknown type is
// the error, where the checker used to panic looking the record's defaults up (fuzz, seed
// 20261124)
type S = { a: int; b: list<Nope> }

impl Add<S> =
  let add x y = { a = x.a + y.a; b = [] }
  let zero = { a = 0; b = [] }

let main () = ()
