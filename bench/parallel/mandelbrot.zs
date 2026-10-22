// Mandelbrot in parallel: the points of an n x n grid over [-2, 1] x [-1.5, 1.5] that stay
// bounded for 50 iterations, the rows computed by the thread pool. Phase 7's exit test (with
// nbody): it should run 0.8 x the cores times as fast as on one worker.

// how many points of row y are in the set
let row (n: int) (y: int) : int =
  let ci = 3.0 * float y / float n - 1.5
  let mutable count = 0
  for x in 0 .. n - 1 do
    let cr = 3.0 * float x / float n - 2.0
    let mutable zr = 0.0
    let mutable zi = 0.0
    let mutable i = 0
    while i < 50 && zr * zr + zi * zi <= 4.0 do
      let t = zr * zr - zi * zi + cr
      zi <- 2.0 * zr * zi + ci
      zr <- t
      i <- i + 1
    if i = 50 then count <- count + 1
  count

let main () =
  let n = match Environment.args () with
          | s :: _ -> Option.get (String.parseInt s)
          | _ -> 4000
  let rows = Array.Parallel.init n (fun y -> row n y)
  println $"{Array.sum rows} points of {n * n} in the set"
