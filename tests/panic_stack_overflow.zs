// Recursion that never ends overflows the stack: a panic that says so, where it was a SIGSEGV
// with nothing printed. Each call pushes, so no optimization can make the recursion a loop.
let rec deeper (b: Buffer<int>) (n: int) : int =
  Buffer.push n b
  1 + deeper b (n + 1)

let main () =
  println "before"
  let b = Buffer.empty
  println $"{deeper b 0}"
  0
