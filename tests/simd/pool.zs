// Only a program that can put a vector in a heap object has its objects 64-byte aligned by the
// system allocator (Compile.wideVectors); a vector in locals only, as Bytes.appendJsonString's
// U8x16 scan, leaves every object to the pool, which calls malloc once per 64 KB chunk.
// tests/simd/pool_wide.zs is the other side.
type Point = { name: string; x: int }

let main () =
  let quoted = Bytes.appendJsonString "say \"hi\"" (Bytes.writerOf Buffer.empty)
  println (String.ofBytes (Bytes.written quoted))
  let before = Runtime.mallocs ()
  let points = List.init 1000 (fun i -> { name = "p"; x = i })
  println $"{List.sumBy (fun p -> p.x) points}, from the pool: {Runtime.mallocs () - before < 10}"
  0
