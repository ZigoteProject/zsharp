// Phase 3: active patterns (total, partial, parameterized)
let (|Even|Odd|) n = if n % 2 = 0 then Even else Odd

let (|Sign|) n = Sign (if n < 0 then -1 else if n > 0 then 1 else 0)

let (|Positive|_|) n = if n > 0 then Some n else None

let (|DivBy|_|) d n = if n % d = 0 then Some (n / d) else None

let parity n =
  match n with
  | Even -> "even"
  | Odd -> "odd"

let fizz n =
  match n with
  | DivBy 15 _ -> "FizzBuzz"
  | DivBy 3 _ -> "Fizz"
  | DivBy 5 _ -> "Buzz"
  | _ -> string n

let classify n =
  match n with
  | 0 -> "zero"
  | Positive p when p > 100 -> "big"
  | Positive _ -> "positive"
  | Sign s -> $"sign {s}"

let main () =
  println $"{parity 4} {parity 7}"
  for i in 9 .. 15 do
    print $"{fizz i} "
  println ""
  println $"{classify 0} {classify 500} {classify 5} {classify (-3)}"
  0
