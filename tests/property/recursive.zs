// derived Arbitrary on recursive types: the cases that end a value (none of their fields holds
// the type) come first, and are the only choice at size 0 or past a replayed stream's end, so a
// type whose base case has fields, one recursive through a list, and types that hold each other
// all make finite values, and zero bytes make the simplest. Gen.range across all of int, and
// Gen.char's scalar values
open Testing

[<Derive(Arbitrary)>]
type Tree =
  | Node of Tree * Tree
  | Leaf of int

[<Derive(Arbitrary)>]
type Rose = Rose of int * list<Rose>

[<Derive(Arbitrary)>]
type Expr =
  | Block of list<Stmt>
  | Num of int

and Stmt = { label: string; body: Expr }

let rec leaves (t: Tree) : int =
  match t with
  | Leaf _ -> 1
  | Node(l, r) -> leaves l + leaves r

let rec roses (r: Rose) : int =
  match r with
  | Rose(_, kids) -> 1 + List.sumBy roses kids

let rec nums (e: Expr) : int =
  match e with
  | Num _ -> 1
  | Block ss -> List.sumBy (fun (s: Stmt) -> nums s.body) ss

let main () =
  // no bytes at all: every draw past the end is a zero, and the values end at once
  println $"{Gen.draw (arbitrary () : Gen<Tree>) (Source.ofBytes [||] 100)}"
  println $"{Gen.draw (arbitrary () : Gen<Rose>) (Source.ofBytes [||] 100)}"
  println $"{Gen.draw (arbitrary () : Gen<Expr>) (Source.ofBytes [||] 100)}"
  // bytes that pick the recursive case each time, until they run out
  println $"{leaves (Gen.draw (arbitrary () : Gen<Tree>) (Source.ofBytes (Array.create 40 (u8 255)) 100))}"
  println $"{Gen.sample (u64 7) 8 (Gen.map leaves (arbitrary ()))}"
  println $"{Gen.sample (u64 7) 8 (Gen.map roses (arbitrary ()))}"
  println $"{Gen.sample (u64 7) 8 (Gen.map nums (arbitrary ()))}"
  // a range across all of int, and at one end of it
  let least = -9223372036854775807 - 1
  let wide = Gen.sample (u64 7) 200 (Gen.range least 9223372036854775807)
  println $"{List.exists (fun n -> n < -4611686018427387904) wide} {List.exists (fun n -> n > 4611686018427387904) wide}"
  println $"{Gen.sample (u64 7) 4 (Gen.range least (least + 3))}"
  println $"{Gen.sample (u64 7) 3 (Gen.range -5 -5)}"
  // characters: never a surrogate, and now and then one past the 16-bit range
  let cs = Gen.sample (u64 3) 3000 (Gen.char ())
  println $"surrogates {List.length (List.filter (fun (c: char) -> int c >= 0xD800 && int c <= 0xDFFF) cs)}"
  println $"above U+FFFF {List.exists (fun (c: char) -> int c > 0xFFFF) cs}"
  Testing.runAll [
    testList "recursive" [
      testProperty "a tree has a leaf" (fun (t: Tree) -> leaves t >= 1)
      testProperty "a rose has a root" (fun (r: Rose) -> roses r >= 1)
      testProperty "statements end" (fun (e: Expr) -> nums e >= 0)
    ]
  ]
