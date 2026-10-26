// a handler reaching state the program changes too (0012), built for a Cortex-M4
let count = ref 0

let bump () = count.Value <- count.Value + 1

[<Interrupt "SysTick">]
let tick () = bump ()

let main () = 0
