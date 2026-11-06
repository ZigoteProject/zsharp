// A Signal record that Signal.create didn't make panics where it's used: the runtime indexes its
// 32 waiters by the id (40 was a write past them, and a cancel's drop of what was there), and a
// bit past the Signals made is one the loop never clears, so it would never sleep
let made = Signal.create ()

let main () =
  Signal.set made
  println "a Signal from Signal.create: set"
  let forged: Signal = { id = 40 }
  Signal.set forged
  println "a forged one: set"
  0
