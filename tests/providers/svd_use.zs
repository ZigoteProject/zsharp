// The svd provider by import (0001): a module per peripheral, each register a [<Bits>] record
// whose defaults are its reset value, so a literal names only the fields it sets; the registers'
// access functions are for a chip, and aren't called here
import svd ("../../examples/mcu/stm32f401-part.svd", only = "GPIOA,RCC,USART2")

let main () =
  // PA5 as an output, the rest at reset (MODER's reset is 0xA8000000)
  let moder: Gpioa.Moder = { moder5 = u8 1 }
  println $"{Bits.toU32 moder:x} {moder.moder5} {moder.moder15}"
  let cr1: Usart2.Cr1 = { ue = true; te = true; re = true }
  println $"{Bits.toU32 cr1:x} {cr1.ue} {cr1.ps}"
  let clocks: Rcc.Ahb1enr = { gpioaen = true; gpiocen = true }
  println $"{Bits.toU32 clocks:x}"
  let brr: Usart2.Brr = { div_mantissa = u16 8; div_fraction = u8 11 }
  println $"{Bits.toU32 brr:x}"
  // a write-only register has write, a read-only one read: a read of BSRR wouldn't compile
  let set: Gpioa.Bsrr = { bs5 = true }
  println $"{Bits.toU32 set:x} {sizeof<Gpioa.Bsrr>} {sizeof<Usart2.Dr>}"
  0
