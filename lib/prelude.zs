// Z# prelude: the names every program has without qualification (the operator traits and
// their derives, option, result, and a few functions). The rest of the library is in core/
// (every target) and std/ (targets with an operating system), opened by namespace. Every item
// is documented with `///` comments, which hover, completion, `zs doc` and the MCP `docs` tool show.

// The operator traits below have built-in impls for the primitive types; user types implement
// them with `impl`. Eq, Ord, Hash and Show are also derived for every record and union.

/// `+` and a zero, for `List.sum`. Built in for numbers and `string` (concatenation, "").
trait Add<'a> =
  /// `a + b`.
  abstract add : 'a -> 'a -> 'a
  /// The value that `+` leaves unchanged: `0`, `0.0`, `""`.
  abstract zero : 'a

/// `-`, `*`, `/`, `%` and negation. Built in for the integer and floating-point types.
trait Num<'a> =
  /// `a - b`.
  abstract sub : 'a -> 'a -> 'a
  /// `a * b`.
  abstract mul : 'a -> 'a -> 'a
  /// `a / b`. Integer division by zero panics.
  abstract div : 'a -> 'a -> 'a
  /// `a % b`. Integer remainder by zero panics.
  abstract rem : 'a -> 'a -> 'a
  /// `-a`.
  abstract neg : 'a -> 'a

/// `=` and `<>`. Built in for primitives; derived structurally for records, unions and tuples.
trait Eq<'a> =
  /// `a = b`.
  abstract equal : 'a -> 'a -> bool

/// `<`, `>`, `<=`, `>=` and `compare`. Built in for numbers and strings; derived for records,
/// unions (by case order, then fields) and tuples (lexicographically).
trait Ord<'a> =
  /// A negative number, zero or a positive number as `a` is less than, equal to or greater than `b`.
  abstract compare : 'a -> 'a -> int

/// Text for a value: what `string x` and `$"{x}"` use. Built in for numbers, bools and
/// strings; derived for records (`{ x = 1; y = 2 }`) and unions (`Some 1`, `Rect (1, 2)`).
trait Show<'a> =
  /// The value as text.
  abstract show : 'a -> string

/// A hash code, consistent with `Eq`: equal values hash the same.
trait Hash<'a> =
  /// The value's hash code.
  abstract hash : 'a -> int

/// What `use x = e` gives back when its scope ends (and, in a task, when the task is cancelled):
/// a socket closed, a file shut, a handle released.
trait Dispose<'a> =
  /// Releases what the value holds.
  abstract dispose : 'a -> unit

/// What `match Shape.kind with` distinguishes inside a `derive`.
type ShapeKind =
  /// The type being derived for is a record.
  | RecordKind
  /// The type being derived for is a union.
  | UnionKind

/// Structural equality for records and unions: same case and equal fields. Applied the first
/// time a type needs `=`; an explicit `impl Eq` or `[<NoEquality>]` takes precedence.
derive Eq =
  let equal (a: 'self) (b: 'self) =
    match Shape.pair a b with
    | Same c ->
      let mutable same = true
      for f in c.fields do
        if same then same <- f.left = f.right
      same
    | Different _ -> false

/// Structural ordering for records and unions: by case (in declaration order), then field by
/// field. Applied the first time a type needs it; `[<NoComparison>]` opts out.
derive Ord =
  let compare (a: 'self) (b: 'self) =
    match Shape.pair a b with
    | Same c ->
      let mutable r = 0
      for f in c.fields do
        if r = 0 then r <- compare f.left f.right
      r
    | Different (i, j) -> compare i j

/// A structural hash for records and unions, consistent with the derived `Eq`.
derive Hash =
  let hash (x: 'self) =
    match Shape.of x with
    | Record r ->
      let mutable h = 17
      for f in r.fields do
        h <- Int.wrappingAdd (Int.wrappingMul h 31) (hash f.value)
      h
    | Union c ->
      let mutable h = 17 + c.index
      for f in c.fields do
        h <- Int.wrappingAdd (Int.wrappingMul h 31) (hash f.value)
      h

/// F#-style text for records (`{ x = 1; y = 2 }`) and unions (`Leaf`, `Some 1`, `Rect (1, 2)`).
derive Show =
  let show (x: 'self) =
    match Shape.of x with
    | Record r ->
      let mutable s = "{ "
      for f in r.fields do
        s <- s + (if f.index > 0 then "; " else "") + f.name + " = " + show f.value
      s + " }"
    | Union c ->
      let mutable s = c.name
      for f in c.fields do
        s <- s + (if f.index = 0 then (if c.count > 1 then " (" else " ") else ", ") + show f.value
      if c.count > 1 then s + ")" else s

/// A value that may be missing. Use it instead of null: `Some x` or `None`.
type option<'a> =
  /// No value.
  | None
  /// A value.
  | Some of 'a

/// The outcome of something that can fail: `Ok value` or `Error err`. The `?` operator
/// returns early with the `Error`.
type result<'a, 'e> =
  /// Success, with its value.
  | Ok of 'a
  /// Failure, with its error.
  | Error of 'e

/// The elements of a sequence, one at a time: what `yield` in a `seq { }` performs, and what
/// a `Seq`'s consumer handles (DESIGN §6.1).
effect Yield<'a> =
  /// Gives the element `x` to the consumer, which resumes the sequence for the next one (or
  /// doesn't, when it needs no more).
  abstract yield : 'a -> unit

/// Typed exceptions: a function that may fail says so in its type (`int / Throw<string>`), and
/// `Throw.catch` turns the failure back into a `result` where it's handled. A boundary between
/// modules returns `result` instead, as it always has.
effect Throw<'e> =
  /// Stops what was running with the error `e`: nothing after it runs, and the handler's clause
  /// gives the result.
  abstract throw : 'e -> 'a

/// Returns its argument unchanged.
let id x = x

/// The first component of a pair.
let fst (a, _) = a

/// The second component of a pair.
let snd (_, b) = b

/// The larger of two values.
let max a b = if a > b then a else b

/// The smaller of two values.
let min a b = if a < b then a else b

/// Lists print as `[1; 2; 3]`.
impl Show<list<'a>> =
  let show xs =
    let rec go acc first xs =
      match xs with
      | [] -> acc
      | x :: rest -> go (acc + (if first then "" else "; ") + show x) false rest
    "[" + go "" true xs + "]"
