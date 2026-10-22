// Callbacks C calls on a thread of its own: one declared callback<share<F>> may be (it's given a
// share function: what it captures is Share, and marked shared); any other panics, naming its
// type, since what it captures may be this thread's alone.
[<Link "callbacks.c">]
import c "callbacks.h"

extern on_thread_shared : callback<share<i64 -> unit>> -> i64 -> unit
extern on_thread_checked : callback<i64 -> unit> -> i64 -> unit

let main () =
  let total = Atomic.make 0
  on_thread_shared (fun x -> Atomic.add total (int x) |> ignore) (i64 42)
  println $"a share callback on another thread: {Atomic.get total}"

  let seen = ref 0
  on_thread_checked (fun x -> seen.Value <- int x) (i64 7)
  println "not reached"
  0
