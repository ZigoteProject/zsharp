// Firmware for an ST Nucleo-F401RE: the green LED (LD2) is off, on or blinking; the blue button
// (B1) cycles the modes, and the ST-Link's serial port (USART2, 115200 8N1) takes commands:
//   on | off | blink <ms> | status
// Three tasks on the runtime's loop, the core asleep between their events: the LED's, waiting for
// its period or a change of mode; the button's, waiting for its interrupt (Irq.wait); the
// shell's, waiting for the bytes USART2's handler hands over (an Spsc and a Signal). println
// goes over RTT, to the probe.
//   zs build      build/nucleo, for the board (zs.toml's target)
//   zs run        flashed through probe-rs, which shows the log
//   zs test       the shell's logic, on this computer
open Shell

/// The LED in its mode: on, off, or toggled each period; a new mode shows at once.
let rec light (mode: ref<Mode>) (changed: Signal) (lit: bool) : Task<unit> =
  task {
    let next =
      match mode.Value with
      | Off -> false
      | On -> true
      | Blink _ -> not lit
    Board.setLed next
    let wait =
      match mode.Value with
      | Blink ms -> Task.race (Task.sleep ms) (Signal.wait changed)
      | _ -> Signal.wait changed
    do! wait
    return! light mode changed next
  }

/// The button: a press (still down 20 ms after its edge, so a bounce isn't one) is the next mode.
let rec button (mode: ref<Mode>) (changed: Signal) : Task<unit> =
  task {
    do! Irq.wait Board.buttonLine
    do! Task.sleep 20
    if Board.buttonDown () then
      mode.Value <- pressed mode.Value
      println $"button: led {describe mode.Value}"
      Signal.set changed
    while Board.buttonDown () do
      do! Task.sleep 20
    Board.clearButton ()
    return! button mode changed
  }

/// The serial port's command line.
let rec shell (mode: ref<Mode>) (changed: Signal) : Task<unit> =
  task {
    Board.putString "\r\n> "
    let! line = Board.readLine ()
    if String.length line > 0 then
      let (next, answer) = run mode.Value (parse line)
      if next <> mode.Value then
        mode.Value <- next
        Signal.set changed
      println $"{line}: {answer}"
      Board.putString $"\r\n{answer}"
    return! shell mode changed
  }

let main () =
  Board.init ()
  println "nucleo: ready; USART2 at 115200 takes on | off | blink <ms> | status"
  let mode = ref Off
  let changed = Signal.create ()
  Task.run (Task.all [ light mode changed false; button mode changed; shell mode changed ])
  |> ignore
  0
