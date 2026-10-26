// Cpu's instructions (0012): barriers and an event; a line pended in a critical section, one
// inside another, is handled only once the outer one ends, and one pended with interrupts
// disabled once they're enabled
let seen = Atomic.make 0

[<Interrupt 4>]
let onLine4 () = Atomic.add seen 1 |> ignore

let main () =
  Irq.enable 4
  Cpu.dmb ()
  Cpu.dsb ()
  Cpu.isb ()
  Cpu.nop ()
  Cpu.sev ()
  // the event just signalled: it returns at once
  Cpu.wfe ()
  let inside =
    Cpu.critical (fun () ->
      Irq.pend 4
      Cpu.critical (fun () -> Atomic.get seen))
  println $"in the critical section {inside}, after it {Atomic.get seen}"
  Cpu.disableInterrupts ()
  Irq.pend 4
  let masked = Atomic.get seen
  Cpu.enableInterrupts ()
  println $"disabled {masked}, enabled {Atomic.get seen}"
  0
