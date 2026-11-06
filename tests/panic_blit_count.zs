// Buffer.blit of int's maximum of elements from index 1, where both i + n and j + n wrap: out of
// range, not a copy of that many counted values
let main () =
  let words = Buffer.ofArray [| "a"; "b"; "c"; "d" |]
  println "before"
  Buffer.blit words 1 words 1 9223372036854775807
  println $"{words.[0]}"
  0
