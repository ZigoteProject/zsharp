[<NoEquality>]
type Handle = { id: int }

let main () =
  let same = { id = 1 } = { id = 1 }
  0
