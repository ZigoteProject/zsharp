// Cpu.critical's body runs with interrupts masked, and must not touch the heap (0012)
let main () = Cpu.critical (fun () -> List.length (List.map (fun x -> x + 1) [ 1; 2; 3 ]))
