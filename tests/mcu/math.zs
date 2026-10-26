// Math and Random on a chip: libm's functions are compiler-rt's there, and pow, atan2 and round
// the runtime's (fdlibm's), with a host's results, in millionths (two libms may differ in the
// last bit, and a chip prints a float to six digits); a seed's numbers are a host's
let six (x: f64) : i64 = i64 (Math.round (x * 1000000.0))

let main () =
  for x in [| 0.5; 2.0; 2.5; -2.5; 10.0 |] do
    println $"{x}: pow {six (Math.pow 2.0 x)} atan2 {six (Math.atan2 x -1.0)} round {Math.round x} floor {Math.floor x} trunc {Math.trunc x}"
    println $"  exp {six (Math.exp x)} log {six (Math.log (Math.abs x))} log2 {six (Math.log2 (Math.abs x))} sin {six (Math.sin x)} cos {six (Math.cos x)} tan {six (Math.tan x)}"
  for f in [| f32 0.5; f32 2.5; f32 -3.5 |] do
    println $"{f}: pow {six (f64 (Math.pow (f32 2.0) f))} round {Math.round f} ceil {Math.ceil f} clamp {Math.clamp (f32 0.0) (f32 1.0) f}"
  let r = Random.create (u64 42)
  println (String.concat (List.init 6 (fun _ -> $"{Random.nextU32 r:x8} ")))
  let d = Random.create (u64 7)
  println $"{List.init 12 (fun _ -> Random.nextInt 1 7 d)} {six (Random.nextFloat d)}"
  0
