// Record fields, traits and derives belong to their module, like types: two modules can use the
// same names, and each resolves where its module is in scope.
open Shop

let main () =
  let mug = { name = "mug"; size = 3 } // Shop.Item: Shop is open and Books isn't
  println (label mug)
  println (title Shop.pen)
  println (label { ribbon = true })
  println (Books.label Books.novel)
  println (Books.label ({ name = "Emma"; size = 474 } : Books.Item))
  println (Books.label ({ wide = false } : Books.Poster))
  0
