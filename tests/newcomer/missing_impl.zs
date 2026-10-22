// Calling a trait method on a type that has no impl for it
trait Area<'a> =
  abstract area : 'a -> f64

type Square = { side: f64 }

let main () =
  println $"{area { side = 2.0 }}"
  0
