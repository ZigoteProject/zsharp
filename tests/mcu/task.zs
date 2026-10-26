// Tasks on a microcontroller (0016): the runtime's loop, its timers on SysTick and the core asleep
// (wfi) between them; a task waiting for an interrupt line (Irq.wait), and one woken by a
// handler's Signal. Lines 5 and 6 are free on both boards, and pended by the program itself.
let ready = Signal.create ()

[<Interrupt 6>]
let onSix () = Signal.set ready

let say (ms: int) =
  task {
    do! Task.sleep ms
    println $"slept {ms}"
    return ms
  }

let main () =
  // the deadlines in order, whatever order the tasks started in
  let all = Task.run (Task.all [ say 30; say 10; say 20 ])
  println $"all: {all}"
  // the first to finish wins; the other is cancelled, its timer gone
  println $"race: {Task.run (Task.race (say 40) (say 5))}"
  let slow =
    task {
      do! Task.sleep 1000
      println "too late"
      return 0
    }
  println $"timeout: {Task.run (Task.timeout 15 slow)}"
  // a sleep takes its time in SysTick's cycles: 50 ms is 800,000 at 16 MHz (more at 25)
  let before = Runtime.ticks ()
  Task.run (Task.sleep 50)
  println $"50 ms: {Runtime.ticks () - before >= u64 800000}"
  // a task waits for line 5, which another pends: the runtime's handler wakes it
  let waiter =
    task {
      do! Irq.wait 5
      println "line 5 fired"
    }
  let pender =
    task {
      do! Task.sleep 10
      println "pending line 5"
      Irq.pend 5
    }
  Task.run (Task.both waiter pender) |> ignore
  // line 6's handler is the program's: it sets a Signal, which wakes the task waiting on it
  let rung =
    task {
      do! Signal.wait ready
      println "signal"
    }
  let ringer =
    task {
      do! Task.sleep 10
      Irq.enable 6
      Irq.pend 6
    }
  Task.run (Task.both rung ringer) |> ignore
  // a set with nobody waiting stays set: the next wait goes on at once
  Signal.set ready
  Task.run (Signal.wait ready)
  println "set before the wait"
  // many waits allocate nothing that stays: live is 0 at exit
  let spin (n: int) =
    task {
      for _ in 1 .. n do
        do! Task.sleep 0
      return n
    }
  println $"waits: {Task.run (Task.all [ spin 300; spin 300; spin 300 ])}"
  0
