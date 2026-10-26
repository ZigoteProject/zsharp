/// A microcontroller's interrupt lines, by number, through its interrupt controller (the NVIC). A
/// line's handler is a function marked `[<Interrupt 38>]` or `[<Interrupt "USART2">]` (the
/// board's names, runtime/boards/<board>.irq).
module Irq

// the NVIC's set-enable, clear-enable and set-pending registers: a bit a line, 32 a word
let private bitAt (base: usize) (n: int) =
  Mmio.write32 (base + usize (4 * (n / 32))) (u32 1 <<< u32 (n % 32))

/// Enables line `n`: its handler runs when the device raises it.
let enable (n: int) =
  let iser: usize = 0xE000E100
  bitAt iser n

/// Disables line `n`.
let disable (n: int) =
  let icer: usize = 0xE000E180
  bitAt icer n

/// Sets line `n` pending, as its device would: its handler runs once the line is enabled. A test
/// needs no device.
let pend (n: int) =
  let ispr: usize = 0xE000E200
  bitAt ispr n
