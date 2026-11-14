// a contained job's memory goes when it ends, a failed one's too: a thousand failed jobs leave
// nothing allocated (ZS_LEAKCHECK), take no more memory from the system than the first did,
// and leave what they shared with their caller counted right
open Threading

type Tree =
  | Leaf
  | Node of Tree * int * Tree

let rec build (d: int) : Tree = if d = 0 then Leaf else Node(build (d - 1), d, build (d - 1))

let rec sum (t: Tree) : int =
  match t with
  | Leaf -> 0
  | Node(l, x, r) -> sum l + x + sum r

// a job that makes garbage of its own, reads what its caller shares, and fails or not
let job (table: Tree) (fails: bool) : result<int, Panic> =
  Contained.run (fun () ->
    let mine = build 8
    let kept = [ mine; mine; table ]
    if fails then panic "failed"
    sum table + List.sumBy sum kept)

let main () =
  let table = build 10
  // the first jobs take their blocks; the rest reuse them
  for _ in 1 .. 10 do
    job table false |> ignore
  let before = Runtime.mallocs ()
  let mutable failed = 0
  for _ in 1 .. 1000 do
    match job table true with
    | Ok _ -> ()
    | Error _ -> failed <- failed + 1
  let mutable total = 0
  for _ in 1 .. 1000 do
    match job table false with
    | Ok n -> total <- total + n
    | Error _ -> ()
  println $"{failed} failed, the rest gave {total}"
  println $"memory taken from the system meanwhile: {Runtime.mallocs () - before}"
  println $"the table is whole: {sum table}"
