// F#: classes; Z# has records, unions and members
type Counter() =
  let mutable n = 0
  member this.Next () =
    n <- n + 1
    n

let main () = 0
