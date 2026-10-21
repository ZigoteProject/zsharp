// let rec … and …: functions that call each other, at the top level and locally
let rec isEven n = if n = 0 then true else isOdd (n - 1)
and isOdd n = if n = 0 then false else isEven (n - 1)

// generic, and sharing a type variable across the group
let rec evens (xs: list<'a>) =
  match xs with
  | [] -> []
  | x :: rest -> x :: odds rest
and odds (xs: list<'a>) =
  match xs with
  | [] -> []
  | _ :: rest -> evens rest

// a tiny expression parser: mutually recursive descent over a list of tokens
type Tok =
  | Num of int
  | Plus
  | Times

let rec sum toks =
  let (v, rest) = product toks
  match rest with
  | Plus :: more ->
    let (w, after) = sum more
    (v + w, after)
  | _ -> (v, rest)
and product toks =
  let (v, rest) = atom toks
  match rest with
  | Times :: more ->
    let (w, after) = product more
    (v * w, after)
  | _ -> (v, rest)
and private atom toks =
  match toks with
  | Num n :: rest -> (n, rest)
  | _ -> (0, toks)

let private secret = 41

let collatzSteps start =
  let limit = 1000
  // local mutual recursion, capturing `limit`
  let rec down n steps = if n = 1 || steps > limit then steps else if n % 2 = 0 then down (n / 2) (steps + 1) else up n steps
  and up n steps = down (3 * n + 1) (steps + 1)
  down start 0

let main () =
  println $"{isEven 10} {isOdd 7} {isEven 7}"
  println $"{evens [ 1; 2; 3; 4; 5 ]} {odds [ "a"; "b"; "c" ]}"
  println $"{fst (sum [ Num 2; Plus; Num 3; Times; Num 4 ])} {collatzSteps 27} {secret + 1}"
  println $"{isEven 1000000}"
  0
