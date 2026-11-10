// The event loop: a task that keeps yielding doesn't hold back what the loop waits for (the
// datagram's arrival is seen within a few turns), and a timer for longer than the clock counts in
// nanoseconds is one far off, not one due at once
let bound () =
  match Udp.bind "127.0.0.1" 0 with
  | Ok s -> s
  | Error e -> panic $"bind: {e}"

let main () =
  use a = bound ()
  use b = bound ()
  let got = ref false
  let receiving =
    task {
      let! _ = Udp.receive b (Buffer.create 16 (u8 0))
      got.Value <- true
      return ()
    }
  let yielding =
    task {
      let! _ = Udp.sendText a "127.0.0.1" (Udp.port b) "x"
      let mutable turns = 0
      while not got.Value && turns < 1000000 do
        do! Task.yield ()
        turns <- turns + 1
      return turns
    }
  let (_, turns) = Task.run (Task.both receiving yielding)
  println $"the datagram seen while a task yields: {turns < 1000000}"
  // the largest int (whose milliseconds in nanoseconds wrapped to a time past)
  let far = Int.saturatingMul (Int.saturatingMul 2000000000 2000000000) 4
  println $"a far timeout doesn't end a task at once: {Option.isSome (Task.run (Task.timeout far (Task.sleep 1)))}"
  println $"a far sleep doesn't end at once: {Option.isNone (Task.run (Task.timeout 1 (Task.sleep far)))}"
  0
