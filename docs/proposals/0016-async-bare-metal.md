# Proposal 0016: async on bare metal

| | |
|---|---|
| **Status** | Approved in principle (decision 71); before 0.1 if the flagship is a microcontroller, after it otherwise |
| **Decided at** | the third design review ([ROADMAP](../../ROADMAP.md#third-design-review-)). Phase 12's note applies: picking microcontrollers as 0.1's niche moves this item into the "before 0.1" list ([ROADMAP](../../ROADMAP.md#phase-12-release-01)) |
| **Builds** | track M, "Later" ([ROADMAP](../../ROADMAP.md#microcontrollers-m)), after [0012](0012-interrupts-noalloc-intrinsics.md)'s handlers and `Spsc` |
| **Rests on** | decisions 21 (one cold `Task`, a state machine), 42 (`[<NoAlloc>]`), 48 (a loop per thread; tasks don't move) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §6](../../DESIGN.md#6-concurrency-task) and [§10](../../DESIGN.md#10-targets) |
| **Related** | [0012 interrupts, NoAlloc and intrinsics](0012-interrupts-noalloc-intrinsics.md) (handlers wake tasks; `Spsc`; `Cpu.wfi`), [0002 effect handlers](0002-effect-handlers.md) (`Task` over an `Async` effect), [0014 placement](0014-placement.md) (the heap's size), [0008 threads](0008-threads.md) (none on bare metal), [0001 type providers](0001-type-providers.md) (the SVD provider names interrupt lines), [0024 library API](0024-library-api.md) (`Task` in Core) |

- [x] Approved in principle
- [ ] Discussion
- [ ] Implementation

## Summary

The same `Task<'a>`, the same `task { }` and the same functions on a Cortex-M as on Linux. The
embedded runtime gets an event loop: a ready queue, a timer heap driven by SysTick, and
waiters for interrupt lines, sleeping with `wfi` when there is nothing to run. An interrupt
wakes a task by pushing a token to a queue the loop drains; no Z# code runs in interrupt
context. `Irq.wait n` is a `Task<unit>` that completes when line `n` fires once, so a driver is
a task, and `Task.sleep`, `both`, `race`, `timeout`, `scope` and cancellation work as on the
host. `Task` moves from Std to Core so that a package's `Task` is one type on every target;
`Task.spawn` and `Task.blocking` are compile errors on a chip, which has no threads.

```fsharp
let blink (ms: int) =
  task {
    while true do
      Led.toggle ()
      do! Task.sleep ms
  }

let commands () =
  task {
    let line = Buffer.create 64 (u8 0)
    while true do
      let! n = Task.timeout 5000 (Uart.readLine line)      // None after 5 s of silence
      match n with
      | Some n -> Uart.writeLine (answer (Buffer.toArray line) n)
      | None -> Uart.writeLine "still here"
  }

let main () =
  Uart.init ()
  Task.run (Task.both (blink 500) (commands ())) |> ignore   // neither ends: firmware runs until reset
  0
```

## Motivation

- **Firmware is waiting.** For a byte, a timer, a button, a DMA transfer. `examples/mcu/uart.zs`
  spins on the transmit-full bit (`putByte`, lines 17–20), and `examples/mcu/nucleo-f401.zs`'s
  main loop polls the button, USART2 and the blink deadline, with the line buffer and the
  debouncing as explicit state. That's the state machine a `task { }` compiles to (phase 9),
  written by hand. With tasks, the blinker is a loop with `Task.sleep`, the command reader is
  a loop with `let!`, and "answer within five seconds or say so" is `Task.timeout`.
- **The frame is the task's memory, not a stack.** An RTOS gives each task a stack of
  hundreds of bytes to kilobytes; a `task { }` allocates one frame, the size of what lives
  across its waits, when it starts (DESIGN §6). So a few long-lived tasks fit the 8 KB heap of
  the Cortex-M0+ build (`Driver.mcus`, src/Driver.fs:369–384 in the main checkout).
- **The same code on the host and the chip.** A protocol parser written over `Uart.read` runs
  under `zs test` with a fake UART on Linux, and under QEMU with `zs test --target cortex-m4`
  ([0009](0009-tests-as-values.md)), because `Task` is one type.
- **Power.** A polling loop burns the core; a loop with nothing to run executes `wfi` and the
  core sleeps until the next interrupt.
- **What the alternative looks like:** polling loops and hand-written state machines (what
  exists), or an RTOS, which brings stacks, preemption and a scheduler that knows nothing of
  Perceus's non-atomic counts (decision 22).

## Detailed design

### One `Task`, in Core

- **The move.** `lib/std/Threading/Task.zs` becomes `lib/core/Threading/Task.zs`: `Task<'a>`,
  `Cancel`, `Scope`, `Promise` and module `Task` as they are (the record `{ ready; work }`,
  Task.zs:19–23 in the main checkout; `resume` through `Native.loopEnter`, 80–85; `Task.run`
  over `Native.loopStep`, 125–133). The namespace stays `Threading` (DESIGN §9), so `open
  Threading` and `Threading.Task.sleep` mean what they did. The placement ledger in
  [0024](0024-library-api.md) lists `Task` as Core's, owned here.
- **Why one type:** a package that gives a `Task<Reading>` must type-check against the same
  `Task` whether the program is built for Linux or for a chip. Two types, or a type per
  runtime, would split the ecosystem at its first async package.
- **The loop's primitives stay under `Native`, per target.** `Native.loopPost`, `loopStep`,
  `loopClose`, `loopEnter`, `loopLeave`, `loopTimer` and `loopUntimer` (Typer.fs:321–329 in
  the main checkout) are implemented by both runtimes under the same C names (`zs_loop_post`,
  rt.c:1081; `zs_loop_step`, rt.c:1476). `Native.loopWait`, `loopUnwait`, `loopBlocking`,
  `loopSpawn`, `loopExpect` and `loopFulfill` need descriptors or threads and are **hosted
  only:** `rt-embedded.c` doesn't define them, and a program that reaches one is a compile
  error naming the target (*What isn't there*, below), not a link error naming a C symbol.
- **New in Core:** `Irq` (`lib/core/Irq.zs`, next to `Mmio`) and `Signal`
  (`lib/core/Threading/Signal.zs`), below. Both are bare-metal only, the mirror image of
  `Task.spawn`.

### The loop in `rt-embedded.c`

The host's loop (rt.c, the section at line 991 in the main checkout) is callbacks waiting
for descriptors, a timer heap, a ready queue, and an inbox pipe for other threads. The chip
has no descriptors and no threads; it has interrupts. Its loop, in C in `rt-embedded.c`:

| Part | On the host (rt.c) | On the chip (rt-embedded.c) |
|---|---|---|
| ready queue | a ring grown by `malloc`, doubling from 64 (rt.c:1081–1093) | the same ring from `zs_alloc`, doubling from 16; a task is queued at most once per wake, so it grows to the first power of two above the number of tasks and stays |
| timers | a heap of `zs_timer`, one `malloc` each, deadlines from `clock_gettime` (rt.c:1193–1208) | the same heap from `zs_alloc`, deadlines in SysTick cycles (*Time*, below) |
| waits | `epoll` on descriptors | a table of `ZS_IRQ_COUNT` waiters, one per interrupt line (*Interrupts*, below) |
| wakes from outside | the inbox pipe | the wake queue: an `Spsc` of tokens ([0012](0012-interrupts-noalloc-intrinsics.md)) that handlers push and the loop drains |
| idle | `epoll_wait` with the next timer as its timeout | SysTick set to the next deadline, then `wfi` |
| nesting depth | 64 continuations, then through the queue (rt.c:1105) | the same |

- **A step** (`zs_loop_step`, the chip's version of rt.c:1476–1523): run the callbacks in the
  ready queue; post the timers that are due; drain the wake queue, posting each token's waiter;
  if the queue has entries, return `true`. If no timer, no line waiter and no `Signal` waiter
  is left, return `false`, and `Task.run` ends (or panics as today when its result isn't
  there, Task.zs:133). Otherwise idle: with interrupts masked, test the wake queue once more,
  and `wfi` if it's empty; unmask. A Cortex-M wakes from `wfi` on a pending interrupt even
  with PRIMASK set, and the handler runs on unmasking, so a token pushed between the test and
  the `wfi` is never slept through.
- **No Z# code in interrupt context.** A handler's work is two things: disable its line and
  push a token. The loop calls the continuation, on the main stack, in loop context, where
  the allocator, the counts and the task's frame are consistent. This is the rule DESIGN §10
  gives for `[<NoAlloc>]` handlers, applied to the loop.
- **One producer:** `Spsc` has one producer and one consumer. The handlers are collectively
  the producer: each push runs with interrupts masked for its few instructions (0012's
  `Cpu.critical`, in C), so a handler that preempts another can't interleave with its push.
  The loop is the consumer. The queue holds one token per line and per `Signal`, since a line
  is disabled when it pushes and a `Signal` pushes only when it wasn't pending, so a push never
  finds it full.
- **Nothing linked without tasks.** Builds link with `--gc-sections` (src/Driver.fs:1824 in
  the main checkout), so a program that never calls `Task.run` carries none of this; the one
  change every program sees is the SysTick handler's addition (*Time*).

### Time: `Task.sleep` on SysTick

- **SysTick stays the runtime's** (the agreement with [0012](0012-interrupts-noalloc-intrinsics.md)).
  Today `Reset_Handler` sets it to reload at `0xFFFFFF` and count processor cycles
  (rt-embedded.c:366–369), the handler counts wraps, and `zs_ticks` is wraps times 2²⁴ plus
  the elapsed part of the period (381–393). After: the handler adds the length of the period
  that just ended to a 64-bit count, then calls the user hook a `[<Interrupt "SysTick">]`
  compiles to (0012); `Runtime.ticks` is the count plus the elapsed part.
- **The deadline sets the period.** When the loop idles with a timer pending, it adds the
  elapsed part of the current period to the count and sets the reload to the cycles until the
  earliest deadline, at most 2²⁴ − 1 (the register's width), so the interrupt arrives with
  the deadline or at a wrap before it; with no timer pending it leaves the full period, as
  today. `Task.sleep ms` is `Native.loopTimer ms` as on the host (Task.zs:136–142).
- **The clock.** Cycles become milliseconds through the core clock, which the runtime doesn't
  know today. `Driver.mcus` gains a clock per board, passed as `-DZS_CLOCK_HZ` as
  `-DZS_HEAP_SIZE` is (src/Driver.fs:1822 in the main checkout), and `clock = "16MHz"` in
  the per-target table [0014](0014-placement.md) defines (`[target.cortex-m4]`, with `heap`
  and `stack`) overrides it. Firmware that reprograms the PLL calls `Runtime.setClock hz`
  (`u32 -> unit`, new in `Runtime`) so later sleeps stay right. Under QEMU with `-icount`,
  cycles are instructions, so a sleep is deterministic, which `tests/mcu` wants.

```toml
[target.cortex-m4]
heap = "16K"
clock = "84MHz"       # after the PLL setup in main; the board's default is 16 MHz
```

### Interrupts: `Irq.wait` and `Signal`

```fsharp
module Irq =
  /// Waits for interrupt line `n` to fire once. Enables the line; the runtime's handler
  /// disables it again when it fires, so the task runs with the line quiet. Clear the
  /// peripheral's flag before waiting again, or the line fires at once.
  val wait : int -> Task<unit>

type Signal                             // Share by construction: a handler may reach it

module Signal =
  val create : unit -> Signal
  val set : Signal -> unit             // from a handler or anywhere: never waits, never allocates
  val wait : Signal -> Task<unit>      // completes once `set` was called since the last wait
```

- **`Irq.wait n`** writes the line's bit to the NVIC's set-enable register, records the task's
  continuation in the waiter table at `n`, and suspends. The runtime's weak default handler
  for a device line (0012's table of `ZS_IRQ_COUNT` weak entries) disables the line in the
  clear-enable register and pushes `n` to the wake queue. The loop drains the queue and posts
  the waiter; the task goes on with the line disabled, reads or acknowledges the peripheral,
  and waits again, which enables the line again. An interrupt that arrives while the line is
  disabled stays pending in the NVIC and fires at the next wait: no event is lost, only
  coalesced, which is what a level-triggered line means anyway.
- **Lines are numbers.** A board module or the SVD provider ([0001](0001-type-providers.md),
  from the file's `<interrupt>` elements) gives them names as constants (`Stm32f401.Irq.usart2
  = 38`), and a top-level constant inlines to an immediate (DESIGN §10), so the NVIC write is
  one store. `Irq.wait "USART2"` is in *Alternatives*.
- **A user handler owns its line** (the agreement with 0012): `[<Interrupt 38>]` replaces the
  default handler, so nothing pushes for line 38, and `Irq.wait 38` is a compile error naming
  the handler when the argument is a constant, a panic when it isn't (the runtime compares the
  line's vector with the default). The handler hands off through `Spsc` and a `Signal`.
- **`Signal`** is the doorbell for a user handler, after Embassy's `Signal`: `set` marks it
  pending and, when a task waits and it wasn't pending, pushes the signal's token (with
  interrupts masked for the push); `wait` completes at once when it's pending, clearing it,
  else registers the task. A set with no waiter is remembered, so a wake is never lost.
  `set` is `[<NoAlloc>]`-safe and may be called from a handler, which the Share rule allows
  (decision 47): a `Signal` is `Share` by construction, as `Spsc` and `Atomic` are.
- **One waiter at a time** on a line and on a `Signal`; a second is a panic naming the line.
  A driver that serves several tasks puts one task in front of the hardware and a `Promise`
  or a `Channel`-shaped queue behind it.
- **Cancellation** is the host's: `Irq.wait` registers an action that removes the waiter and
  disables the line; `Signal.wait`'s removes the waiter. A task cancelled at the wait is
  destroyed there (DESIGN §6), so `Task.timeout 5000 (Uart.readLine line)` leaves the line
  quiet and the frame freed when the time is up.

### Drivers as tasks

The CMSDK UART of QEMU's mps2-an386 (`examples/mcu/uart.zs`'s board), its receive side, with
the runtime's default handler:

```fsharp
module Uart =
  let private data = usize 0x40004000
  let private state = usize 0x40004004       // bit 1: a byte is waiting
  let private ctrl = usize 0x40004008        // bit 0: send; bit 1: receive; bit 3: receive interrupt
  let private intClear = usize 0x4000400C    // bit 1: the receive interrupt
  let private rxFull = u32 2
  let rxLine = 0                             // UART0 RX in the board's table

  let init () = Mmio.write32 ctrl (u32 0xB)

  /// The next byte received, waiting for the receive interrupt when none is there.
  let rec read () : Task<u8> =
    task {
      if Mmio.read32 state &&& rxFull = u32 0 then
        do! Irq.wait rxLine
        return! read ()
      else
        Mmio.write32 intClear (u32 2)
        return u8 (Mmio.read32 data)
    }

  /// Fills `line` up to a newline or its end, and gives the length.
  let readLine (line: Buffer<u8>) : Task<int> =
    task {
      let mutable n = 0
      let mutable fin = false
      while not fin do
        let! b = read ()
        if b = u8 10 || n = Buffer.length line then fin <- true
        else
          line.[n] <- b
          n <- n + 1
      return n
    }
```

A line at 115200 baud delivers a byte every 87 µs (estimate from the rate), and a task that
computes for longer than that loses bytes on a UART without a FIFO. That driver keeps the
handler, and hands bytes off through a ring:

```fsharp
let rx : Spsc<u8> = Spsc.create 64
let rxReady = Signal.create ()

[<Interrupt 38>]                                   // USART2 on the STM32F401: the line is this handler's
let onUsart2 () =
  Spsc.push rx (u8 (Mmio.read32 usart2Dr)) |> ignore   // a full ring drops the byte; the driver counts
  Signal.set rxReady

let rec read () : Task<u8> =
  task {
    match Spsc.pop rx with
    | Some b -> return b
    | None ->
      do! Signal.wait rxReady
      return! read ()
  }
```

`onUsart2` is `[<NoAlloc>]` implicitly and reaches only `Share` values (0012); `Spsc.push`
and `Signal.set` are what it may call.

### Memory, `[<NoAlloc>]` and `--no-heap`

- **A task's frame is allocated once,** when it starts (phase 9); a wait allocates nothing
  (`tests/task/awaits.zs`: 7 allocations for 10 waits and for 200,000). `Task.sleep` allocates
  its timer and its cancellation action (a closure and a list cell) and frees them when it
  fires; `Irq.wait` and `Signal.wait` allocate their cancellation action only. All of it comes
  from the free lists of the embedded heap (rt-embedded.c:93–139), so `live` is constant from
  the first wait on, and a program with a few long-lived tasks fits the 8 KB heap: a frame is
  the live variables across waits plus the coroutine's own words, 50–200 bytes each (estimate),
  and the loop's ring, timers and waiter table are a few hundred bytes (*Scaling*).
- **Starting a task allocates,** so a `[<NoAlloc>]` function can't call `Task.run`,
  `Task.start`, or anything that starts a task; the allocation analysis (0012) gives the
  verdict "allocates: a task's frame" with the chain. A handler, implicitly `[<NoAlloc>]`,
  touches tasks only through `Signal.set` and `Spsc.push`.
- **`--no-heap` excludes tasks:** the image has no heap, and a program whose `main` reaches
  `Task.run` is an error naming the chain. A program that must not allocate after startup
  starts its tasks first and keeps `[<NoAlloc>]` on what runs after: the waits don't allocate,
  and a `Task.sleep` in such code is the one thing the analysis flags.
- **The exit report** (`#zs heap_peak=… allocations=… live=…`, rt-embedded.c:345–354) is the
  measurement: a soak of three tasks waiting 10,000 times under QEMU must show `live` at its
  value after the first wait, and `heap_peak` under 1 KB (estimate; the exit test fixes the
  number once measured).

### What isn't there: threads and descriptors

- **`Task.spawn`, `Task.blocking` and `Task.waitFor`** stay in `Task` (one module, one type)
  and are errors on a chip, found after monomorphization, where the program's reachable
  functions are known, as `share<F>`'s top-level check (DESIGN §7) and `[<NoAlloc>]` run:
  a function that reaches a hosted-only builtin in a bare-metal build is an error at the
  program's call with the chain and the target's name (*Diagnostics*). `Irq.wait` and
  `Signal` on a hosted target are the same error the other way round.
- **No threads means no marking:** a top-level `Spsc` or `Signal` is reached by a handler,
  not sent to a thread, so nothing is marked shared and counts stay non-atomic (DESIGN §7.1).
  `Share` is the check that the handler reaches nothing else.
- **`Mutex` and `Channel`** stay Std's: they're threads' tools; between tasks on one loop a
  `Promise` is enough, and between a handler and a task `Spsc` and `Signal` are.

### Order of implementation

1. **The move:** `Task` to Core; hosted-only builtins and their error after monomorphization.
   The host suite is unchanged, and `zs build --target cortex-m4` of a program calling
   `Task.spawn` prints the error.
2. **The loop:** ready queue, timers on SysTick, `wfi` idle, the clock per board. `Task.sleep`,
   `both`, `all`, `race`, `timeout`, `scope` and `use` under QEMU: `tests/mcu/task.zs` with
   `.out`, run by the `--target` block of `test.sh`, and the soak above.
3. **`Irq.wait`** on 0012's default handlers and `Spsc`; `examples/mcu/uart.zs` gains the
   receive side as a task, with QEMU's serial as its input.
4. **`Signal`** and the handler-and-ring driver; `Runtime.setClock`.
5. **`zs test --target cortex-m4`** of tests whose bodies are tasks ([0009](0009-tests-as-values.md)).

Each step keeps `bench/mcu` at its ratios ([the report](../reports/microcontrollers.md)): the
loop is linked only into programs that use it.

## Drawbacks

- **Cooperative, one priority.** A task that computes for 10 ms delays every other task by
  10 ms; handlers still run, so a handler-and-ring driver loses nothing, but a task that
  needs to answer in microseconds is a handler, not a task.
- **Latency is a queue hop:** interrupt to task is the handler, the drain, and whatever
  callback is running; tens of microseconds at 16 MHz (estimate).
- **A heap is required.** Tasks allocate frames, so `--no-heap` firmware can't have them.
- **The clock must be right.** A wrong `clock`, or a PLL change without `Runtime.setClock`,
  makes every sleep wrong by the same factor, and nothing detects it.
- **Flash for the loop:** 1–2 KB at `-Os` (estimate; measured in step 2), paid only by
  programs that use tasks.
- **SysTick is taken,** as it is today; a program that wants it reprograms it at its own
  risk, and `Runtime.ticks` and the timers with it.

## Alternatives

- **An RTOS** (FreeRTOS, Zephyr): a stack per task, preemption, priorities. Each stack is
  hundreds of bytes to kilobytes, which the 8 KB chip can't give to several tasks; preemption
  would need atomic counts everywhere, which decision 22 rejects; and the scheduler would own
  what the loop already does. Not chosen.
- **Embassy** (Rust's embedded async executor): tasks are state machines, an executor is woken
  from interrupts through a pending set, timers run on a hardware timer, and the idle loop
  waits for an event. This proposal follows it, with two differences: Embassy's tasks are
  static pools of a fixed count, Z#'s frames come from the free lists, so a task can be
  started from data; and Embassy runs executors at several interrupt priorities, which is in
  *Unresolved questions*. Not an alternative so much as the model.
- **Interrupt-driven state machines by hand** (`nucleo-f401.zs`): what exists, and still
  possible; the task compiles to the same machine with the compiler keeping the state. Not
  chosen as the only way, because the state and the transitions are written by hand.
- **Polling loops** (`uart.zs`'s `putByte`): simple, and right for a one-event program; they
  burn the core and can't wait for two things without the state machine above.
- **Protothreads** (Dunkels's, Contiki's): the same idea in C macros, where locals don't
  survive a wait. The coroutine frame is what makes a wait keep its variables.
- **A separate `Mcu.Task`:** two types that packages can't agree on. The placement ledger puts
  one `Task` in Core.
- **`Irq.wait "USART2"`:** a name needs the board's table at run time, or a second function
  (no overloading, decision 9). Constants from a board module or the SVD provider give the
  same name at the call and inline to the same immediate.
- **A pending bitmask instead of a queue** (Embassy's wake): one atomic OR per line, no
  capacity and no masking. Kept as the fallback in *Unresolved questions*; the agreement with
  0012 is the `Spsc`.
- **`Task` on an `Async` effect** ([0002](0002-effect-handlers.md)): phase 10's measurement
  decides; the loop here serves either, since `await`'s handler would post to the same queue.

## Compatibility

- **Not breaking on the host.** `Task`'s API is unchanged; it moves from Std to Core under the
  same namespace, so `open Threading` and every call compile as before. A program with its
  own `Task` module shadows it as it did.
- **An older compiler** meeting a bare-metal program that uses `Task` prints today's error:
  `'Task' is in Threading, part of Std, which needs an operating system; this target has none`
  (src/Typer.fs:594 in the main checkout). `Irq` and `Signal` are unknown modules to it.
- **Compiled binaries:** none to consider (decision 27).
- **The library:** `Threading.Task` moves; `Irq` and `Threading.Signal` are new in Core.
  `Mutex`, `Channel`, `Parallel` and `Atomic`'s placement are 0012's and 0024's. `bench/mcu`'s
  programs don't use tasks and link none of the loop.
- **Microcontrollers:** both chips; a `--no-heap` program can't use tasks (above). The
  SysTick handler changes for every program: a 64-bit addition where a wrap count was.
- **Hosted targets:** `Irq.wait` and `Signal` are errors there, as `Task.spawn` is on a chip.

## Pragmatics

### Diagnostics

| Situation | Error |
|---|---|
| `Task.spawn` in a bare-metal build | `Task.spawn needs a thread, and cortex-m4 has none: run the task on this loop with let! (main -> serve -> Task.spawn)` |
| `Task.blocking` in a bare-metal build | `Task.blocking needs a helper thread, and cortex-m0plus has none: call the function, or wait for its interrupt with Irq.wait (main -> store -> Task.blocking)` |
| `Task.waitFor` in a bare-metal build | `Task.waitFor needs file descriptors, and cortex-m4 has none (main -> Tcp.read -> Task.waitFor)` |
| `Irq.wait` or `Signal` in a hosted build | `Irq.wait needs an interrupt controller, and linux-x86-64 has none: build with --target cortex-m4 (main -> Uart.read -> Irq.wait)` |
| `Irq.wait` on a line with a user handler, constant argument | `Irq.wait 38: line 38 has a handler of its own (onUsart2, main.zs:14), so the runtime's isn't there to wake a task; set a Signal from onUsart2, or remove the handler` |
| the same, at run time | `panic: Irq.wait 38: the line has a handler of its own (onUsart2)` |
| a `[<NoAlloc>]` function starting a task | `tick may allocate: tick -> Task.run -> a task's frame; a handler wakes a task with Signal.set instead` |
| `--no-heap` with tasks | `--no-heap: main -> Task.run starts a task, whose frame is on the heap` |
| a line beyond the table | `Irq.wait 300: cortex-m4's table has lines 0–239` when constant; `panic: interrupt 300 is beyond the table (240 lines)` when not |
| two waiters on one line | `panic: two tasks wait for interrupt 38 (one Irq.wait per line at a time)` |
| two waiters on one `Signal` | `panic: two tasks wait on one Signal` |
| nothing left to wait for | today's `panic: Task.run: the task waits for something that can't happen any more` (Task.zs:133) |
| `Task.run` inside a task | today's `panic: Task.run inside a task: use let! there instead` (rt.c:1477) |

The target checks run after monomorphization, as `[<NoAlloc>]`'s does, so `zs check` and the
editor, which stop at type checking (facts: `Driver.check`), don't show them; `zs build
--target` does. The messages name the chain, as 0012's do.

### Tooling

- **`zs lsp`:** hover on `Task.sleep` shows `Task.sleep : int -> Task<unit>` with its `///`
  comment, the same on every target, since it's one type from one file; completion after
  `Irq.` and `Signal.` lists `wait`, `create` and `set`; definition opens
  `lib/core/Threading/Task.zs`; a `let!` outside a task and a type error in a task body are
  diagnostics while editing, as today. The server checks for the host (facts §1), so the
  target errors above show at the build until the server takes the target from `zs.toml`
  ([0007](0007-incremental-builds.md) keys a check by `--target` already).
- **The tree-sitter grammar** gains nothing: no new syntax. `[<Interrupt 38>]` is 0012's
  attribute.
- **`zs test --target cortex-m4`** ([0009](0009-tests-as-values.md)): a test whose body is a
  `Task<unit>` runs on the chip's loop under QEMU, with QEMU's serial as the UART.
- **Debugging:** under QEMU's gdb stub, a task's frame is a struct of its live variables
  ([0011](0011-debug-info-profiles-traces.md)); a backtrace from a resumed task shows the
  loop's step as the caller, as on the host.
- **The exit report** is the chip's `ZS_STATS`: `heap_peak`, `allocations` and `live` after a
  soak say whether the tasks leak.

### Performance

- **Programs without tasks:** nothing linked (`--gc-sections`); the SysTick handler's addition.
- **A wake:** the handler's disable and push, 20–40 cycles (estimate); the drain and the post;
  the resume, an indirect call into the coroutine. A timer firing is a heap pop and a post.
- **A wait:** as on the host, no allocation; the cancellation action's allocation and free
  come from the free lists, a few dozen cycles each (estimate).
- **Idle:** `wfi` between events; SysTick keeps running (tickless idle is open).
- **Flash:** 1–2 KB at `-Os` for the loop, timers, `Irq` and `Signal` (estimate; step 2
  measures it and the exit test fixes it).
- **The host:** unchanged code paths; the move of the file changes no IR (the module cache
  keys on text, [0007](0007-incremental-builds.md)).

### Scaling

| Dimension | Typical | Upper bound |
|---|---|---|
| tasks alive | 2–5 | 100: frames of 50–200 bytes each (estimate), a ready ring of 128 entries (512 bytes) |
| timers pending | 1–3 | 100, a heap of pointers, O(log n) per insert and pop |
| interrupt lines | 32 (QEMU's mps2-an386), 85 (the STM32F401's SVD) | 240, the NVIC's maximum: a waiter pointer and a token slot per line, about 1.5 KB of `.bss` on a 32-bit chip (estimate) |
| signals | 1–4 | 64, a token slot each |
| wakes per second | 100–10,000 (a UART at 115200 baud is 11,520 bytes a second) | 100,000 (estimate: a wake is tens of cycles plus a resume, at 16 MHz) |
| a sleep | 1 ms – 1 min | 2⁶³ cycles: the 64-bit count doesn't wrap |

### Culture-aware formatting and parsing

None: `Task.sleep` takes integer milliseconds, lines are numbers, and `clock` is parsed as
`heap` is, invariant (`16MHz`, `84000000`).

## Unresolved questions

1. **Tickless idle:** stopping SysTick when no timer is pending and sleeping deeper. This
   document keeps SysTick running, because `Runtime.ticks` and the timers count on it; the
   alternative is a low-power timer per board as the time base, which Embassy's time drivers
   use, and which needs a driver per chip family.
2. **Priorities:** none here, one cooperative loop. The alternative is Embassy's executors per
   interrupt priority: a second loop run from PendSV at a higher priority, whose tasks
   preempt the main loop's; it needs a loop per priority and the Share rule between them.
3. **Nesting of handler wakes:** pushes under PRIMASK here, which makes the handlers one
   producer. The alternative is a pending bitmask with an atomic OR per line and no queue,
   which also removes the capacity question; chosen if 0012's `Atomic` on the M0+ (interrupts
   masked anyway, no `ldrex`) measures the same.
4. **`Task` on an `Async` effect** ([0002](0002-effect-handlers.md)): phase 10's measurement
   on the host decides; this loop serves both, and this document assumes the coroutine form.
5. **One waiter per line and per `Signal`:** a panic here; the alternative is a list of
   waiters, woken together, which costs a list cell per waiter and decides nothing a `Promise`
   can't.
6. **The `clock` key:** in 0014's `[target.<name>]` table here, with `Runtime.setClock` for
   PLL changes; the alternative is a board module in Z# that sets the clock at startup, which
   the SVD provider could write. A new decision row, numbered by the coordinator, records the
   choice with the rest.

## History

- **2026-10-22:** drafted from track M's "Later" item, DESIGN §6 and §10, `lib/std/Threading/Task.zs`, `rt.c`'s event loop, `rt-embedded.c`, and Embassy's executor.
