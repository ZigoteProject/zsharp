/// Integer arithmetic the operators don't do (they panic on overflow, except in a `[<Wrapping>]`
/// function): wrapping around, for hashes and checksums; checked, giving an `option`; saturating,
/// stopped at the type's bounds; the bit operations; and parsing. Most of its functions are
/// built into the compiler, an instruction each where the target has one.
module Int

/// The integer `s` writes in radix 2 to 36 (letters for the digits past 9, in either case): an
/// optional sign, then the digits, and nothing else (no spaces, `_` or `0x`); `None` for anything
/// else or a number outside the type's range. The type is the result's
/// (`let mask: option<u8> = Int.parseRadix 16 "ff"`), `int` when nothing else says.
let parseRadix (radix: int) (s: string) : option<'a> =
  let (ok, n) = Native.parseInt radix s
  if ok then Some n else None

/// The integer `s` writes in decimal, as `Int.parseRadix 10`: `Int.parse "-42"` is `Some -42`.
let parse (s: string) : option<'a> = Int.parseRadix 10 s

/// `a + b`, or `None` when the sum doesn't fit the type: `Int.checkedAdd (u8 200) (u8 100)` is
/// `None`, and `Int.checkedAdd 1 2` is `Some 3`. For sums whose overflow is an input's fault, not
/// a bug: a parsed size, a timestamp plus a duration.
let checkedAdd (a: 'a) (b: 'a) : option<'a> =
  let (ok, n) = Native.checkedAdd a b
  if ok then Some n else None

/// `a - b`, or `None` when the difference doesn't fit the type: `Int.checkedSub (u8 3) (u8 5)` is
/// `None`.
let checkedSub (a: 'a) (b: 'a) : option<'a> =
  let (ok, n) = Native.checkedSub a b
  if ok then Some n else None

/// `a * b`, or `None` when the product doesn't fit the type: `Int.checkedMul (u8 16) (u8 16)` is
/// `None`.
let checkedMul (a: 'a) (b: 'a) : option<'a> =
  let (ok, n) = Native.checkedMul a b
  if ok then Some n else None
