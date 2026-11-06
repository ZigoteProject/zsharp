// A Buffer read past its end in a for loop versioning could take: Buffers aren't versioned (the
// loop can shrink one without assigning it), so the read is checked against the length it has
let sum (b: Buffer<int>) (n: int) =
  let mutable s = 0
  for i in 0 .. n - 1 do
    s <- s + b.[i]
  s

let main () =
  let b = Buffer.empty
  for i in 1 .. 4 do
    Buffer.push i b
  println $"{sum b 4}"
  println $"{sum b 64}"
  0
