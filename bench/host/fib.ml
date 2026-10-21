(* Recursive Fibonacci: calls and integer arithmetic (63-bit, wrapping on overflow). *)
let rec fib n = if n < 2 then n else fib (n - 1) + fib (n - 2)

let () =
  let n = if Array.length Sys.argv > 1 then int_of_string Sys.argv.(1) else 32 in
  Printf.printf "%d\n" (fib n)
