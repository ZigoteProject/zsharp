// Uncurrying: a closure applied to several arguments calls code taking them all at once when
// it takes exactly that many, instead of building a closure per argument; and a function whose
// body is a lambda takes the lambda's parameters. Every way of applying must still give the
// same results, with closures over heap values freed (ZS_LEAKCHECK, valgrind).
let add x = fun y -> x + y

let add3 (a: string) = fun (b: string) (c: string) -> a + b + c

let twice (f: int -> int -> int) (x: int) = f (f x x) x

let apply3 (f: string -> string -> string -> string) = f "a" "b" "c"

let rec countdown n = fun (acc: list<int>) -> if n = 0 then acc else countdown (n - 1) (n :: acc)

let main () =
  // a closure that captures, applied to two arguments a thousand times: no closure per call
  let k = 3
  let xs = List.init 1000 (fun i -> i)
  let before = Runtime.allocations ()
  let total = List.fold (fun acc x -> acc + x * k) 0 xs
  let allocated = Runtime.allocations () - before
  println $"fold {total} with {allocated} allocations"
  // over, exactly and partially applied
  let inc = add 1
  println $"{add 1 2} {inc 10} {twice (fun a b -> a * b + k) 2}"
  let s = "s"
  let ab = add3 "a" "b"
  let a = add3 "a"
  println $"{add3 "x" "y" "z"} {ab "c"} {a "b" "c"} {apply3 (fun x y z -> z + y + x + s)} {apply3 add3}"
  // a closure with fewer parameters than the call has arguments: the rest go to its result
  let pick (b: bool) = if b then (fun (x: string) -> fun (y: string) -> x) else (fun x -> fun y -> y)
  let first = pick true
  println $"{first "left" "right"} {pick false "left" "right"}"
  // a curried local function, recursive
  let rec range lo = fun hi -> if lo > hi then [] else lo :: range (lo + 1) hi
  println $"{range 1 5} {countdown 3 []}"
  // a closure applied to more arguments than its function takes, through a list of them
  let ops = [ (fun (a: int) (b: int) -> a + b); (fun a -> fun b -> a * b); add ]
  println $"{ops |> List.map (fun f -> f 6 7)}"
  let partial = ops |> List.map (fun f -> f 2)
  println $"{partial |> List.map (fun g -> g 10)}"
  // closures holding strings: freed whichever way they're called
  let greet (greeting: string) = fun (name: string) (mark: string) -> greeting + ", " + name + mark
  let hello = greet "hello"
  let hi = hello "you"
  println $"{hello "world" "!"} {hi "?"} {greet "hey" "there" "."}"
  0
