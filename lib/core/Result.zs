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

/// The `result { }` builder: `let! x = r` stops with the `Error` when `r` is one, and
/// `return x` is `Ok x`.
module Builder =
  /// `let!`: the rest with the value of `Ok`, or the `Error`.
  let bind r f =
    match r with
    | Ok x -> f x
    | Error e -> Error e

  /// `return x`: `Ok x`.
  let ret x = Ok x

  /// An `if` without `else`, or a body that ends in a statement: `Ok ()`.
  let zero () = Ok ()

  /// The body, run now.
  let delay f = f ()

  /// `use x = e`: the rest with `x`, which is disposed after it.
  let using x f =
    let r = f x
    dispose x
    r

  /// `for x in xs do`: the body for each element, until one gives an `Error`.
  let rec forEach xs f =
    match xs with
    | [] -> Ok ()
    | x :: rest ->
      match f x with
      | Ok () -> forEach rest f
      | Error e -> Error e
