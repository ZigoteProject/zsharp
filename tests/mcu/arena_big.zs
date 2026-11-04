// a big array freed, then an arena: the arena's block may be cut from the array's freed block,
// which goes back to the heap when the arena is done, so a second big array fits the Cortex-M0+'s
// 8 KB heap again (and the blocks arenas released are the heap's before it runs out)
let make (n: int) (x: int) : array<int> = Array.create n x

let main () =
  let first = ref [ make 1250 1 ]
  let a = Array.length (List.head first.Value)
  first.Value <- []
  let inArena = Arena.with (fun () -> List.length [ a; 2; 3 ])
  let second = make 1250 2
  let more = Arena.with (fun () -> List.length [ 4; 5 ])
  println $"{a} {inArena} {Array.length second} {more}"
  0
