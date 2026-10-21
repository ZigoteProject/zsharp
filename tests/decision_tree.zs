// Matches compiled to decision trees: nested patterns, or-patterns, guards that fall through,
// literals and tuples. A part reached on several paths is shared as a join point, and cells are
// reused through it; ZS_LEAKCHECK and valgrind check the reference counts.

type Expr =
  | Num of int
  | Var of string
  | Add of Expr * Expr
  | Mul of Expr * Expr
  | Neg of Expr

let rec simplify e =
  match e with
  | Add (Num 0, x) | Add (x, Num 0) -> simplify x
  | Mul (Num 1, x) | Mul (x, Num 1) -> simplify x
  | Mul (Num 0, _) | Mul (_, Num 0) -> Num 0
  | Neg (Neg x) -> simplify x
  | Neg (Num n) -> Num (0 - n)
  | Add (Num a, Num b) -> Num (a + b)
  | Mul (Num a, Num b) when a < 1000 && b < 1000 -> Num (a * b)
  | Add (a, b) -> Add (simplify a, simplify b)
  | Mul (a, b) -> Mul (simplify a, simplify b)
  | Neg a -> Neg (simplify a)
  | e -> e

let rec render e =
  match e with
  | Num n when n < 0 -> $"({n})"
  | Num n -> $"{n}"
  | Var v -> v
  | Add (a, b) -> $"({render a} + {render b})"
  | Mul (a, b) -> $"{render a} * {render b}"
  | Neg a -> $"-{render a}"

let rec dedup xs =
  match xs with
  | a :: (b :: _ as rest) when a = b -> dedup rest
  | a :: rest -> a :: dedup rest
  | [] -> []

let rec merge xs ys =
  match (xs, ys) with
  | ([], ys) -> ys
  | (xs, []) -> xs
  | (x :: xt, y :: yt) -> if x <= y then x :: merge xt ys else y :: merge xs yt

let command verb n =
  match (verb, n) with
  | ("add", 0) | ("sub", 0) -> "nothing"
  | ("add", n) -> $"+{n}"
  | ("sub", n) -> $"-{n}"
  | (_, 0) -> "zero"
  | (v, n) -> $"{v} {n}"

// a tree whose leaves return unit
let describe e =
  match e with
  | Add (Num 0, _) | Add (_, Num 0) -> println "adds zero"
  | Mul (Num 0, _) | Mul (_, Num 0) -> println "times zero"
  | Neg (Neg _) -> println "negates twice"
  | _ -> println "other"

let show (xs: list<int>) = String.join " " (List.map (fun x -> $"{x}") xs)

let main () =
  let exprs =
    [ Add (Mul (Num 1, Add (Var "x", Num 0)), Neg (Neg (Mul (Num 3, Num 4))))
      Mul (Num 0, Var "y")
      Mul (Var "y", Num 0)
      Neg (Num 5)
      Mul (Num 2000, Num 3)
      Add (Num 2, Num 3)
      Add (Num 0, Num 0)
      Neg (Add (Var "z", Mul (Num 1, Num 1))) ]
  for e in exprs do
    println $"{render e} => {render (simplify e)}"
  for e in exprs do
    describe e
  println (show (dedup [ 1; 1; 2; 3; 3; 3; 1 ]))
  println (show (merge [ 1; 4; 6 ] [ 2; 3; 7; 8 ]))
  println (show (merge [] [ 5 ]))
  for (v, n) in [ ("add", 0); ("sub", 0); ("add", 5); ("sub", 2); ("mul", 0); ("mul", 3) ] do
    println (command v n)
  0
