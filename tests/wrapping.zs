// [<Wrapping>]: + - and * on integers wrap around in the whole function, its lambdas included,
// instead of panicking on overflow (hashes and checksums)
[<Wrapping>]
let fnv1a (s: string) =
  let mutable h = u32 2166136261
  for i in 0 .. String.length s - 1 do
    h <- (h ^^^ u32 (String.byte s i)) * u32 16777619
  h

[<Wrapping>]
let cube (x: i64) = x * x * x

[<Wrapping>]
let next (x: i64) = List.fold (fun acc d -> acc + d) x [ i64 1 ]

// floats and strings keep their meaning
[<Wrapping>]
let mixed (a: f64) (s: string) = (a * 2.0 + 0.5, s + "!")

let main () =
  println $"{fnv1a "hello"} {fnv1a ""} {fnv1a "Z#"}"
  println $"{cube (i64 3037000500)} {next (i64 9223372036854775807)} {mixed 1.0 "hi"}"
  0
