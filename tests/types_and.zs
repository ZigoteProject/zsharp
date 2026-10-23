// Types that name each other, as in F#: type A = … and B = …, each body naming the others
type Expr = { shape: Shape; at: int }

and Shape =
  | Lit of int
  | Add of Expr * Expr
  | Neg of Expr

and private Env = { values: list<Expr> }

let rec eval (e: Expr) : int =
  match e.shape with
  | Lit n -> n
  | Add (a, b) -> eval a + eval b
  | Neg a -> -(eval a)

let lit n = { shape = Lit n; at = n }

let main () =
  let e = { shape = Add (lit 1, { shape = Neg (lit 5); at = 9 }); at = 0 }
  let env = { values = [ e; lit 2 ] }
  println $"{eval e} {e} {e = e} {List.length env.values}"
  0
