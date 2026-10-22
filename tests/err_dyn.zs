// a dyn Trait holds only values whose type implements the trait
trait Shape<'a> =
  abstract area : 'a -> f64

let main () =
  let s: dyn Shape = 5
  println $"{area s}"
  0
