// The STM32F401's registers this firmware uses (reference manual RM0368): clocks, the LED's and
// the button's pins, USART2 (the ST-Link's serial port, 115200 8N1) and the button's external
// interrupt. The core runs on its HSI clock's 16 MHz after reset, as the runtime counts.

/// A USART's control register 1.
[<Bits 32>]
type Cr1 =
  { sbk: bool = false
    rwu: bool = false
    re: bool = false
    te: bool = false
    idleie: bool = false
    rxneie: bool = false
    tcie: bool = false
    txeie: bool = false
    peie: bool = false
    ps: bool = false
    pce: bool = false
    wake: bool = false
    m: bool = false
    ue: bool = false }

/// A USART's status register.
[<Bits 32>]
type Sr = { pe: bool; fe: bool; nf: bool; ore: bool; idle: bool; rxne: bool; tc: bool; txe: bool }

let private rccAhb1enr = usize 0x40023830
let private rccApb1enr = usize 0x40023840
let private rccApb2enr = usize 0x40023844
let private gpioaModer = usize 0x40020000
let private gpioaAfrl = usize 0x40020020
let private gpioaBsrr = usize 0x40020018
let private gpiocIdr = usize 0x40020810
let private usartSr = usize 0x40004400
let private usartDr = usize 0x40004404
let private usartBrr = usize 0x40004408
let private usartCr1 = usize 0x4000440C
let private syscfgExticr4 = usize 0x40013814
let private extiImr = usize 0x40013C00
let private extiFtsr = usize 0x40013C0C
let private extiPr = usize 0x40013C14

/// The button's interrupt line, which EXTI lines 10 to 15 share (EXTI15_10).
let buttonLine = 40

/// USART2's line.
let usartLine = 38

let private bit (n: int) = u32 1 <<< u32 n

/// Clears `mask` in a register, then sets `bits`.
let private modify (reg: usize) (mask: u32) (bits: u32) =
  Mmio.write32 reg ((Mmio.read32 reg &&& ~~~ mask) ||| bits)

/// The clocks, the pins, USART2 with its receive interrupt, and the button's falling edge.
let init () =
  modify rccAhb1enr (u32 0) (bit 0 ||| bit 2) // GPIOA, GPIOC
  modify rccApb1enr (u32 0) (bit 17) // USART2
  modify rccApb2enr (u32 0) (bit 14) // SYSCFG
  Mmio.read32 rccApb2enr |> ignore // a peripheral needs two cycles after its clock starts
  modify gpioaModer (u32 0xCF0) (u32 0x4A0) // PA5 an output; PA2, PA3 alternate functions
  modify gpioaAfrl (u32 0xFF00) (u32 0x7700) // AF7: USART2's TX and RX
  Mmio.write32 usartBrr (u32 0x8B) // 16 MHz / (16 × 8.6875) = 115200 baud
  Mmio.write32 usartCr1 (Bits.toU32 { ue = true; te = true; re = true; rxneie = true })
  modify syscfgExticr4 (u32 0xF0) (u32 0x20) // EXTI13 from port C: B1 is PC13
  modify extiFtsr (u32 0) (bit 13) // B1 pulls PC13 low while it's pressed
  modify extiImr (u32 0) (bit 13)
  Irq.enable usartLine

let setLed (lit: bool) = Mmio.write32 gpioaBsrr (if lit then bit 5 else bit 21)

let buttonDown () = Mmio.read32 gpiocIdr &&& bit 13 = u32 0

/// The button's edges so far are dealt with: its line fires at the next.
let clearButton () = Mmio.write32 extiPr (bit 13)

let private status () : Sr = Bits.ofU32 (Mmio.read32 usartSr)

let putByte (b: u8) =
  while not (status ()).txe do
    ()
  Mmio.write32 usartDr (u32 b)

let putString (s: string) =
  for i in 0 .. String.length s - 1 do
    putByte (String.byte s i)

/// What USART2 received, from its interrupt handler to the shell's task.
let received: Spsc<u8> = Spsc.create 64

let arrived = Signal.create ()

[<Interrupt "USART2">]
let onUsart2 () =
  let sr = status ()
  // the data register read after the status takes the byte, and clears an overrun
  let b = u8 (Mmio.read32 usartDr &&& u32 0xFF)
  if sr.rxne then
    Spsc.push received b |> ignore // a full ring drops the byte
    Signal.set arrived

/// The next byte typed, waiting for the handler's signal when none is there.
let rec getByte () : Task<u8> =
  task {
    match Spsc.pop received with
    | Some b -> return b
    | None ->
      do! Signal.wait arrived
      return! getByte ()
  }

/// A line typed, echoed as it comes (what's past 64 bytes is dropped).
let readLine () : Task<string> =
  task {
    let line = Buffer.empty
    let mutable fin = false
    while not fin do
      let! b = getByte ()
      if b = u8 13 || b = u8 10 then
        fin <- true
      else if Buffer.length line < 64 then
        Buffer.push b line
        putByte b
    return Utf8.decode (Buffer.toArray line)
  }
