// A UART driver in Z#: the CMSDK UART0 of an ARM MPS2 board (QEMU's mps2-an386), through its
// memory-mapped registers. Sending spins on the transmit buffer; receiving is a task that waits
// for the receive interrupt (Irq.wait), the core asleep until a byte comes.
//   zs run examples/mcu/uart.zs --target cortex-m4          (type a line; QEMU's serial is stdin)
//   zs build examples/mcu/uart.zs --target cortex-m4 -o uart.elf
//   qemu-system-arm -M mps2-an386 -nographic -semihosting-config enable=on -kernel uart.elf

/// UART0's registers: DATA, STATE (bit 0: transmit buffer full; bit 1: a byte received), CTRL
/// (bit 0: transmit; bit 1: receive; bit 3: interrupt on a byte received) and INTCLEAR.
let uart = usize 0x40004000
let data = uart
let state = uart + usize 4
let ctrl = uart + usize 8
let intClear = uart + usize 12

let txFull = u32 1
let rxFull = u32 2
let rxLine = 0 // UARTRX0, in runtime/boards/mps2-an386.irq

let init () = Mmio.write32 ctrl (u32 0xB)

let putByte (b: u8) =
  while Mmio.read32 state &&& txFull <> u32 0 do
    ()
  Mmio.write32 data (u32 b)

let putString (s: string) =
  for i in 0 .. String.length s - 1 do
    putByte (String.byte s i)

/// The next byte received, waiting for the receive interrupt when none is there.
let rec getByte () : Task<u8> =
  task {
    if Mmio.read32 state &&& rxFull = u32 0 then
      do! Irq.wait rxLine
      return! getByte ()
    else
      Mmio.write32 intClear (u32 2) // the interrupt's done: it doesn't fire again for this byte
      return u8 (Mmio.read32 data)
  }

/// A line typed, echoed as it comes.
let readLine () : Task<string> =
  task {
    let line = Buffer.empty
    let mutable fin = false
    while not fin do
      let! b = getByte ()
      if b = u8 10 || b = u8 13 then
        fin <- true
      else
        Buffer.push b line
        putByte b
    putByte (u8 10)
    return Utf8.decode (Buffer.toArray line)
  }

let main () =
  init ()
  putString "Hello from a Z# UART driver: type a line\n"
  let line = Task.run (readLine ())
  putString $"you typed {String.length line} bytes: {line}\n"
  0
