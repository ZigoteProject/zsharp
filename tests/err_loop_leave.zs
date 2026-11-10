// break, continue and return where they can't be (proposal 0029)
let outside () =
  break

let inLambda (xs: list<int>) =
  for x in xs do
    List.iter (fun y -> if y = x then break) xs

let wrongType () : int =
  if true then return "one"
  1

let unreachable (xs: list<int>) =
  for x in xs do
    continue
    println $"{x}"

let argument (x: int) : int =
  abs (return 1)

let computedStep (n: int) =
  for i in 0 .. n .. 10 do
    if i = 4 then break

let value = return 5

let main () = ()
