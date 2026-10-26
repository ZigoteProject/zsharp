// Random: PCG32, seeded, the same numbers on every target; Random.shared from the system
let main () =
  // PCG's reference output for seed 42 on stream 54
  let r = Random.create (u64 42)
  println (String.concat (List.init 6 (fun _ -> $"{Random.nextU32 r:x8} ")))
  // every face of a die about as often, none outside
  let d = Random.create (u64 2026)
  let counts = Buffer.create 7 0
  for _ in 1 .. 60000 do
    let face = Random.nextInt 1 7 d
    counts.[face] <- counts.[face] + 1
  let faces = List.init 6 (fun i -> counts.[i + 1])
  println $"faces {List.forall (fun n -> n > 9000 && n < 11000) faces} {counts.[0]}"
  // a range wider than 32 bits, and the whole of int
  let wide = Random.nextInt 0 5000000000 d
  let top = 9223372036854775807
  let whole = Random.nextInt (-top - 1) top d
  println $"wide {wide >= 0 && wide < 5000000000} whole {whole < top}"
  let floats = List.init 1000 (fun _ -> Random.nextFloat d)
  println $"floats {List.forall (fun f -> f >= 0.0 && f < 1.0) floats} {List.exists (fun f -> f > 0.9) floats}"
  let shuffled = Random.shuffle (Array.init 20 id) d
  println $"shuffled {List.sort (Array.toList shuffled) = List.init 20 id} {Array.toList shuffled <> List.init 20 id}"
  let bytes = Buffer.create 32 (u8 0)
  Random.nextBytes bytes d
  println $"bytes {Array.exists (fun b -> b <> u8 0) (Buffer.toArray bytes)}"
  // seeded from the system: two generators, two sequences
  println $"shared {Random.nextU32 (Random.shared ()) <> Random.nextU32 (Random.shared ())}"
  0
