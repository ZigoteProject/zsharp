// Record patterns: { field = pattern; ... }, fields left out match anything
type Point = { x: int; y: int }

type Kind =
  | Circle
  | Square

type Shape = { kind: Kind; size: int; label: string }

type Stack<'a> = { items: list<'a>; depth: int }

let quadrant p =
  match p with
  | { x = 0; y = 0 } -> "origin"
  | { x = 0 } -> "on the y axis"
  | { y = 0 } -> "on the x axis"
  | { x = x; y = y } when x > 0 && y > 0 -> "first"
  | _ -> "elsewhere"

let describe s =
  match s with
  | { kind = Circle; size = n; label = l } -> $"circle {n} {l}"
  | { kind = Square; label = l } -> $"square {l}"

let top (s: Stack<'a>) =
  match s with
  | { items = x :: _ } -> Some x
  | { items = [] } -> None

let norm { x = x; y = y } = x * x + y * y

let main () =
  println $"{quadrant { x = 0; y = 0 }} | {quadrant { x = 0; y = 5 }} | {quadrant { x = 3; y = 0 }} | {quadrant { x = 2; y = 2 }} | {quadrant { x = -1; y = 2 }}"
  println $"{describe { kind = Circle; size = 3; label = "c" }} | {describe { kind = Square; size = 1; label = "s" }}"
  let { x = a; y = b } = { x = 4; y = 5 }
  println $"let {a} {b} | norm {norm { x = 3; y = 4 }} | lambda {List.map (fun { x = x } -> x) [ { x = 7; y = 0 }; { x = 8; y = 0 } ]}"
  println $"stack {top { items = [ "a"; "b" ]; depth = 2 }} {top ({ items = []; depth = 0 }: Stack<int>)}"
  let shapes =
    [ { kind = Circle; size = 2; label = "one" }; { kind = Square; size = 5; label = "two" } ]
  let mutable total = 0
  for { size = n; label = l } in shapes do
    total <- total + n
    print $"{l} "
  println $"{total}"
  match Some { x = 1; y = 2 } with
  | Some { y = y } -> println $"nested {y}"
  | None -> println "none"
  0
