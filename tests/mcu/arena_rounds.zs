// arenas' blocks reused for arenas (track M item 8): rounds of an arena, each keeping an array of
// 80 ints (over 256 bytes) outside it, no longer hand the arena's freed blocks (an eighth of the
// heap each) to the arrays, so fifteen rounds fit even the Cortex-M0+'s 8 KB heap
let main () =
  let mutable kept: list<array<int>> = []
  let mutable total = 0
  for i in 1 .. 15 do
    total <- total + Arena.with (fun () -> List.length [ i; i + 1; i + 2 ])
    kept <- Array.create 80 i :: kept
  println $"{total} {List.length kept}"
  0
