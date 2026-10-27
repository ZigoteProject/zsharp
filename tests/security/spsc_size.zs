// An Spsc whose slots' bytes overflow the word panics; the runtime made them a small block that
// pushes wrote past
let main () =
  let n = Option.defaultValue 536870911 (Int.parse "2305843009213693951")
  println "before"
  let q : Spsc<int> = Spsc.create n
  Spsc.push q 1 |> ignore
  println "pushed"
  0
