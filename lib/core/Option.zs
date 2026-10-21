/// Functions on options, values that may be missing: `Some x` or `None` (the type is in the
/// prelude).
module Option

/// Applies `f` to the value of `Some`; `None` stays `None`.
let map f o =
  match o with
  | Some x -> Some (f x)
  | None -> None

/// Applies `f`, which itself returns an option, to the value of `Some`.
let bind f o =
  match o with
  | Some x -> f x
  | None -> None

/// The value of `Some`, or `d` for `None`.
let defaultValue d o =
  match o with
  | Some x -> x
  | None -> d

/// Whether the option holds a value.
let isSome o =
  match o with
  | Some _ -> true
  | None -> false

/// Whether the option is `None`.
let isNone o = not (Option.isSome o)

/// The value of `Some`. Panics on `None`; prefer a match or `Option.defaultValue`.
let get o =
  match o with
  | Some x -> x
  | None -> panic "Option.get: None"

/// `[x]` for `Some x`, `[]` for `None`.
let toList o =
  match o with
  | Some x -> [ x ]
  | None -> []

/// The option itself if it is `Some`, otherwise `other`.
let orElse other o =
  match o with
  | Some _ -> o
  | None -> other

/// Calls `f` on the value of `Some`; does nothing for `None`.
let iter f o =
  match o with
  | Some x -> f x
  | None -> ()

/// `Ok x` for `Some x`, `Error err` for `None`.
let toResult err o =
  match o with
  | Some x -> Ok x
  | None -> Error err

type option<'a> with
  /// Whether the option holds a value.
  member o.IsSome = Option.isSome o
  /// Whether the option is `None`.
  member o.IsNone = Option.isNone o
