trait Describe<'a> =
  abstract describe : 'a -> string

type Vec = { x: f64; y: f64 }

let main () =
  println (describe { x = 1.0; y = 2.0 })
  0
