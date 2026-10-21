// Recursive Fibonacci: calls and integer arithmetic (checked for overflow, as always).
let rec fib n = if n < 2 then n else fib (n - 1) + fib (n - 2)

let main () =
  let n =
    match Environment.args () with
    | a :: _ -> Option.defaultValue 32 (String.parseInt a)
    | [] -> 32
  println $"{fib n}"
  0
