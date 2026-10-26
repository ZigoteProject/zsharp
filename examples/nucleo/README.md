# nucleo: firmware for an ST Nucleo-F401RE

The flagship of Z#'s 0.6.2: a real program in the niche Z# is best at, built alongside the
release. The green LED (LD2) is off, on or blinking; the blue button (B1) cycles the modes; and
the board's ST-Link serial port takes commands.

```sh
cd examples/nucleo
zs build          # build/nucleo, for the board: zs.toml says target = "nucleo-f401"
zs run            # flashed through probe-rs (https://probe.rs), which shows the log
zs test           # the shell's logic, on this computer
```

Then, in a terminal on the ST-Link's serial port at 115200 baud (`screen /dev/tty.usbmodem* 115200`
on macOS, `/dev/ttyACM0` on Linux):

```text
> status
led off
> blink 100
led blinking every 100 ms
> reboot
commands: on | off | blink <ms> | status
```

## How it's built

Three tasks on the runtime's event loop, the core asleep (`wfi`) between their events:

| Task | Waits for | With |
|---|---|---|
| `light` | its blink period, or a change of mode | `Task.race (Task.sleep ms) (Signal.wait changed)` |
| `button` | B1's falling edge, then 20 ms to tell a press from a bounce | `Irq.wait Board.buttonLine`, `Task.sleep 20` |
| `shell` | a line typed at USART2 | the bytes USART2's interrupt handler hands over |

- **[src/Shell.zs](src/Shell.zs):** the modes, the commands and the replies, as pure functions
  over values, so `zs test` runs them here ([tests/ShellTests.zs](tests/ShellTests.zs)).
- **[src/Board.zs](src/Board.zs):** the STM32F401's registers: constants inlined where they're
  used, and USART2's control and status registers as `[<Bits>]` records, so
  `{ ue = true; te = true; re = true; rxneie = true }` is one store of a constant. USART2's
  handler (`[<Interrupt "USART2">]`) reads the byte, pushes it to an `Spsc` and sets a `Signal`:
  it allocates nothing and reaches only what a handler may share, both checked when compiling.
- **[src/main.zs](src/main.zs):** the tasks, which share the mode in a `ref`: they run on one loop,
  in turn. `println` goes over RTT, the probe's channel, so the log needs no pins.

52 KB of the board's 512 KB of flash at `-Os`, and 66 KB of its 96 KB of RAM, 64 KB of it the
heap. [examples/mcu/nucleo-f401.zs](../mcu/nucleo-f401.zs) is the same firmware written as one
polling loop, in 5 KB: the tasks' combinators and their cancellation are most of the difference.

## Without the board

`./test.sh` runs it on QEMU's `netduinoplus2`, whose STM32F405 has the F401's memory map and its
USART2: it types the commands above at USART2 and reads the replies, then the log from a dump of
the RAM, found by the RTT block's ID as a probe finds it ([tests/mcu/rtt.mjs](../../tests/mcu/rtt.mjs)).
QEMU has no model of the board's GPIO, so the LED and the button go untested there.
