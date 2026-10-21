// Phase 1 exit test: an evaluator for a tiny expression language
extern printf : cstr -> ... -> c_int

type Expr =
  | Num of int
  | Var of slot: int
  | Add of Expr * Expr
  | Mul of Expr * Expr
  | Neg of Expr
  | IfPos of cond: Expr * Expr * Expr
  | Let of slot: int * value: Expr * body: Expr

type Env =
  | Empty
  | Bind of int * int * Env

type Stats = { steps: int; maxDepth: int }

let rec lookup env slot =
  match env with
  | Empty -> 0
  | Bind (s, v, _) when s = slot -> v
  | Bind (_, _, rest) -> lookup rest slot

let step (st: Stats) depth =
  { steps = st.steps + 1
    maxDepth = if depth > st.maxDepth then depth else st.maxDepth }

let rec eval env e depth st =
  let st = step st depth
  match e with
  | Num n -> (n, st)
  | Var slot -> (lookup env slot, st)
  | Add (a, b) ->
      let (x, st) = eval env a (depth + 1) st
      let (y, st) = eval env b (depth + 1) st
      (x + y, st)
  | Mul (a, b) ->
      let (x, st) = eval env a (depth + 1) st
      let (y, st) = eval env b (depth + 1) st
      (x * y, st)
  | Neg a ->
      let (x, st) = eval env a (depth + 1) st
      (-x, st)
  | IfPos (c, t, f) ->
      let (x, st) = eval env c (depth + 1) st
      if x > 0 then eval env t (depth + 1) st
      else eval env f (depth + 1) st
  | Let (slot, v, body) ->
      let (x, st) = eval env v (depth + 1) st
      eval (Bind (slot, x, env)) body (depth + 1) st

let rec simplify e =
  match e with
  | Add (Num 0, x) | Add (x, Num 0) | Mul (Num 1, x) | Mul (x, Num 1) -> simplify x
  | Mul (Num 0, _) | Mul (_, Num 0) -> Num 0
  | Add (a, b) -> Add (simplify a, simplify b)
  | Mul (a, b) -> Mul (simplify a, simplify b)
  | Neg (Neg x) -> simplify x
  | Neg x -> Neg (simplify x)
  | IfPos (c, t, f) -> IfPos (simplify c, simplify t, simplify f)
  | Let (s, v, b) -> Let (s, simplify v, simplify b)
  | Num _ | Var _ -> e

let rec size e =
  match e with
  | Num _ | Var _ -> 1
  | Add (a, b) | Mul (a, b) | Let (_, a, b) -> 1 + size a + size b
  | Neg a -> 1 + size a
  | IfPos (a, b, c) -> 1 + size a + size b + size c

let rec show e =
  match e with
  | Num n -> printf "%ld" n |> ignore
  | Var s -> printf "x%ld" s |> ignore
  | Add (a, b) ->
      printf "(" |> ignore
      show a
      printf " + " |> ignore
      show b
      printf ")" |> ignore
  | Mul (a, b) ->
      printf "(" |> ignore
      show a
      printf " * " |> ignore
      show b
      printf ")" |> ignore
  | Neg a ->
      printf "-" |> ignore
      show a
  | IfPos (c, t, f) ->
      printf "(if " |> ignore
      show c
      printf " > 0 then " |> ignore
      show t
      printf " else " |> ignore
      show f
      printf ")" |> ignore
  | Let (s, v, b) ->
      printf "(let x%ld = " s |> ignore
      show v
      printf " in " |> ignore
      show b
      printf ")" |> ignore

let main () =
  let prog =
    Let (0, Add (Num 3, Num 4),
      Add (IfPos (Var 0, Mul (Var 0, Add (Num 0, Num 10)), Neg (Num 1)),
           Mul (Num 1, Neg (Var 0))))
  show prog
  printf "\n" |> ignore
  let (v, st) = eval Empty prog 0 { steps = 0; maxDepth = 0 }
  printf "value = %ld, steps = %ld, depth = %ld\n" v st.steps st.maxDepth |> ignore
  let small = simplify prog
  show small
  printf "\n" |> ignore
  let (v2, st2) = eval Empty small 0 { steps = 0; maxDepth = 0 }
  printf "value = %ld, steps = %ld, size %ld -> %ld\n" v2 st2.steps (size prog) (size small) |> ignore
  if v = v2 then 0 else 1
