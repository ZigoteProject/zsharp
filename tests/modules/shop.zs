// shop.zs and books.zs declare a record, a trait and a derive under the same names
type Item = { name: string; size: int }

trait Label<'a> =
  abstract label : 'a -> string

impl Label<Item> =
  let label i = $"{i.name}: {i.size} coins"

derive Label =
  let label (x: 'self) = "wrapped by the shop"

[<Derive(Label)>]
type Gift = { ribbon: bool }

// Shop's own Item, though Books declares one with the same fields
let pen = { name = "pen"; size = 2 }

// i.name: Shop's field, whatever module is loaded after this one
let title i = i.name
