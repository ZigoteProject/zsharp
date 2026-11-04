// Inverse Captcha (2017, day 1): the sum of the digits that match the next digit around the
// circle; then the digit halfway around
let input = "91212129"

let digits = List.map (fun c -> int c - int '0') (String.chars input)

let matching (offset: int) =
  let n = List.length digits
  let arr = Array.ofList digits
  List.sum (List.init n (fun i -> if arr.[i] = arr.[(i + offset) % n] then arr.[i] else 0))

let main () =
  println $"part 1: {matching 1}"
  println $"part 2: {matching (List.length digits / 2)}"
  0
