extern printf : cstr -> ... -> c_int
extern abs : c_int -> c_int

let square (x: int) : int = x * x

let sign x =
  if x < 0 then -1
  else if x = 0 then 0
  else 1

let report (label: cstr) (v: int) =
  printf "%s = %ld\n" label v |> ignore

let main () =
  let a = square 7
  let b = sign (0 - 5)
  report "square 7" a
  report "sign -5" b
  printf "abs(-3) = %d\n" (abs (-3)) |> ignore
  if a > 40 && not (b = 0) then
    report "and/not" 1
  printf "%d %d\n" true (10 % 3 = 2) |> ignore
  let msg =
    if a = 49 then "nested \"ok\""
    else "bad"
  a
  |> square
  |> report msg
  0
