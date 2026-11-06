// A loop over a Buffer of strings that clears it on the way: the next read is checked against
// the length 0 it has then, rather than reading a string clear has dropped
let main () =
  let b = Buffer.ofArray [| "a"; ""; "c"; "d" |]
  println "before"
  for i in 0 .. Buffer.length b - 1 do
    if b.[i] = "" then Buffer.clear b
  println $"{Buffer.length b}"
  0
