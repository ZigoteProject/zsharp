// every kind of value under -g (tests/debug run by test.sh): closures, C pointers, a Buffer,
// unions whose payload holds the union again, through a list, a ref or an array, and SIMD vectors
// (no DWARF type of their own, but their size lays out what follows them)
type Rose =
  | Leaf
  | Node of list<Rose>

type Q =
  | Q0
  | Q1 of ref<Q>

type Wide =
  | W0
  | W1 of array<Wide>

let rec count (r: Rose) : int =
  match r with
  | Leaf -> 1
  | Node kids -> 1 + List.sum (List.map count kids)

let apply (f: int -> int) x = f x

type Lanes = { v: f32x4; n: int }

let main () =
  let xs = List.map (fun x -> x + 1) [ 1; 2 ]
  let p : ptr<u8> = unsafe (Ptr.alloc 4)
  unsafe (Ptr.write p (u8 7))
  let b = Buffer.create 2 (u8 1)
  let q = Q1(ref Q0)
  let w = W1 [| W0; W0 |]
  let depth =
    match q with
    | Q1 r -> (match r.Value with | Q0 -> 1 | Q1 _ -> 2)
    | Q0 -> 0
  let width =
    match w with
    | W1 ws -> Array.length ws
    | W0 -> 0
  let one : f32 = 1.0
  let lanes = [ { v = F32x4.splat one; n = 3 } ]
  let vs = [| F32x4.splat one |]
  let vr = ref (F32x4.splat one)
  let vb = Buffer.ofArray [| F32x4.splat one |]
  println $"{xs} {apply (fun x -> x * 2) 21} {unsafe (Ptr.read p)} {Buffer.length b} {count (Node [ Leaf; Node [ Leaf; Leaf ] ])} {depth} {width} {(List.head lanes).n + Array.length vs + Buffer.length vb} {F32x4.sum vr.Value}"
  unsafe (Ptr.free p)
  0
