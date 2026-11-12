// An i64 to f32 is rounded once (2^60 + 2^36 + 1 is above the tie, so up), folded, computed at
// run time and in a static: through a double it's rounded twice, to 2^60, which is what
// valgrind's conversion does, so this runs plain only.
let staticFloat = [| f64 (f32 1152921573326323713) |]

let main () =
  let mutable bigInt = 1152921573326323713
  println $"f32 of an i64: {f32 1152921573326323713} {f32 bigInt}"
  println $"static: {staticFloat.[0]}"
  0
