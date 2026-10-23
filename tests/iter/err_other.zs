// An impl's other parameter must be made of the head's type variables.
type Box<'a> = { item: 'a }

impl Iter<Box<'a>, 'b> =
  let forEach b f = f b.item

let main () = 0
