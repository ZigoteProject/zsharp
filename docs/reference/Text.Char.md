# Text.Char

Functions on characters: `char`, a Unicode scalar value such as `'a'` or `'é'`. The tests
know ASCII; other letters aren't classified.

## Functions

### `Char.isDigit`

```zsharp
Char.isDigit : char -> bool
```

Whether `c` is an ASCII digit, '0' to '9'.

### `Char.isLower`

```zsharp
Char.isLower : char -> bool
```

Whether `c` is an ASCII lower-case letter.

### `Char.isUpper`

```zsharp
Char.isUpper : char -> bool
```

Whether `c` is an ASCII upper-case letter.

### `Char.isLetter`

```zsharp
Char.isLetter : char -> bool
```

Whether `c` is an ASCII letter.

### `Char.isLetterOrDigit`

```zsharp
Char.isLetterOrDigit : char -> bool
```

Whether `c` is an ASCII letter or digit.

### `Char.isWhitespace`

```zsharp
Char.isWhitespace : char -> bool
```

Whether `c` is a space, tab, line feed or carriage return.

### `Char.toUpper`

```zsharp
Char.toUpper : char -> char
```

`c` in upper case (ASCII letters; others unchanged).

### `Char.toLower`

```zsharp
Char.toLower : char -> char
```

`c` in lower case (ASCII letters; others unchanged).

### `Char.digitValue`

```zsharp
Char.digitValue : char -> option<int>
```

The value of an ASCII digit: `Some 7` for '7', `None` for anything else.

