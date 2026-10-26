/// The processor's instructions firmware needs, with nothing moved across them: `Cpu.nop`, `wfi`
/// (sleep until an interrupt), `wfe` and `sev` (events), `dmb` and `dsb` (memory barriers), `isb`,
/// `enableInterrupts` and `disableInterrupts`, and `Cpu.critical (fun () -> …)`, which runs its
/// body with interrupts masked and gives its value (one inside another is fine). On a computer the
/// barriers are fences and the rest do nothing, but masking interrupts is an error there. Its
/// functions are built into the compiler.
module Cpu
