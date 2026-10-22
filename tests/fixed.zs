// Fixed-size arrays: N elements inline, a value indexed like an array
type Frame =
  { id: int
    bytes: fixed<u8, 4> }

let main () =
  let mutable f: fixed<int, 4> = Fixed.init (fun i -> i * i)
  f.[1] <- 10
  f.[2] += 5
  println $"{f} {f.[3]} {Fixed.length f} {Fixed.fold (fun a x -> a + x) 0 f} {Array.toList (Fixed.toArray f)}"
  let g = f // a copy
  f.[0] <- 7
  println $"{g.[0]} {f.[0]} {g = f} {g = Fixed.set f 0 0} {compare g f}"
  let mutable fr = { id = 1; bytes = Fixed.create (u8 0) }
  fr.bytes.[2] <- u8 9
  fr.bytes.[3] += u8 1
  let mutable text = ""
  for b in fr.bytes do
    text <- text + $"{b} "
  println text
  let words: fixed<string, 3> = Fixed.ofArray [| "a"; "b"; "c" |]
  let again: fixed<string, 3> = Fixed.ofArray [| "a"; "b"; "c" |]
  println $"{Fixed.map (fun w -> w + "!") words} {hash words = hash again} {words = again} {fr}"
  0
