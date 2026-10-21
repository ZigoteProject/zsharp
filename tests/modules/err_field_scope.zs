// a record from a module that isn't open: its fields alone don't say which record
let main () =
  println (Books.label { name = "Emma"; size = 474 })
  0
