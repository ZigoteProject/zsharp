// F#'s list and array ranges: [a .. b], [a .. step .. b] and [| … |], the list expression over
// the range (empty when the range is: [10 .. 1]), and typed tuple parameters, (a: int, b: int),
// one tuple parameter with its type (what the README called not there yet)
let sum (a: int, b: int) = a + b

let describe (name: string, count: int, unit: string) = $"{count} {unit} of {name}"

let apply (f: int * int -> int) = f (3, 4)

let main () =
  println $"{[ 1 .. 5 ]} {[ 1 .. 2 .. 9 ]} {[ 10 .. 1 ]} {[ 5 .. -1 .. 1 ]} {Array.toList [| 0 .. 3 |]}"
  let n = 4
  println $"{[ n .. n * 2 ]} {List.sum [ 1 .. 100 ]} {Array.length [| 1 .. 1000 |]} {[ for i in [ 1 .. 3 ] -> i * i ]}"
  println $"{sum (1, 2)} {describe ("tea", 2, "cups")} {apply sum} {List.map sum [ (1, 1); (2, 2) ]}"
  0
