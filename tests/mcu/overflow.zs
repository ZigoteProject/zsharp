// A stack overflow on a chip panics, saying so: the stack is at the bottom of RAM (cortex-m.ld),
// so recursion that runs past it writes below RAM, which faults (on a Cortex-M4 the MPU guards
// those 4 KB too, whatever the board maps there), and the fault handler takes a fresh stack to
// say it. With the stack at the top of RAM it ran on over the heap and the program's globals.
// Each level does work after its call, so it stays a recursion
let rec chain (n: int) : int = if n = 0 then 0 else (chain (n - 1) * 31 + n) % 1000003

let main () =
  println "down a million levels"
  println $"{chain 1000000}"
  0
