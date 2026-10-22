// Kennedy's general case: f's parameters have no annotations, and sq x and cube y must have one
// unit, so x's unit is some 'w cubed and y's 'w squared ('u^2 = 'v^3 has no other solution)
[<Measure>] type m

let sq (x: f64<'u>) = x * x
let cube (x: f64<'u>) = x * x * x
let same (a: f64<'u>) (b: f64<'u>) = a + b

let f x y = same (sq x) (cube y)

let main () =
  let r: f64<m^6> = f 2.0<m^3> 3.0<m^2>
  println $"{r}"
  0
