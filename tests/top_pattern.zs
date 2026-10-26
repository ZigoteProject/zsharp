// Patterns at the top level (0006): a value for each variable. A tuple against a tuple (or a
// constant that is one) splits, so the parts that are constants stay constants; anything else is
// computed once at startup, in declaration order, and each variable taken from it.
type Point = { x: int; y: int }

let divmod (a: int) (b: int) = (a / b, a % b)

let (width, height) = (800, 600)
let (lo, (mid, hi)) = (1, (2, 3))
let corner = (10, 20)
let (left, top) = corner
let (first, second) as pair = (String.length "ab", 2)
let { x = px; y = py } = { x = 3; y = 4 }
let (quotient, remainder) = divmod 17 5
let (u, v): int * string = (7, "seven")
let (n, _) = (List.length [ 1; 2; 3 ], println "startup: a tuple's parts in order")
let _ = println "startup: a wildcard's value runs too"
// a generic constant stays generic: empty is a map of any type
let (empty, zero) = (Map.empty, 0)

let main () =
  println $"{width}x{height} {lo} {mid} {hi} {left},{top}"
  println $"{first} {second} {pair} {px},{py} {quotient} r {remainder} {u} {v} {n}"
  let names : Map<string, int> = Map.add "a" 1 empty
  let flags : Map<int, bool> = Map.add 2 true empty
  println $"{Map.count names} {Map.count flags} {zero}"
  // a local let's pattern takes an annotation too
  let (a, b): int * string = (1, "one")
  println $"{a} {b}"
  0
