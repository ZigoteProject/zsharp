// A range loop whose end is its type's last value (or first, counting down) stops there: whether
// another step would pass the end is tested before the step, so the variable never wraps past the
// type's end to start the range again. Several widths both ways, steps whose next sum would
// overflow, a loop that yields (a generator's), and a loop versioning runs without bounds checks,
// whose variable stays in the range its test proved
let lastBytes (lo: u8) = seq { for c in lo .. u8 255 do yield int c }

let firstInts (hi: int) = seq { for i in hi .. -1 .. -9223372036854775808 do yield i }

let main () =
  let mutable bytes = 0
  for c in u8 250 .. u8 255 do
    bytes <- bytes + int c
  let mutable small = []
  for c in i8 -125 .. -1 .. i8 -128 do
    small <- int c :: small
  let mutable wide = 0
  for _ in i32 2147483645 .. i32 2147483647 do
    wide <- wide + 1
  println $"{bytes} {small} {wide}"
  let mutable top = []
  for i in 9223372036854775805 .. 9223372036854775807 do
    top <- i :: top
  let mutable bottom = []
  for i in -9223372036854775806 .. -1 .. -9223372036854775808 do
    bottom <- i :: bottom
  println $"{top} {bottom}"
  let mutable up = []
  for i in 9223372036854775800 .. 5 .. 9223372036854775807 do
    up <- i :: up
  let mutable down = []
  for i in -9223372036854775800 .. -5 .. -9223372036854775808 do
    down <- i :: down
  let mutable hundreds = []
  for c in u8 0 .. u8 100 .. u8 255 do
    hundreds <- int c :: hundreds
  println $"{up} {down} {hundreds}"
  println $"{Seq.toList (lastBytes (u8 253))} {Seq.toList (firstInts -9223372036854775806)}"
  // bounds from input: u64's last value, and a versioned loop up to int's
  let last: option<u64> = Int.parse "18446744073709551615"
  let mutable count = 0
  match last with
  | Some m ->
    for _ in m - u64 2 .. m do
      count <- count + 1
  | None -> ()
  let hi = Option.defaultValue 0 (String.parseInt "9223372036854775807")
  let mutable ring = Array.create 8 0
  for i in hi - 3 .. hi do
    ring.[i % 8] <- i
  println $"{count} {Array.toList ring}"
  0
