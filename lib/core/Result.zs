/// Functions on results, the outcome of something that can fail: `Ok value` or `Error err` (the
/// type is in the prelude).
module Result

/// Applies `f` to the value of `Ok`; an `Error` passes through.
let map f r =
  match r with
  | Ok x -> Ok (f x)
  | Error e -> Error e

/// Applies `f`, which itself returns a result, to the value of `Ok`.
let bind f r =
  match r with
  | Ok x -> f x
  | Error e -> Error e

/// Applies `f` to the error of `Error`; an `Ok` passes through.
let mapError f r =
  match r with
  | Ok x -> Ok x
  | Error e -> Error (f e)

/// The value of `Ok`, or `d` for an `Error`.
let defaultValue d r =
  match r with
  | Ok x -> x
  | Error _ -> d

/// Whether the result is `Ok`.
let isOk r =
  match r with
  | Ok _ -> true
  | Error _ -> false

/// Whether the result is `Error`.
let isError r = not (Result.isOk r)

/// `Some x` for `Ok x`, `None` for an `Error`.
let toOption r =
  match r with
  | Ok x -> Some x
  | Error _ -> None
