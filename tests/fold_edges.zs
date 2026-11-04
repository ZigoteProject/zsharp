// constant folding at its edges (0015 step 4): each line prints a folded expression and the same
// computed at run time (through mutable variables, which aren't folded), which must agree:
// u64 values above 2^63, f32 rounding at every step, the sign of zero, conversions narrowed
// inside others, and negative literals down to i64's least
let widen (a: f32) = float a
let addsub (b: f32) (c: f32) = (b + c) - b

type Tree =
  | Leaf
  | Node of Tree * int * Tree

let staticTree = Node(Leaf, int (i8 200), Leaf)
let staticTable = [| int (i16 0xFFFE); int (i8 0x80); int (u8 300) |]
let staticFloats = [| -0.0; f64 (u8 300); f64 (f32 1152921573326323713) |]

let main () =
  let mutable big : u64 = 0xFFFF_FFFF_FFFF_FFFF
  let mutable two : u64 = 2
  let mutable one : u64 = 1
  let mutable minusZero = -0.0
  let mutable f1 : f32 = 0.1
  let mutable f2 : f32 = 0.10000000001
  let mutable fOne : f32 = 1.0
  let mutable fTiny : f32 = 0.00000001
  let mutable fBig : f32 = 16777217.0
  let mutable n200 = 200
  let mutable n300 = 300
  let mutable bigInt = 1152921573326323713
  println $"u64: {0xFFFF_FFFF_FFFF_FFFF > u64 1} {big > one} | {0xFFFF_FFFF_FFFF_FFFF / u64 2} {big / two} | {0xFFFF_FFFF_FFFF_FFFD % u64 3} {(big - two) % (two + one)}"
  println $"f32: {widen 0.1} {float f1} | {addsub 1.0 0.00000001} {(fOne + fTiny) - fOne} | {f32 0.1 < f32 0.10000000001} {f1 < f2} | {int (f32 16777217.0)} {int fBig}"
  println $"round: {Math.round (f32 2.5000001)} {Math.round (f1 + f32 2.4000001)}"
  println $"zero: {1.0 / -0.0} {1.0 / minusZero} | {1.0 / Math.round -0.5} {1.0 / Math.round (minusZero - 0.5)} | {1.0 / Math.round -0.3} {1.0 / Math.round (minusZero - 0.3)}"
  println $"f32 of an i64: {f32 1152921573326323713} {f32 bigInt}"
  println $"narrowed: {int (i8 200)} {int (i8 n200)} | {int (u8 300)} {int (u8 n300)}"
  match staticTree with
  | Node(_, v, _) ->
    println $"statics: {v} {staticTable.[0]} {staticTable.[1]} {staticTable.[2]} {1.0 / staticFloats.[0]} {staticFloats.[1]} {staticFloats.[2]}"
  | Leaf -> ()
  let least : i64 = -0x8000_0000_0000_0000
  println $"least: {least} {-0x7FFF_FFFF_FFFF_FFFF}"
  0
