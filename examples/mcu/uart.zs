// A UART driver in Z#: writes to the CMSDK UART0 of an ARM MPS2 board (QEMU's mps2-an386)
// through its memory-mapped registers.
//   zs build examples/mcu/uart.zs --target cortex-m4 -o uart.elf
//   qemu-system-arm -M mps2-an386 -nographic -semihosting-config enable=on -kernel uart.elf

/// UART0's registers: DATA, STATE (bit 0: transmit buffer full), CTRL (bit 0: transmit enable).
let uart () = 0x40004000
let data () = usize (uart ())
let state () = usize (uart () + 4)
let ctrl () = usize (uart () + 8)

let txFull () = u32 1

let init () = Mmio.write32 (ctrl ()) (u32 1)

let putByte (b: u8) =
  while Mmio.read32 (state ()) &&& txFull () <> u32 0 do
    ()
  Mmio.write32 (data ()) (u32 b)

let putString (s: string) =
  for i in 0 .. String.length s - 1 do
    putByte (String.byte s i)

let main () =
  init ()
  putString "Hello from a Z# UART driver\n"
  for i in 1 .. 3 do
    putString $"blink {i}\n"
  0
