// Shortest paths: Dijkstra's algorithm over a w x w grid whose cells cost 1 to 9 to enter, from
// the top-left corner to every cell, with the library's priority queue. What a router, a game's
// pathfinding or a build scheduler does: a heap, array updates, and indexes computed per step.
let next (seed: int) = (seed * 1103515245 + 12345) % 2147483648

let main () =
  let w =
    match Environment.args () with
    | a :: _ -> Option.defaultValue 1000 (String.parseInt a)
    | [] -> 1000
  let cells = w * w
  let mutable cost = Array.create cells 0
  let mutable seed = 3
  for i in 0 .. cells - 1 do
    seed <- next seed
    cost.[i] <- 1 + seed / 65536 % 9
  let unreached = cells * 10
  let mutable dist = Array.create cells unreached
  dist.[0] <- 0
  let mutable queue = PriorityQueue.enqueue 0 0 PriorityQueue.empty
  let mutable settled = 0
  let mutable going = true
  while going do
    match PriorityQueue.dequeue queue with
    | None -> going <- false
    | Some ((cell, d), rest) ->
      queue <- rest
      if d = dist.[cell] then // else a stale entry: the cell was reached cheaper since
        settled <- settled + 1
        let x = cell % w
        let y = cell / w
        for (nx, ny) in [ (x - 1, y); (x + 1, y); (x, y - 1); (x, y + 1) ] do
          if nx >= 0 && nx < w && ny >= 0 && ny < w then
            let near = ny * w + nx
            let nd = d + cost.[near]
            if nd < dist.[near] then
              dist.[near] <- nd
              queue <- PriorityQueue.enqueue near nd queue
  println $"{settled} cells settled"
  println $"to the far corner: {dist.[cells - 1]}"
  println $"all distances: {Array.sum dist}"
  0
