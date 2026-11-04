// Chronal Calibration (2018, day 1): the changes summed; then the first frequency reached twice
// as the changes repeat
let input = "+3, +3, +4, -2, -4"

let changes =
  List.choose (fun s -> Int.parse (String.replace (String.trim s) "+" "")) (String.split "," input)

let firstTwice () =
  let arr = Array.ofList changes
  let rec go (i: int) (f: int) (seen: HashSet<int>) =
    if HashSet.contains f seen then f
    else go ((i + 1) % Array.length arr) (f + arr.[i]) (HashSet.add f seen)
  go 0 0 HashSet.empty

let main () =
  println $"part 1: {List.sum changes}"
  println $"part 2: {firstTwice ()}"
  0
