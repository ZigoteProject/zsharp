// SysTick's handler (0012): a program's runs at the runtime's period, after the runtime counts
// the wrap, so Runtime.ticks keeps counting up across wraps
let wraps = Atomic.make 0

[<Interrupt "SysTick">]
let tick () = Atomic.add wraps 1 |> ignore

let main () =
  let mutable last = Runtime.ticks ()
  let mutable upward = true
  while Atomic.get wraps < 2 do
    let now = Runtime.ticks ()
    if now < last then
      upward <- false
    last <- now
  println $"SysTick ran {Atomic.get wraps >= 2}, ticks kept counting up {upward}"
  0
