// the same program without units (must compile to identical IR)

let speed (d: f64) (t: f64) = d / t
let accel (v: f64) (t: f64) : f64 = v / t
let force (mass: f64) (a: f64) : f64 = mass * a
let area (w: f64) (h: f64) : f64 = w * h
let square (x: f64) = x * x

let main () =
  let d = 100.0
  let t = 10.0
  let v = speed d t
  let a = accel v 2.0
  println $"{v} {a} {force 70.0 a} {area 3.0 4.0} {square t}"
  println $"{d * 2.0} {2.0 / t} {d + 5.0} {List.sum [ 1.0; 2.0 ]} {d > 50.0}"
  0
