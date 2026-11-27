#!/usr/bin/env bash
# zs test --stress under ThreadSanitizer (0009, D4): the pool, tasks on other threads' loops and
# Alt's choices on them race on nothing, run over and over on every core, each run its own
# process checked; and a race planted in unsafe code (two threads write a byte) fails its test,
# so a race in Z#'s code would show (its functions have sanitize_thread, as the runtime's do).
set -u
zs="$(pwd)/${1:-bin/zs}"; t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cat > "$t/planted.zs" <<'ZS'
open Testing

// a byte's address as a number, which crosses threads where its pointer can't
let address (p: ptr<u8>) : int = unsafe (Ptr.diff p (Ptr.null ()))

// writes the byte, then holds its result back 20 ms, so the write that follows on the loop's
// thread isn't ordered after this one either
let write (at: int) =
  unsafe (Ptr.write (Ptr.add (Ptr.null ()) at) (u8 1))
  let until = Runtime.ticks () + u64 20000000
  while Runtime.ticks () < until do
    ()

[<Tests>]
let tests =
  testList "planted" [
    test "a byte two threads write" (fun () ->
      let p: ptr<u8> = unsafe (Ptr.alloc 1)
      let at = address p
      Task.run (Task.scope (fun s ->
          task {
            let other = Task.start s (Task.blocking (fun () -> write at))
            unsafe (Ptr.write p (u8 2))
            do! Task.wait other
          }))
      unsafe (Ptr.free p))
  ]
ZS
cat > "$t/threads.zs" <<'ZS'
open Testing

let rec fib (n: int) : int = if n < 2 then n else fib (n - 1) + fib (n - 2)

// x after ms milliseconds
let later (ms: int) (x: int) : Task<int> =
  task {
    do! Task.sleep ms
    return x
  }

// a choice on this thread's loop: a Ch's give against a timer that loses, then a Mailbox
let choice (k: int) : Task<int> =
  Task.scope (fun s ->
    task {
      let c = Ch.make ()
      let m = Mailbox.make ()
      Task.start s (Alt.sync (Ch.give c k)) |> ignore
      let! x = Alt.sync (Alt.choose [ Ch.take c; Alt.map (fun () -> -1) (Alt.after 1000) ])
      Mailbox.post m x
      return! Alt.sync (Mailbox.take m)
    })

[<Tests>]
let tests =
  testList "threads" [
    test "both, for, reduce and Array.Parallel" (fun () ->
      let (a, b) = Parallel.both (fun () -> fib 18) (fun () -> fib 19)
      let hits = Atomic.make 0
      Parallel.for 0 1000 (fun i -> if i % 3 = 0 then Atomic.add hits 1 |> ignore)
      let total = Parallel.reduce 0 1001 0 (fun i -> i) (fun x y -> x + y)
      let words = Array.Parallel.init 50 (fun i -> $"w{i}")
      assert (a + b = 6765 && Atomic.get hits = 334 && total = 500500 && words.[49] = "w49"))
    test "a Mutex and a Channel between jobs" (fun () ->
      let log = Mutex.make []
      Parallel.for 0 100 (fun i -> Mutex.update log (fun xs -> i :: xs) |> ignore)
      let ch = Channel.make 256
      let sender () =
        for i in 1 .. 200 do
          Channel.send ch i
        Channel.close ch
        200
      let receiver () =
        let mutable sum = 0
        let mutable going = true
        while going do
          match Channel.receive ch with
          | Some x -> sum <- sum + x
          | None -> going <- false
        sum
      let (sent, got) = Parallel.both sender receiver
      assert (List.length (Mutex.get log) = 100 && sent = 200 && got = 20100))
    test "tasks on other threads, and a blocking call" (fun () ->
      task {
        let! xs = Task.all (List.init 8 (fun i -> Task.spawn (fun () -> later 1 (fib (10 + i)))))
        let! c = Task.blocking (fun () -> fib 15)
        assert (List.sum xs = 4092 && c = 610)
      })
    test "a spawned task cancelled on its thread" (fun () ->
      task {
        let! r = Task.race (Task.spawn (fun () -> later 60000 1)) (later 5 0)
        assert (r = 0)
      })
    test "choices on several threads' loops" (fun () ->
      task {
        let! xs = Task.all (List.init 4 (fun k -> Task.spawn (fun () -> choice k)))
        assert (xs = [ 0; 1; 2; 3 ])
      })
  ]
ZS
cd "$t"
export ZS_LEAKCHECK=1
# the runs' counts and the cores vary; a report's lines are indented under its FAIL
quiet() { sed -E -e 's/^stress: [0-9]+ runs of ([0-9]+) tests on [0-9]+ cores for ([0-9]+) s, ([0-9]+) failed$/stress: runs of \1 tests for \2 s, \3 failed/' \
  -e 's/^stress: runs of 1 tests for 2 s, [1-9][0-9]* failed$/stress: runs of 1 tests for 2 s, some failed/' | grep -v -E '^       |^[0-9]+ passed, [0-9]+ failed$'; }
echo "planted:"
"$zs" test planted.zs --stress 2s --sanitize=thread 2>&1 | quiet
echo "the pool, tasks and Alt:"
"$zs" test threads.zs --stress 10s --sanitize=thread 2>&1 | quiet
