// Contained.run (0035): a job's result, a panic's message, and the program going on
open Threading

type Shape =
  | Circle of float
  | Rect of float * float

let area (s: Shape) : float =
  match s with
  | Circle r -> 3.0 * r * r
  | Rect(w, h) -> w * h

let pick (xs: array<int>) (i: int) : int = xs.[i]

let main () =
  // a result that's a number
  match Contained.run (fun () -> 6 * 7) with
  | Ok n -> println $"ok {n}"
  | Error p -> println $"failed: {p.message}"
  // a panic: its message, and the program goes on
  let xs = [| 1; 2; 3 |]
  match Contained.run (fun () -> pick xs 7) with
  | Ok n -> println $"ok {n}"
  | Error p -> println $"failed: {p.message}"
  // what the job captured is still the caller's
  println $"xs is {Array.toList xs}"
  // a result built in the job: a string, a list, a union, a record's worth of each
  match Contained.run (fun () ->
    (String.join ", " [ "a"; "b"; "c" ],
      List.map (fun x -> x * x) [ 1; 2; 3 ],
      [ Circle 1.0; Rect(2.0, 3.0) ])) with
  | Ok(s, squares, shapes) -> println $"{s} {squares} {List.map area shapes}"
  | Error p -> println $"failed: {p.message}"
  // a job in a job: the inner one's panic is the outer one's Error
  let outer =
    Contained.run (fun () ->
      match Contained.run (fun () -> panic "inner") with
      | Ok() -> "inner returned"
      | Error p -> "caught " + p.message)
  match outer with
  | Ok s -> println s
  | Error p -> println $"failed: {p.message}"
  // an explicit panic
  match Contained.run (fun () -> if Array.length xs = 3 then panic "three" else 0) with
  | Ok n -> println $"ok {n}"
  | Error p -> println $"failed: {p.message}"
  println "done"
