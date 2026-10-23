/// Integer arithmetic that wraps around on overflow, for hashes and checksums (the operators
/// panic on overflow instead, except in a `[<Wrapping>]` function). Its functions are built
/// into the compiler.
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
