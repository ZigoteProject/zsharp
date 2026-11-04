// Report Repair (2020, day 1): the two entries that sum to 2020, multiplied; then the three
let input = "1721\n979\n366\n299\n675\n1456"

let entries = List.choose Int.parse (String.splitLines input)

let main () =
  let two =
    List.collect (fun a ->
      List.choose (fun b -> if a < b && a + b = 2020 then Some(a * b) else None) entries) entries
  println $"part 1: {List.head two}"
  let three =
    List.collect (fun a ->
      List.collect (fun b ->
        List.choose (fun c -> if a < b && b < c && a + b + c = 2020 then Some(a * b * c) else None) entries) entries) entries
  println $"part 2: {List.head three}"
  0
