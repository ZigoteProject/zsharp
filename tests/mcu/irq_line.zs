// Irq.enable, disable and pend panic for a line past the board's table, naming the function: its
// bit would be in another register of the System Control Space (24647's is VTOR's, where the next
// interrupt would take its handler from), and a negative line's in another line's
let main () =
  Irq.enable 3
  Irq.disable 3
  println "line 3 on and off"
  Irq.enable 24647
  println "VTOR written"
  0
