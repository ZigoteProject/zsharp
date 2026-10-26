// Math: libm's functions for f64 and f32, round half to even, clamp, and pi and e at either type
let main () =
  println $"{Math.floor 2.5} {Math.ceil 2.5} {Math.round 2.5} {Math.round 3.5} {Math.round -2.5} {Math.trunc -2.7}"
  println $"{Math.pow 2.0 10.0} {Math.pow 9.0 0.5} {Math.exp 0.0} {Math.log Math.e} {Math.log2 8.0} {Math.log10 1000.0}"
  println $"{Math.sin 0.0} {Math.cos 0.0} {Math.atan2 1.0 -1.0 = 3.0 * Math.pi / 4.0} {Math.tan (Math.pi / 4.0)}"
  let half: f32 = Math.pi / f32 2.0
  println $"{half} {Math.sin half} {Math.floor (f32 1.75)} {Math.pow (f32 2.0) (f32 -1.0)}"
  println $"{Math.clamp 0 10 15} {Math.clamp 0 10 -3} {Math.clamp 0.0 1.0 0.25} {Math.abs -4}"
  0
