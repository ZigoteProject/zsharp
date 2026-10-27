// A channel whose slots' bytes overflow the word panics; the runtime made them a small block
// that sends wrote past
let main () =
  let n = Option.defaultValue 536870912 (Int.parse "2305843009213693952")
  println "before"
  let c : Channel<int> = Channel.make n
  Channel.send c 1
  println "sent"
  0
