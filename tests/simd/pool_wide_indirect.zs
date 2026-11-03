// The ways a vector reaches a heap object that its type alone doesn't show (tests/simd/pool_wide.zs:
// a list of vectors): a closure capturing one, a curried function's stub keeping one between
// arguments, a record with one boxed as a dyn, and a union case holding one: each on its own
// would need the aligned allocator, so together they do.
trait Summed<'a> =
  abstract total : 'a -> f32

type Lanes = { v: f32x8 }

impl Summed<Lanes> =
  let total l = F32x8.sum l.v

type Shape =
  | Vec of f32x4
  | Many of list<Shape>

let rec sum (s: Shape) : f32 =
  match s with
  | Vec v -> F32x4.sum v
  | Many l -> List.sumBy sum l

let add (v: u8x16) (i: int) : int = int (U8x16.get v i) + i

let main () =
  let before = Runtime.mallocs ()
  let v = U8x16.load (Array.init 16 (fun i -> u8 i)) 0
  let captured = [ 1; 2; 3 ] |> List.map (fun i -> int (U8x16.get v i) + i)
  let partial = add (U8x16.splat (u8 7))
  let curried = List.map partial [ 1; 2; 3 ]
  let boxed: list<dyn Summed> = [ { v = F32x8.splat (f32 1.5) } ]
  let cases = List.init 20 (fun i -> Vec (F32x4.splat (f32 i)))
  println $"{captured} {curried} {List.map total boxed} {sum (Many cases)}"
  println $"each object its own malloc: {Runtime.mallocs () - before >= 30}"
  0
