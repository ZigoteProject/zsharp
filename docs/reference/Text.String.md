# Text.String

Functions on strings: immutable UTF-8 text. Lengths and indexes count bytes; `for c in s`
and `String.chars` give the characters.

## Types

#### `string#Length`

```zsharp
member s.Length
```

The length in bytes (UTF-8).

#### `string#Contains`

```zsharp
member s.Contains(sub: string)
```

Whether `sub` occurs in the string.

#### `string#StartsWith`

```zsharp
member s.StartsWith(p: string)
```

Whether the string begins with `p`.

#### `string#EndsWith`

```zsharp
member s.EndsWith(p: string)
```

Whether the string ends with `p`.

#### `string#IndexOf`

```zsharp
member s.IndexOf(sub: string)
```

The byte index of the first `sub`, or `None`.

#### `string#Split`

```zsharp
member s.Split(sep: string)
```

The pieces between occurrences of `sep`.

#### `string#Substring`

```zsharp
member s.Substring(start: int, len: int)
```

The `len` bytes starting at byte `start`. Panics if out of range.

#### `string#Trim`

```zsharp
member s.Trim()
```

The string without leading and trailing spaces, tabs and line breaks.

#### `string#ToUpper`

```zsharp
member s.ToUpper()
```

The string with ASCII letters in upper case.

#### `string#ToLower`

```zsharp
member s.ToLower()
```

The string with ASCII letters in lower case.

#### `string#Replace`

```zsharp
member s.Replace(old: string, by: string)
```

The string with every `old` replaced by `by`.

## Functions

### `String.isEmpty`

```zsharp
String.isEmpty : string -> bool
```

Whether the string has no bytes.

### `String.contains`

```zsharp
String.contains : string -> string -> bool
```

Whether `sub` occurs in `s`.

### `String.indexOf`

```zsharp
String.indexOf : string -> string -> option<int>
```

The byte index of the first `sub` in `s`, or `None`.

### `String.lastIndexOf`

```zsharp
String.lastIndexOf : string -> string -> option<int>
```

The byte index of the last `sub` in `s`, or `None`.

### `String.startsWith`

```zsharp
String.startsWith : string -> string -> bool
```

Whether `s` begins with `p`.

### `String.endsWith`

```zsharp
String.endsWith : string -> string -> bool
```

Whether `s` ends with `p`.

### `String.split`

```zsharp
String.split : string -> string -> list<string>
```

The pieces of `s` between occurrences of `sep`: `String.split ", " "a, b" = ["a"; "b"]`.

### `String.join`

```zsharp
String.join : string -> list<string> -> string
```

The strings with `sep` between them.

### `String.concat`

```zsharp
String.concat : list<string> -> string
```

The strings joined with nothing between them.

### `String.repeat`

```zsharp
String.repeat : 'a -> string -> string
```

`s` repeated `n` times.

### `String.parseInt`

```zsharp
String.parseInt : string -> option<int>
```

The integer written in `s` (optional sign, decimal digits), or `None`.

### `String.parseFloat`

```zsharp
String.parseFloat : string -> option<f64>
```

The floating-point number written in `s`, or `None`.

### `String.decodeAt`

```zsharp
String.decodeAt : string -> int -> char * int
```

The character that starts at byte `i` of `s`, and the byte index after it (UTF-8 decoding;
a malformed sequence gives U+FFFD and moves one byte). `for c in s` uses it.

### `String.chars`

```zsharp
String.chars : string -> list<char>
```

The characters of `s`, in order (decoded from UTF-8).

### `String.charCount`

```zsharp
String.charCount : string -> 'a when 'a : Add
```

The number of characters in `s`. `String.length` counts bytes.

### `String.ofChar`

```zsharp
String.ofChar : char -> string
```

A string of one character (its UTF-8 encoding).

### `String.ofChars`

```zsharp
String.ofChars : list<char> -> string
```

A string of the characters, in order.

### `String.byte`

```zsharp
String.byte : string -> int -> u8
```

The byte at index `i`. Panics if out of range.

### `String.bytes`

```zsharp
String.bytes : string -> span<u8>
```

The string's bytes (its UTF-8), as a span: no copy.

### `String.indexOfFrom`

```zsharp
String.indexOfFrom : string -> string -> int -> int
```

The byte index of the first `sub` in `s` at or after byte `from`, or -1.

### `String.length`

```zsharp
String.length : string -> int
```

The length in bytes (UTF-8).

### `String.ofByte`

```zsharp
String.ofByte : u8 -> string
```

A one-byte string.

### `String.ofBytes`

```zsharp
String.ofBytes : span<u8> -> string
```

A string with a copy of the bytes, each malformed UTF-8 byte replaced by U+FFFD.

### `String.ofCStr`

```zsharp
String.ofCStr : cstr -> string
```

A Z# string copied from a C string (`const char*`).

### `String.replace`

```zsharp
String.replace : string -> string -> string -> string
```

`s` with every occurrence of `old` replaced by `by`.

### `String.sub`

```zsharp
String.sub : string -> int -> int -> string
```

The `len` bytes of `s` starting at byte `start`. Panics if out of range.

### `String.toLower`

```zsharp
String.toLower : string -> string
```

`s` with ASCII letters in lower case.

### `String.toUpper`

```zsharp
String.toUpper : string -> string
```

`s` with ASCII letters in upper case.

### `String.trim`

```zsharp
String.trim : string -> string
```

`s` without leading and trailing spaces, tabs and line breaks.

