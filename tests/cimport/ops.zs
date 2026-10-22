// C function pointers called from Z#: a struct of them from a C library (imported as fnptr
// fields), and typed pointers to C memory (ptr<i32>), both inside `unsafe`
[<Link "ops.c">]
import c "ops.h"

let main () =
  let ops = shape_ops ()

  unsafe
    println $"area {ops.area 2.0 3.5}"
    println $"twice {ops.twice 21}"
    ops.hello ()
    println (String.ofCStr (ops.name ()))

  // C memory for five i32s: written by C, read and written through the pointer, then freed
  let n = 5
  let p: ptr<i32> = unsafe Ptr.alloc n

  unsafe
    fill_squares (Ptr.toCPtr p) (i32 n)

    for i in 0 .. n - 1 do
      print $"{Ptr.read (Ptr.add p i)} "

    Ptr.write (Ptr.add p 2) (i32 100)
    println $"sum {sum_ints (Ptr.toCPtr p) (i32 n)}"
    Ptr.free p

  println $"null {Ptr.isNull (Ptr.null () : ptr<i32>)}"
  0
