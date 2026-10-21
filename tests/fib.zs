// Phase 0 exit test
extern printf : cstr -> ... -> c_int

let rec fib n =
  if n < 2 then n
  else fib (n - 1) + fib (n - 2)

let main () =
  printf "fib 30 = %ld\n" (fib 30)
  0
