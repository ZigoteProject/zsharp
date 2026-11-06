// The runtime's hooks under Native are the library's: nothing checks what one is given (a job's
// handle, a loop's token), so a program uses one only inside `unsafe`, a field's default too.
type Probe = { probeId: int; onWindows: bool = Native.isWindows () }

let twice () =
  let job = Native.parFork (fun () -> 42)
  let a: int = unsafe (Native.parJoin job)
  a

let forged () = Native.loopFulfill 1

let probed () = { probeId = 1 }

let main () = println $"{twice ()}"
