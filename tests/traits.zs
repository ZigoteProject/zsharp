// Phase 3: traits, impls, operators on user types, inferred impl requirements
trait Describe<'a> =
  abstract describe : 'a -> string
  abstract kind : 'a -> int

type Vec = { x: f64; y: f64 }

type Tree<'a> =
  | Leaf
  | Node of Tree<'a> * 'a * Tree<'a>

impl Describe<int> =
  let describe n = $"int {n}"
  let kind _ = 1

impl Describe<Vec> =
  let describe v = $"vec({v.x}, {v.y})"
  let kind _ = 2

// needs Describe<'a> for the elements; inferred from the body
impl Describe<list<'a>> =
  let describe xs =
    match xs with
    | [] -> "[]"
    | x :: rest -> describe x + " :: " + describe rest
  let kind xs = 3

impl Add<Vec> =
  let add a b = { x = a.x + b.x; y = a.y + b.y }
  let zero = { x = 0.0; y = 0.0 }

impl Num<Vec> =
  let sub a b = { x = a.x - b.x; y = a.y - b.y }
  let mul a b = { x = a.x * b.x; y = a.y * b.y }
  let div a b = { x = a.x / b.x; y = a.y / b.y }
  let rem a b = a
  let neg a = { x = -a.x; y = -a.y }

impl Eq<Vec> =
  let equal a b = a.x = b.x && a.y = b.y

impl Show<Vec> =
  let show v = $"<{v.x}, {v.y}>"

impl Show<Tree<'a>> =
  let show t =
    match t with
    | Leaf -> "."
    | Node (l, v, r) -> $"({show l} {v} {show r})"

// generic over any Describe
let twice x = describe x + " / " + describe x

let main () =
  println (describe 42)
  println (twice { x = 1.0; y = 2.0 })
  println (describe [ 1; 2; 3 ])
  println $"kinds {kind 5 + kind [ 7 ]}"
  let a = { x = 1.0; y = 2.0 }
  let b = { x = 0.5; y = 0.5 }
  println $"vec {a + b} {a - b} {-a} {a = b} {a <> b} {a + b = { x = 1.5; y = 2.5 }}"
  println $"sums {List.sum [ a; b; a ]} {List.sum [ 1.5; 2.5 ]} {List.sum [ 1; 2; 3 ]}"
  println $"tree {Node (Node (Leaf, 1, Leaf), 2, Leaf)}"
  let (b1, a1) = ("b", "a")
  println $"compare {compare 1 2} {compare b1 a1} {compare 2.0 2.0} hash {hash 7} {hash a1 = hash a1}"
  0
