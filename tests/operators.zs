// Custom operators: defined with let (op), used infix at the precedence of their first
// character (as in F#), and as values with (op).

// ---- railway-oriented programming over result
let (>>=) r f = Result.bind f r
let (>=>) f g x = f x >>= g
let (<!>) f r = Result.map f r

let parseInt (s: string) =
  match String.parseInt s with
  | Some n -> Ok n
  | None -> Error $"not a number: {s}"

let positive n = if n > 0 then Ok n else Error $"not positive: {n}"
let half n = if n % 2 = 0 then Ok (n / 2) else Error $"odd: {n}"

let validate = parseInt >=> positive >=> half

// ---- a small parser combinator library
type Parser<'a> = Parser of (list<char> -> option<'a * list<char>>)

let run p (s: string) =
  match p with
  | Parser f -> f (String.chars s)

let (<|>) p q =
  match (p, q) with
  | (Parser f, Parser g) ->
    let either cs =
      match f cs with
      | Some r -> Some r
      | None -> g cs
    Parser either

let (.>>.) p q =
  match (p, q) with
  | (Parser f, Parser g) ->
    let both cs =
      match f cs with
      | Some (a, rest) ->
        match g rest with
        | Some (b, rest2) -> Some ((a, b), rest2)
        | None -> None
      | None -> None
    Parser both

let (|>>) p h =
  match p with
  | Parser f -> Parser (fun cs -> f cs |> Option.map (fun (a, rest) -> (h a, rest)))

let (.>>) p q = p .>>. q |>> fst
let (>>.) p q = p .>>. q |>> snd

let satisfy ok =
  let one cs =
    match cs with
    | c :: rest when ok c -> Some (c, rest)
    | _ -> None
  Parser one

let many p =
  match p with
  | Parser f ->
    let rec go acc cs =
      match f cs with
      | Some (a, rest) -> go (a :: acc) rest
      | None -> Some (List.rev acc, cs)
    Parser (fun cs -> go [] cs)

let pchar c = satisfy (fun x -> x = c)
let spaces = many (pchar ' ')
let token p = p .>> spaces
let digits = satisfy Char.isDigit .>>. many (satisfy Char.isDigit) |>> fun (d, ds) -> d :: ds
let number =
  token digits |>> fun ds -> List.fold (fun n d -> n * 10 + Option.get (Char.digitValue d)) 0 ds
let sign = token (pchar '+') <|> token (pchar '-')
let sum =
  number
  .>>. many (sign .>>. number)
  |>> fun (first, rest) ->
    List.fold (fun acc (s, n) -> if s = '+' then acc + n else acc - n) first rest

// ---- the other precedence classes
let (=~) (a: f64) (b: f64) = a - b < 0.001 && b - a < 0.001 // like =, so tighter than &&
let (@@) f x = f x // like ::, right-associative
let (+.) a b = a + b + 1 // like +
let ( *. ) a b = a * b * 10 // like *
let rec ( ** ) (a: int) (b: int) = if b = 0 then 1 else a * (a ** (b - 1)) // right-associative

// prefix operators start with ! (but not !=) or ~, and bind tighter than application
let (!) (r: ref<int>) = r.Value
let (~~) x = -x
let (!=) a b = a <> b // infix
let (<+) a b = a * 2 + b // ends in a sign, still one operator before )

module Vec =
  let (|+|) (ax, ay) (bx, by) = (ax + bx, ay + by)

module Shapes =
  open Vec

  let moved = (1, 2) |+| (3, 4) |+| (10, 10)

let main () =
  println $"{validate "84"} {validate "-4"} {validate "21"} {validate "x"}"
  println $"{"42" |> parseInt >>= positive} {(fun x -> x + 1) <!> Ok 1} {Ok 5 >>= fun x -> Ok (x * 2)}"
  let r =
    "84"
    |> parseInt
    >>= positive
    >>= half
  println $"{r}"
  println $"{run sum "12 + 30 - 2"} {run sum "7"} {run sum "x"}"
  println $"{0.1 + 0.2 =~ 0.3 && true} {List.rev @@ List.map (fun x -> x * 2) @@ [ 1; 2; 3 ]} {1 +. 2 *. 3} {2 ** 3 ** 2}"
  println $"{List.fold (+) 0 [ 1; 2; 3 ]} {List.map ((*) 2) [ 1; 2 ]} {(-) 10 3} {List.map ((=) 2) [ 1; 2 ]} {(>>=) (Ok 4) half}"
  let (<+>) a b = a * 10 + b
  println $"{1 <+> 2 <+> 3} {Shapes.moved} {[ 1; 2 ] |> List.length = 2}"
  let counter = ref 41
  counter.Value <- !counter + 1
  println $"{!counter} {string !counter} {~~5} {3 != 4} {List.map (!) [ ref 1; ref 2 ]} {1 <+ 2}"
  0
