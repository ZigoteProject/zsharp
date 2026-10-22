// function | p -> … | q -> …: a lambda matching its one argument
type Shape =
  | Circle of float
  | Square of float

let area =
  function
  | Circle r -> 3.0 * r * r
  | Square a -> a * a

let describe = function | 0 -> "none" | 1 -> "one" | _ -> "many"

let main () =
  println $"{area (Circle 1.0)} {area (Square 2.0)}"
  println $"{describe 0} {describe 1} {describe 5}"
  // its parameter type comes from the call, as a lambda's does
  let sizes = [ Some 3; None; Some 5 ] |> List.map (function Some x -> x | None -> 0)
  println $"{sizes}"
  let total =
    [ (1, "a"); (2, "b") ]
    |> List.sumBy (function
      | (n, "a") -> n * 10
      | (n, _) -> n)
  println $"{total}"
  0
