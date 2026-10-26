// What the firmware does, apart from the hardware: the LED's modes, what the button and the
// serial commands do to them, and the replies. Pure functions over values, so `zs test` runs
// them on a computer.

/// The LED: off, on, or blinking with a period.
type Mode =
  | Off
  | On
  | Blink of periodMs: int

/// A line typed at the serial port.
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

/// A line, without its end: on | off | blink <ms> (1 to 60000) | status.
let parse (line: string) : Command =
  match String.trim line with
  | "on" -> TurnOn
  | "off" -> TurnOff
  | "status" -> Status
  | l when String.startsWith "blink " l ->
    match Int.parse (String.sub l 6 (String.length l - 6)) with
    | Some ms when ms >= 1 && ms <= 60000 -> BlinkEvery ms
    | _ -> Unknown
  | _ -> Unknown

/// A command's new mode and the reply to it.
let run (mode: Mode) (cmd: Command) : Mode * string =
  match cmd with
  | TurnOn -> (On, "led on")
  | TurnOff -> (Off, "led off")
  | BlinkEvery ms -> (Blink ms, $"led {describe (Blink ms)}")
  | Status -> (mode, $"led {describe mode}")
  | Unknown -> (mode, "commands: on | off | blink <ms> | status")
