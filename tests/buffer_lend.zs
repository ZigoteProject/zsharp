// a Buffer written or read through a pattern variable, passed to a function that borrows it, or a
// closure applied, while the same expression hands the value it was matched from to a function
// that frees it: none is lent then (it would be gone before it's used), so the write lands in the
// Buffer, nothing else's memory, and the leak check is clean
let rec count (o: option<Buffer<string>>) (k: int) : int =
  if k = 0 then List.length [ o ] else count o (k - 1)

let fresh (n: int) (keep: ref<list<Buffer<string>>>) : string =
  let y = Buffer.create 2 $"q{n}"
  keep.Value <- [ y ]
  $"n{n}"

let rec put (b: Buffer<string>) (s: string) (k: int) = if k = 0 then b.[0] <- s else put b s (k - 1)

let rec countF (o: option<int -> string>) (k: int) : int =
  if k = 0 then List.length [ o ] else countF o (k - 1)

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
  let w = Some(Buffer.create 2 $"w{List.length (Environment.args ())}")
  match w with
  | Some b ->
    put b (fresh (count w 2) keep) 3
    println $"{b.[0]}"
  | None -> ()
  let n = List.length (Environment.args ())
  let f = Some(fun (k: int) -> $"t{n}{k}")
  match f with
  | Some g -> println (g (countF f 2))
  | None -> ()
  0
