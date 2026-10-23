/// Functions for the `Throw` effect (typed exceptions): turning a failure into a `result`, or
/// a `result` into a failure.
module Throw

/// Runs `f`, giving `Ok` of its result, or `Error e` when it throws `e`:
/// `Throw.catch (fun () -> digit c)`.
let catch f =
  handle f () with
  | Throw.throw e, _ -> Error e
  | return x -> Ok x

/// Runs `f`, giving its result, or `onError e` when it throws `e`.
let recover onError f =
  handle f () with
  | Throw.throw e, _ -> onError e

/// The value of an `Ok`, or the error of an `Error` thrown: `Throw.ofResult (Int.parse s)`.
let ofResult r =
  match r with
  | Ok x -> x
  | Error e -> Throw.throw e

/// The value of a `Some`, or `e` thrown for `None`.
let ofOption e o =
  match o with
  | Some x -> x
  | None -> Throw.throw e
