type Item = { name: string; size: int }

trait Label<'a> =
  abstract label : 'a -> string

impl Label<Item> =
  let label b = $"{b.name}, {b.size} pages"

derive Label =
  let label (x: 'self) = "printed"

[<Derive(Label)>]
type Poster = { wide: bool }

let novel = { name = "Dune"; size = 412 }
