// interrupt handlers (0012): a device line the program sets pending runs its handler, which
// counts in an Atomic and pushes to an Spsc the program drains; handling allocates nothing
let presses = Atomic.make 0
let rx: Spsc<int> = Spsc.create 4

[<Interrupt 3>]
let onLine3 () =
  let n = Atomic.add presses 1
  Spsc.push rx (n * 10) |> ignore

let main () =
  Irq.enable 3
  let before = Runtime.allocations ()
  for _ in 1 .. 6 do
    Irq.pend 3
  let after = Runtime.allocations ()
  let mutable got = []
  let mutable going = true
  while going do
    match Spsc.pop rx with
    | Some x -> got <- x :: got
    | None -> going <- false
  println $"handled {Atomic.get presses}, queued {List.rev got} (4 fit), allocations {after - before}"
  0
