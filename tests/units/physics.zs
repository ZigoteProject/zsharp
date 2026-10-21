// Phase 3 exit test: units of measure are checked, then erased
[<Measure>] type m
[<Measure>] type s
[<Measure>] type kg

let speed (d: f64<m>) (t: f64<s>) = d / t
let accel (v: f64<m/s>) (t: f64<s>) : f64<m/s^2> = v / t
let force (mass: f64<kg>) (a: f64<m/s^2>) : f64<kg m/s^2> = mass * a
let area (w: f64<m>) (h: f64<m>) : f64<m^2> = w * h
let square (x: f64<'u>) = x * x

let main () =
  let d = 100.0<m>
  let t = 10.0<s>
  let v = speed d t
  let a = accel v 2.0<s>
  println $"{v} {a} {force 70.0<kg> a} {area 3.0<m> 4.0<m>} {square t}"
  println $"{d * 2.0} {2.0 / t} {d + 5.0<m>} {List.sum [ 1.0<m>; 2.0<m> ]} {d > 50.0<m>}"
  0
