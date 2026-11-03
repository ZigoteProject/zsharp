// An interpreter: a small imperative language is tokenized, parsed by recursive descent into a
// syntax tree (variables resolved to slots), and run by walking the tree: counting the primes
// below n and the Collatz steps of every number below n / 4. What a compiler or a scripting
// engine does: matching on unions, recursion, and a tree shared by every iteration.
let source =
  """
count = 0;
i = 2;
while i < n {
  prime = 1;
  j = 2;
  while j * j <= i {
    if i % j == 0 { prime = 0; j = i; }
    j = j + 1;
  }
  count = count + prime;
  i = i + 1;
}
steps = 0;
k = 1;
while k < n / 4 {
  x = k;
  while x > 1 {
    if x % 2 == 0 { x = x / 2; } else { x = 3 * x + 1; }
    steps = steps + 1;
  }
  k = k + 1;
}
"""

type Token =
  | TNum of int
  | TName of string
  | TSym of string

type Op =
  | Add
  | Sub
  | Mul
  | Div
  | Mod
  | Lt
  | Le
  | Gt
  | Ge
  | Eq
  | Ne

type Expr =
  | Num of int
  | Var of int
  | Bin of Op * Expr * Expr

type Stmt =
  | Assign of int * Expr
  | While of Expr * list<Stmt>
  | If of Expr * list<Stmt> * list<Stmt>

let isDigit (b: u8) = b >= u8 '0' && b <= u8 '9'
let isAlpha (b: u8) = b >= u8 'a' && b <= u8 'z'
let isSpace (b: u8) = b = u8 ' ' || b = u8 '\n' || b = u8 '\t' || b = u8 '\r'

let tokenize (s: string) =
  let bytes = String.bytes s
  let n = Span.length bytes
  let tokens = Buffer.empty
  let mutable i = 0
  while i < n do
    let b = bytes.[i]
    let start = i
    if isSpace b then
      i <- i + 1
    else if isDigit b then
      while i < n && isDigit bytes.[i] do
        i <- i + 1
      Buffer.push (TNum (Option.defaultValue 0 (String.parseInt (String.sub s start (i - start))))) tokens
    else if isAlpha b then
      while i < n && isAlpha bytes.[i] do
        i <- i + 1
      Buffer.push (TName (String.sub s start (i - start))) tokens
    else
      // two-character operators first
      let two = if i + 1 < n then String.sub s i 2 else ""
      let len = if two = "<=" || two = ">=" || two = "==" || two = "!=" then 2 else 1
      Buffer.push (TSym (String.sub s i len)) tokens
      i <- i + len
  Buffer.toArray tokens

/// The parser's state: the tokens, the next one's index, and each variable's slot.
type Parser = { tokens: array<Token>; pos: ref<int>; slots: ref<HashMap<string, int>> }

let peek (p: Parser) = if p.pos.Value < Array.length p.tokens then Some p.tokens.[p.pos.Value] else None

let advance (p: Parser) = p.pos.Value <- p.pos.Value + 1

let expect (p: Parser) (sym: string) =
  match peek p with
  | Some (TSym s) when s = sym -> advance p
  | t -> panic $"expected {sym}, found {t}"

let slot (p: Parser) (name: string) =
  match HashMap.tryFind name p.slots.Value with
  | Some i -> i
  | None ->
    let i = HashMap.count p.slots.Value
    p.slots.Value <- HashMap.add name i p.slots.Value
    i

let rec primary (p: Parser) : Expr =
  match peek p with
  | Some (TNum v) ->
    advance p
    Num v
  | Some (TName name) ->
    advance p
    Var (slot p name)
  | Some (TSym "(") ->
    advance p
    let e = comparison p
    expect p ")"
    e
  | t -> panic $"unexpected {t}"

// a left-associative level: operands from `operand`, operators from `op`
and binary (p: Parser) (operand: Parser -> Expr) (op: string -> option<Op>) : Expr =
  let mutable left = operand p
  let mutable going = true
  while going do
    match peek p with
    | Some (TSym s) ->
      match op s with
      | Some o ->
        advance p
        left <- Bin (o, left, operand p)
      | None -> going <- false
    | _ -> going <- false
  left

and product (p: Parser) =
  binary p primary (fun s ->
    match s with
    | "*" -> Some Mul
    | "/" -> Some Div
    | "%" -> Some Mod
    | _ -> None)

and sum (p: Parser) =
  binary p product (fun s ->
    match s with
    | "+" -> Some Add
    | "-" -> Some Sub
    | _ -> None)

and comparison (p: Parser) =
  binary p sum (fun s ->
    match s with
    | "<" -> Some Lt
    | "<=" -> Some Le
    | ">" -> Some Gt
    | ">=" -> Some Ge
    | "==" -> Some Eq
    | "!=" -> Some Ne
    | _ -> None)

let rec block (p: Parser) : list<Stmt> =
  expect p "{"
  let body = statements p
  expect p "}"
  body

and statements (p: Parser) : list<Stmt> =
  match peek p with
  | None
  | Some (TSym "}") -> []
  | Some _ ->
    let s = statement p
    s :: statements p

and statement (p: Parser) : Stmt =
  match peek p with
  | Some (TName "while") ->
    advance p
    let cond = comparison p
    While (cond, block p)
  | Some (TName "if") ->
    advance p
    let cond = comparison p
    let yes = block p
    match peek p with
    | Some (TName "else") ->
      advance p
      If (cond, yes, block p)
    | _ -> If (cond, yes, [])
  | Some (TName name) ->
    advance p
    let target = slot p name
    expect p "="
    let e = comparison p
    expect p ";"
    Assign (target, e)
  | t -> panic $"unexpected {t}"

let rec eval (env: Buffer<int>) (e: Expr) : int =
  match e with
  | Num v -> v
  | Var i -> env.[i]
  | Bin (op, a, b) ->
    let x = eval env a
    let y = eval env b
    match op with
    | Add -> x + y
    | Sub -> x - y
    | Mul -> x * y
    | Div -> x / y
    | Mod -> x % y
    | Lt -> if x < y then 1 else 0
    | Le -> if x <= y then 1 else 0
    | Gt -> if x > y then 1 else 0
    | Ge -> if x >= y then 1 else 0
    | Eq -> if x = y then 1 else 0
    | Ne -> if x <> y then 1 else 0

let rec exec (env: Buffer<int>) (stmts: list<Stmt>) =
  match stmts with
  | [] -> ()
  | s :: rest ->
    match s with
    | Assign (i, e) -> env.[i] <- eval env e
    | While (cond, body) ->
      while eval env cond <> 0 do
        exec env body
    | If (cond, yes, no) -> if eval env cond <> 0 then exec env yes else exec env no
    exec env rest

let main () =
  let n =
    match Environment.args () with
    | a :: _ -> Option.defaultValue 300000 (String.parseInt a)
    | [] -> 300000
  let p = { tokens = tokenize source; pos = ref 0; slots = ref (HashMap.add "n" 0 HashMap.empty) }
  let program = statements p
  let names = HashMap.toList p.slots.Value |> List.sortBy snd
  let env = Buffer.create (List.length names) 0
  env.[0] <- n
  exec env program
  for (name, i) in names do
    println $"{name} = {env.[i]}"
  0
