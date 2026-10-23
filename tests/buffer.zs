// Buffers that grow (0024): push, pop, truncate, clear and blit. A slice shares the storage
// until either grows past it, and every element is dropped once (ZS_LEAKCHECK=1 checks)
let main () =
  let b = Buffer.empty
  for i in 1 .. 10 do
    Buffer.push i b
  println $"{Buffer.length b} {b.[0]} {b.[9]}"
  let s = b.[2..4]
  s.[0] <- 30
  println $"shared: {b.[2]} {Buffer.length s}"
  Buffer.push 99 s // the slice grows: a copy of its own, which b doesn't see
  s.[1] <- 40
  println $"apart: {b.[3]} {s.[1]} {Buffer.length s} {s.[3]}"
  println $"{Buffer.pop b} {Buffer.pop b} {Buffer.length b}"
  Buffer.truncate 3 b
  println $"{Array.toList (Buffer.toArray b)}"
  Buffer.clear b
  println $"{Buffer.length b} {Buffer.pop b}"
  // counted values: popped while a slice holds the storage, then written over by pushes
  let names = Buffer.empty
  for i in 1 .. 100 do
    Buffer.push $"name {i}" names
  let view = names.[0..9]
  for _ in 1 .. 50 do
    Buffer.pop names |> ignore
  println $"{Buffer.length names} {names.[49]} {view.[9]}"
  for i in 1 .. 20 do
    Buffer.push $"again {i}" names
  println $"{Buffer.length names} {names.[50]} {view.[0]}"
  // blit: bytes, overlapping, and counted values
  let bytes = Buffer.create 8 (u8 46)
  Buffer.blit (String.bytes "hello") 0 bytes 2 5
  println (String.ofBytes bytes)
  Buffer.blit bytes 2 bytes 0 5
  println (String.ofBytes bytes)
  let words = Buffer.ofArray [| "a"; "b"; "c"; "d" |]
  Buffer.blit words 0 words 1 3
  println $"{Array.toList (Buffer.toArray words)}"
  0
