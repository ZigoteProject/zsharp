// a placed Buffer of objects (0014 item 12): each slot of its static storage holds one reference
// until exit, whatever the Buffer did since (written, pushed past its room into the heap,
// shortened by removeLast and truncate), and each is dropped then, so the leak check finds none
[<Section ".logs">]
let log = Buffer.create 2 "-"

[<Align 16>]
let rows = Buffer.create 3 "."

let main () =
  let mutable n = 7
  log.[0] <- $"x{n}"
  Buffer.push "z" log
  log.[1] <- $"y{n}"
  rows.[2] <- $"r{n}"
  let last = Buffer.removeLast rows
  rows.[1] <- $"s{n}"
  Buffer.truncate 1 rows
  println $"{Buffer.length log} {log.[0]} {log.[1]} {log.[2]} {last} {Buffer.length rows} {rows.[0]}"
  0
