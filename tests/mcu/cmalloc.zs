// C's malloc, calloc and realloc over the heap of a chip or WebAssembly (rt-embedded.c), as C,
// Rust or Zig code linked in calls them: a size past the heap's is NULL, as a C library's is,
// where the size's rounding wrapped (SIZE_MAX gave a block of 0 bytes, 0xFFFFFF00 moved the
// heap's top back over live objects); a calloc whose count times size overflows is NULL too; and
// a realloc that can't grow leaves the block as it was (its first bytes aren't a free list's link)
extern malloc : usize -> ptr<u8>
extern calloc : usize -> usize -> ptr<u8>
extern realloc : ptr<u8> -> usize -> ptr<u8>

let main () =
  let block = malloc (usize 64)
  for i in 0 .. 63 do
    unsafe Ptr.write (unsafe Ptr.add block i) (u8 65)
  let wrapsTop: usize = 0xFFFFFF00
  let wrapsRounding: usize = 0xFFFFFFFF
  let a = malloc wrapsTop
  let b = malloc wrapsRounding
  println $"malloc past the heap: {Ptr.isNull a} {Ptr.isNull b}"
  let c = calloc (usize 0x10000) (usize 0x10000)
  let d = calloc (usize 0x1000) (usize 0x1000)
  println $"calloc past the heap: {Ptr.isNull c} {Ptr.isNull d}"
  let e = realloc block wrapsRounding
  let first = unsafe Ptr.read block
  println $"realloc past the heap: {Ptr.isNull e}, the block kept: {first = u8 65}"
  let f = malloc (usize 64)
  println $"malloc after: {not (Ptr.isNull f)}"
  unsafe Ptr.free a
  unsafe Ptr.free b
  unsafe Ptr.free c
  unsafe Ptr.free d
  unsafe Ptr.free e
  unsafe Ptr.free f
  unsafe Ptr.free block
  0
