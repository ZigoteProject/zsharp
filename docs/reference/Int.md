# Int

Integer arithmetic the operators don't do (they panic on overflow, except in a `[<Wrapping>]`
function): wrapping around, for hashes and checksums; checked, giving an `option`; saturating,
stopped at the type's bounds; the bit operations; and parsing. Most of its functions are
built into the compiler, an instruction each where the target has one.

## Functions

### `Int.parseRadix`

```zsharp
Int.parseRadix : int -> string -> option<'a>
```

The integer `s` writes in radix 2 to 36 (letters for the digits past 9, in either case): an
optional sign, then the digits, and nothing else (no spaces, `_` or `0x`); `None` for anything
else or a number outside the type's range. The type is the result's
(`let mask: option<u8> = Int.parseRadix 16 "ff"`), `int` when nothing else says.

### `Int.parse`

```zsharp
Int.parse : string -> option<'a>
```

The integer `s` writes in decimal, as `Int.parseRadix 10`: `Int.parse "-42"` is `Some -42`.

### `Int.checkedAdd`

```zsharp
Int.checkedAdd : 'a -> 'a -> option<'a>
```

`a + b`, or `None` when the sum doesn't fit the type: `Int.checkedAdd (u8 200) (u8 100)` is
`None`, and `Int.checkedAdd 1 2` is `Some 3`. For sums whose overflow is an input's fault, not
a bug: a parsed size, a timestamp plus a duration.

### `Int.checkedSub`

```zsharp
Int.checkedSub : 'a -> 'a -> option<'a>
```

`a - b`, or `None` when the difference doesn't fit the type: `Int.checkedSub (u8 3) (u8 5)` is
`None`.

### `Int.checkedMul`

```zsharp
Int.checkedMul : 'a -> 'a -> option<'a>
```

`a * b`, or `None` when the product doesn't fit the type: `Int.checkedMul (u8 16) (u8 16)` is
`None`.

### `Int.byteSwap`

```zsharp
Int.byteSwap : 'a -> 'a
```

The bytes in the other order, for a number read in the other endianness: `Int.byteSwap (u16 0x1234)` is `0x3412`; a `u8` or `i8` is itself.

### `Int.leadingZeros`

```zsharp
Int.leadingZeros : 'a -> int
```

The number of zero bits above the highest bit set, the type's width for 0: `Int.leadingZeros (u8 1)` is 7.

### `Int.popCount`

```zsharp
Int.popCount : 'a -> int
```

The number of bits set: `Int.popCount (u8 255)` is 8.

### `Int.rotateLeft`

```zsharp
Int.rotateLeft : 'a -> int -> 'a
```

The bits rotated left by `n` places modulo the type's width, the bits leaving at the top coming back in at the bottom; a negative `n` rotates right: `Int.rotateLeft (u8 0b10010001) 1` is `0b00100011`.

### `Int.rotateRight`

```zsharp
Int.rotateRight : 'a -> int -> 'a
```

The bits rotated right by `n` places modulo the type's width; a negative `n` rotates left.

### `Int.saturatingAdd`

```zsharp
Int.saturatingAdd : 'a -> 'a -> 'a
```

`a + b`, stopped at the type's bounds on overflow instead of panicking: `Int.saturatingAdd (u8 200) (u8 100)` is 255.

### `Int.saturatingMul`

```zsharp
Int.saturatingMul : 'a -> 'a -> 'a
```

`a * b`, stopped at the type's bounds on overflow: `Int.saturatingMul (i8 -100) (i8 2)` is -128.

### `Int.saturatingSub`

```zsharp
Int.saturatingSub : 'a -> 'a -> 'a
```

`a - b`, stopped at the type's bounds on overflow: `Int.saturatingSub (u8 3) (u8 5)` is 0.

### `Int.trailingZeros`

```zsharp
Int.trailingZeros : 'a -> int
```

The number of zero bits below the lowest bit set, the type's width for 0: `Int.trailingZeros 8` is 3.

### `Int.wrappingAdd`

```zsharp
Int.wrappingAdd : 'a -> 'a -> 'a
```

`a + b`, wrapping around on overflow instead of panicking.

### `Int.wrappingMul`

```zsharp
Int.wrappingMul : 'a -> 'a -> 'a
```

`a * b`, wrapping around on overflow instead of panicking.

### `Int.wrappingSub`

```zsharp
Int.wrappingSub : 'a -> 'a -> 'a
```

`a - b`, wrapping around on overflow instead of panicking.

