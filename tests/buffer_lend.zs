// a Buffer written or read through a pattern variable, while the same expression hands the value
// it was matched from to a function that frees it: the Buffer isn't lent then (it would be gone
// before the write), so the write lands in it, nothing else's memory, and the leak check is clean
let rec count (o: option<Buffer<string>>) (k: int) : int =
  if k = 0 then List.length [ o ] else count o (k - 1)

let fresh (n: int) (keep: ref<list<Buffer<string>>>) : string =
  let y = Buffer.create 2 $"q{n}"
  keep.Value <- [ y ]
  $"n{n}"

let main () =
  let keep = ref []
  let x = Some(Buffer.create 2 $"a{List.length (Environment.args ())}")
  match x with
  | Some b -> b.[0] <- fresh (count x 2) keep
  | None -> ()
  match keep.Value with
  | [ y ] -> println $"y holds {y.[0]} {y.[1]}"
  | _ -> ()
  let z = Some(Buffer.create 2 "r")
  match z with
  | Some b -> println b.[count z 1 - 1]
  | None -> ()
  0
