// C and a contained job (0035): a callback C calls during the call is the job's, and works as
// anywhere; one C may call on any thread, and keep (a callback<share<F>>), can't be passed in a
// job, whose memory it would be in when the job has gone: a panic, the job's own.
[<Link "ccalls.c">]
import c "ccalls.h"

extern call_now : callback<i64 -> unit> -> i64 -> unit
extern call_shared : callback<share<i64 -> unit>> -> i64 -> unit

let main () =
  // outside a job: both, as ever
  let total = Atomic.make 0
  call_shared (fun x -> Atomic.add total (int x) |> ignore) (i64 1)
  println $"outside a job: {Atomic.get total}"
  // in a job: the callback of the call is called there, on what the job made
  let inJob =
    Contained.run (fun () ->
      let seen = ref 0
      call_now (fun x -> seen.Value <- seen.Value + int x) (i64 20)
      call_now (fun x -> seen.Value <- seen.Value + int x) (i64 22)
      seen.Value)
  println $"in a job: {inJob}"
  // in a job: a callback C may keep
  let kept =
    Contained.run (fun () -> call_shared (fun x -> Atomic.add total (int x) |> ignore) (i64 1))
  println $"{Result.isError kept}, and the total is still {Atomic.get total}"
  0
