// Firmware for an ST Nucleo-F401RE (STM32F401RE, a Cortex-M4F at 16 MHz after reset). The green
// LED (LD2, PA5) is off, on or blinking. The blue button (B1, PC13) cycles through the modes, and
// USART2 takes commands; the board's ST-Link turns it into a USB serial port (115200 8N1):
//   on | off | blink <ms> | status
//
// The logic (parsing, the modes, debouncing, blinking) is pure functions over values. Only the
// hardware section touches registers, and the main loop allocates nothing until a command is
// answered.
//   zs build examples/mcu/nucleo-f401.zs --target cortex-m4 -Os -o nucleo.elf
// Not flashable yet: cortex-m4 links for QEMU's mps2-an386 memory map until the STM32F4 board
// lands (ROADMAP, track M).

// ---- the logic: no registers here

type Mode =
  | Off
  | On
  | Blink of periodMs: int

type Command =
  | TurnOn
  | TurnOff
  | BlinkEvery of ms: int
  | Status
  | Unknown

/// The button cycles the modes: off, on, blinking twice a second, off.
let pressed (mode: Mode) =
  match mode with
  | Off -> On
  | On -> Blink 500
  | Blink _ -> Off

let describe (mode: Mode) =
  match mode with
  | Off -> "off"
  | On -> "on"
  | Blink ms -> $"blinking every {ms} ms"

/// Whether line.[start ..] (len bytes are filled) begins with `word`.
let hasAt (line: array<u8>) (len: int) (start: int) (word: string) =
  let n = String.length word
  let rec go i = i = n || (line.[start + i] = String.byte word i && go (i + 1))
  start + n <= len && go 0

let isDigit (b: u8) = b >= u8 48 && b <= u8 57

/// The decimal number that fills line.[start .. len - 1], if it's from 1 to 60000.
let numberAt (line: array<u8>) (len: int) (start: int) : option<int> =
  let rec go i acc =
    if i = len then (if acc >= 1 && acc <= 60000 then Some acc else None)
    else if not (isDigit line.[i]) || acc > 6000 then None // acc > 6000: too big, stop before overflow
    else go (i + 1) (acc * 10 + int (line.[i] - u8 48))
  if start < len then go start 0 else None

/// A typed line: the bytes of the line buffer, without allocating.
let parse (line: array<u8>) (len: int) =
  let is word = len = String.length word && hasAt line len 0 word
  if is "on" then TurnOn
  else if is "off" then TurnOff
  else if is "status" then Status
  else if hasAt line len 0 "blink " then
    match numberAt line len 6 with
    | Some ms -> BlinkEvery ms
    | None -> Unknown
  else Unknown

/// A command's new mode and the reply to it.
let run (mode: Mode) (cmd: Command) =
  match cmd with
  | TurnOn -> (On, "led on")
  | TurnOff -> (Off, "led off")
  | BlinkEvery ms -> (Blink ms, $"led {describe (Blink ms)}")
  | Status -> (mode, $"led {describe mode}")
  | Unknown -> (mode, "commands: on | off | blink <ms> | status")

/// The button after debouncing: `down` changes once the raw level has held for holdTicks.
type Button = { down: bool; raw: bool; since: u64 }

/// The new state, and whether this sample completes a press.
let sample (b: Button) (raw: bool) (now: u64) (holdTicks: u64) =
  if raw <> b.raw then ({ b with raw = raw; since = now }, false)
  else if raw <> b.down && now - b.since >= holdTicks then ({ b with down = raw }, raw)
  else (b, false)

/// The LED's level, and when it last toggled: ticks are compared as u64, which never wraps.
let led (mode: Mode) (lit: bool) (lastToggle: u64) (now: u64) (ticksPerMs: u64) =
  match mode with
  | Off -> (false, lastToggle)
  | On -> (true, lastToggle)
  | Blink ms when now - lastToggle >= u64 ms * ticksPerMs -> (not lit, now)
  | Blink _ -> (lit, lastToggle)

// ---- the hardware: STM32F401 registers (reference manual RM0368)

let ticksPerMs = u64 16000 // the HSI clock after reset; SysTick counts core cycles

let rccAhb1enr = usize 0x40023830
let rccApb1enr = usize 0x40023840

let gpioaModer = usize 0x40020000
let gpioaAfrl = usize 0x40020020
let gpioaBsrr = usize 0x40020018
let gpiocIdr = usize 0x40020810

let usartSr = usize 0x40004400
let usartDr = usize 0x40004404
let usartBrr = usize 0x40004408
let usartCr1 = usize 0x4000440C

let bit (n: int) = u32 1 <<< u32 n

/// Clears `mask` in a register, then sets `bits`.
let modify (reg: usize) (mask: u32) (bits: u32) =
  Mmio.write32 reg ((Mmio.read32 reg &&& ~~~ mask) ||| bits)

let init () =
  modify rccAhb1enr (u32 0) (bit 0 ||| bit 2) // clocks for GPIOA and GPIOC
  modify rccApb1enr (u32 0) (bit 17) // and USART2
  let _ = Mmio.read32 rccApb1enr // a peripheral needs two cycles after its clock starts
  modify gpioaModer (u32 0xCF0) (u32 0x4A0) // PA5 output; PA2, PA3 alternate function
  modify gpioaAfrl (u32 0xFF00) (u32 0x7700) // AF7: USART2 TX and RX
  Mmio.write32 usartBrr (u32 0x8B) // 16 MHz / (16 × 8.6875) = 115200 baud
  Mmio.write32 usartCr1 (bit 13 ||| bit 3 ||| bit 2) // enable the USART, its transmitter and receiver

let setLed (lit: bool) = Mmio.write32 gpioaBsrr (if lit then bit 5 else bit 21)

/// B1 pulls PC13 low while it's pressed.
let buttonDown () = Mmio.read32 gpiocIdr &&& bit 13 = u32 0

let putByte (b: u8) =
  while Mmio.read32 usartSr &&& bit 7 = u32 0 do // TXE: the transmit register is empty
    ()
  Mmio.write32 usartDr (u32 b)

let putString (s: string) =
  for i in 0 .. String.length s - 1 do
    putByte (String.byte s i)

/// A received byte, if one is waiting (RXNE).
let tryGetByte () : option<u8> =
  if Mmio.read32 usartSr &&& bit 5 <> u32 0 then Some (u8 (Mmio.read32 usartDr &&& u32 0xFF)) else None

// ---- the main loop: poll the button and the serial port, then drive the LED

let main () =
  init ()
  putString "\r\nready\r\n> "
  let mutable line = Array.create 32 (u8 0)
  let mutable len = 0
  let mutable mode = Off
  let mutable button = { down = false; raw = false; since = u64 0 }
  let mutable lit = false
  let mutable lastToggle = u64 0
  while true do
    let now = Runtime.ticks ()
    let (b, press) = sample button (buttonDown ()) now (u64 20 * ticksPerMs)
    button <- b
    if press then
      mode <- pressed mode
    match tryGetByte () with
    | Some c when c = u8 13 -> // Enter
      if len > 0 then
        let (m, answer) = run mode (parse line len)
        mode <- m
        putString $"\r\n{answer}"
        len <- 0
      putString "\r\n> "
    | Some c when len < Array.length line ->
      line.[len] <- c
      len <- len + 1
      putByte c // echo
    | _ -> ()
    let (l, t) = led mode lit lastToggle now ticksPerMs
    lit <- l
    lastToggle <- t
    setLed lit
  0
