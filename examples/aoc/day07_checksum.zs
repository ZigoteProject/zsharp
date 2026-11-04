// Corruption Checksum (2017, day 2): each row's largest minus smallest, summed; then the one
// division in each row that comes out even
let input = "5 9 2 8\n9 4 7 3\n3 8 6 5"

let rows =
  List.map (fun line -> List.choose Int.parse (String.split " " line)) (String.splitLines input)

let evenDivision (row: list<int>) =
  let pairs = List.collect (fun a -> List.map (fun b -> (a, b)) row) row
  match List.tryFind (fun (a, b) -> a <> b && a % b = 0) pairs with
  | Some(a, b) -> a / b
  | None -> 0

let main () =
  println $"part 1: {List.sumBy (fun row -> List.max row - List.min row) rows}"
  println $"part 2: {List.sumBy evenDivision rows}"
  0
