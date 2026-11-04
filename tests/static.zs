// constants in flash (0014 item 1): a top-level array literal of numbers, bools or strings is a
// static object in the image, not built at startup: reading it allocates nothing, a write copies
// it (a static is never unique), and the strings in it are statics too
let crc = [| u32 0x00000000; u32 0x77073096; u32 0xEE0E612C; u32 0x990951BA |]
let names = [| "zero"; "one"; "two" |]
let flags = [| true; false; true |]
let weights = [| 0.5; 1.25; -2.0 |]
let small = [| i8 -3; i8 7 |]
let primes = [ 2; 3; 5; 7 ]
let commands = [ "off"; "on"; "blink" ]

let main () =
  let mutable sum = u32 0
  for i in 0 .. Array.length crc - 1 do
    sum <- Int.wrappingAdd sum crc.[i]
  println $"{sum:X8} {names.[1]} {flags.[2]} {weights.[1]} {small.[0] + small.[1]}"
  let mutable copy = crc
  copy.[0] <- u32 1
  println $"{crc.[0]} {copy.[0]} {Array.toList names} {Array.length flags}"
  // static lists: cells in the image, the last pointing at the static []; a longer list shares
  // them, and taking the tail is reading
  let more = 1 :: primes
  match commands with
  | first :: rest ->
    println $"{List.sum primes} {List.length more} {first} {rest} {List.tail more = primes}"
  | [] -> ()
  0
