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

/// Whether the option holds a value for which `f` is true.
let exists f o =
  match o with
  | Some x -> f x
  | None -> false

/// Whether the value of `Some` satisfies `f`; `None` does.
let forall f o =
  match o with
  | Some x -> f x
  | None -> true

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

/// The `option { }` builder: `let! x = o` stops with `None` when `o` is `None`, and `return x`
/// is `Some x`.
module Builder =
  /// `let!`: the rest with the value of `Some`, or `None`.
  let bind o f =
    match o with
    | Some x -> f x
    | None -> None

  /// `return x`: `Some x`.
  let ret x = Some x

  /// An `if` without `else`, or a body that ends in a statement: `Some ()`.
  let zero () = Some ()

  /// The body, run now.
  let delay f = f ()

  /// `use x = e`: the rest with `x`, which is disposed after it.
  let using x f =
    let r = f x
    dispose x
    r

  /// `for x in xs do`: the body for each element of any collection, until one gives `None`.
  let forEach (xs: 'c) (f: 'a -> option<unit>) : option<unit> =
    let ran =
      Iter.forEach xs (fun x ->
        match f x with
        | Some () -> true
        | None -> false)

    if ran then Some () else None

type option<'a> with
  /// Whether the option holds a value.
  member o.IsSome = Option.isSome o
  /// Whether the option is `None`.
  member o.IsNone = Option.isNone o

/// An option's one element, or none.
impl Iter<option<'a>, 'a> =
  let forEach o f =
    match o with
    | Some x -> f x
    | None -> true
