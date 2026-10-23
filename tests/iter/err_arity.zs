// Iter takes two type parameters.
type Box<'a> = { item: 'a }

impl Iter<Box<'a>> =
  let forEach b f = f b.item

let main () = 0
