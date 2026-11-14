// what crosses a contained job's boundary (0035): a mutex's value in and out, a channel's
// messages, an atomic, and a Mutex, a Channel and an Atomic made in a job that outlive it
open Threading

let main () =
  let m = Mutex.make [ 1; 2; 3 ]
  let counter = Atomic.make 0
  let ch = Channel.make 4
  // a job reads the mutex, updates it, sets it, sends on the channel, adds to the atomic
  let r =
    Contained.run (fun () ->
      let before = Mutex.get m
      let after = Mutex.update m (fun xs -> 0 :: xs)
      Mutex.set m (List.map (fun x -> x + 10) after)
      Channel.send ch (String.join "," (List.map (fun x -> $"{x}") before))
      Channel.send ch "second"
      Atomic.add counter 1 |> ignore
      List.length after)
  println $"{r} {Mutex.get m} {Channel.receive ch} {Channel.receive ch} {Atomic.get counter}"
  // a panic in Mutex.update's function: the mutex is unlocked, its value the one before
  let r2 =
    Contained.run (fun () ->
      List.length (Mutex.update m (fun xs -> if List.length xs = 4 then panic "in update" else xs)))
  println $"{r2} {Mutex.get m}"
  Mutex.set m [ 7 ]
  println $"{Mutex.update m (fun xs -> 8 :: xs)}"
  // a panic after a send and a set: they happened
  let r3 =
    Contained.run (fun () ->
      Channel.send ch "sent before the panic"
      Mutex.set m [ 99 ]
      Atomic.add counter 1 |> ignore
      if Atomic.get counter = 2 then panic "after" else 0)
  println $"{r3} {Mutex.get m} {Channel.receive ch} {Atomic.get counter}"
  // made in a job, and returned from it: they outlive it
  let made =
    Contained.run (fun () ->
      let a = Atomic.make 5
      let inner = Mutex.make "inside"
      let c = Channel.make 2
      Channel.send c [ "a"; "b" ]
      Mutex.set inner (Mutex.get inner + "!")
      (a, inner, c))
  match made with
  | Ok(a, inner, c) -> println $"{Atomic.add a 1} {Mutex.get inner} {Channel.receive c}"
  | Error p -> println $"failed: {p.message}"
  // made in a job that fails: gone with it
  let lost =
    Contained.run (fun () ->
      let c = Channel.make 1
      Channel.send c "never read"
      let inner = Mutex.make [ "x" ]
      if List.length (Mutex.get inner) = 1 then panic "lost" else c)
  match lost with
  | Ok _ -> println "returned"
  | Error p -> println $"failed: {p.message}"
  // a message from another thread received in a job, and one sent from a job to another thread
  let toJob : Channel<list<string>> = Channel.make 1
  let fromJob : Channel<list<string>> = Channel.make 1
  let inJob () =
    Contained.run (fun () ->
      match Channel.receive toJob with
      | Some xs ->
        Channel.send fromJob (List.rev xs)
        String.join " " xs
      | None -> "closed")
  let outside () =
    Channel.send toJob [ "over"; "the"; "boundary" ]
    Channel.receive fromJob
  let (got, echoed) = Parallel.both inJob outside
  println $"{got} {echoed}"
  // a closed channel: the send's panic is the job's
  Channel.close ch
  println $"{Contained.run (fun () -> Channel.send ch "late")}"
