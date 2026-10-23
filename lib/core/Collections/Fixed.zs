/// Fixed-size arrays: `fixed<u8, 16>` holds 16 elements inline, in a record as C's
/// `uint8_t data[16]` is in a struct. A value, copied like a record and indexed like an array:
/// `f.[i]`, and `f.[i] <- x` when `f` (or the record holding it) is `let mutable`. The length
/// is a number in the type.
module Collections.Fixed

/// A fixed-size array with `f i` at index `i` (its length from the type expected of it).
let init (f: int -> 'a) : fixed<'a, 'n> =
  let mutable r = Fixed.create (f 0)
  for i in 1 .. Fixed.length r - 1 do
    r <- Fixed.set r i (f i)
  r

/// The elements in an array of their own.
let toArray (x: fixed<'a, 'n>) = Array.init (Fixed.length x) (fun i -> x.[i])

/// Calls `f` on every element, in order.
let iter f (x: fixed<'a, 'n>) =
  for i in 0 .. Fixed.length x - 1 do
    f x.[i]

/// A fixed-size array with `f` applied to every element.
let map (f: 'a -> 'b) (x: fixed<'a, 'n>) : fixed<'b, 'n> = Fixed.init (fun i -> f x.[i])

/// Combines the elements from the left, like `Array.fold`.
let fold f state (x: fixed<'a, 'n>) =
  let mutable acc = state
  for i in 0 .. Fixed.length x - 1 do
    acc <- f acc x.[i]
  acc

/// Element by element, as records' fields are.
impl Eq<fixed<'a, 'n>> =
  let equal (a: fixed<'a, 'n>) (b: fixed<'a, 'n>) =
    let mutable same = true
    for i in 0 .. Fixed.length a - 1 do
      if same then
        same <- a.[i] = b.[i]
    same

/// By the first element that differs.
impl Ord<fixed<'a, 'n>> =
  let compare (a: fixed<'a, 'n>) (b: fixed<'a, 'n>) =
    let mutable r = 0
    for i in 0 .. Fixed.length a - 1 do
      if r = 0 then
        r <- compare a.[i] b.[i]
    r

/// Consistent with `Eq`.
impl Hash<fixed<'a, 'n>> =
  let hash (x: fixed<'a, 'n>) =
    let mutable h = 17
    for i in 0 .. Fixed.length x - 1 do
      h <- Int.wrappingAdd (Int.wrappingMul h 31) (hash x.[i])
    h

/// As F# prints an array: `[|1; 2; 3|]`.
impl Show<fixed<'a, 'n>> =
  let show (x: fixed<'a, 'n>) =
    let mutable s = "[|"
    for i in 0 .. Fixed.length x - 1 do
      s <- s + (if i > 0 then "; " else "") + show x.[i]
    s + "|]"

/// A fixed-size array's elements, by index.
impl Iter<fixed<'a, 'n>, 'a> =
  let forEach (x: fixed<'a, 'n>) f =
    let mutable i = 0
    let mutable ok = true
    while ok && i < Fixed.length x do
      ok <- f x.[i]
      i <- i + 1
    ok
