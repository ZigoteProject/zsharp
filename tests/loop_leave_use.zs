// a use value is disposed when its scope is left by break, continue or return (proposal 0029)
type Res = { name: string }

impl Dispose<Res> =
  let dispose (r: Res) = println $"  dispose {r.name}"

let rounds (xs: list<int>) : int =
  use outer = { name = "outer" }
  for x in xs do
    use r = { name = $"round {x}" }
    if x = 2 then continue
    if x = 4 then break
    if x = 9 then return -1
    println $"  work {x}"
  0

let early (n: int) : string =
  use a = { name = "a" }
  if n = 0 then return "zero"
  use b = { name = "b" }
  let s =
    match n with
    | 1 -> return "one"
    | _ -> $"{n}"
  s + "!"

let main () =
  println $"{rounds [ 1; 2; 3; 4; 5 ]}"
  println $"{rounds [ 1; 9; 3 ]}"
  println (early 0)
  println (early 1)
  println (early 7)
