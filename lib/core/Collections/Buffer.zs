/// Buffers: an array's storage as a shared, mutable reference, so a write is seen through every
/// reference (an `array` is a value instead), and one that grows: `Buffer.push` adds an element
/// at the end (in amortized constant time, the storage doubling when full), `Buffer.pop` takes
/// one. A slice of a Buffer (`b.[i..j]`) is a Buffer too, sharing the storage until either grows
/// past it. Its other functions are built into the compiler: `create`, `length`, `ofArray`,
/// `ofSpan`, `toArray`, `push`, `removeLast` (the last element, taken; a panic when there's
/// none), `truncate` (the first `n` elements kept) and `blit` (`n` elements of a span copied in).
module Collections.Buffer

/// An empty Buffer, a new one at each use: `let names = Buffer.empty` then `Buffer.push n names`.
let empty : Buffer<'a> = Buffer.ofArray [||]

/// The last element, taken out of the Buffer, or `None` when it's empty.
let pop (b: Buffer<'a>) = if Buffer.length b = 0 then None else Some (Buffer.removeLast b)

/// Removes every element.
let clear (b: Buffer<'a>) = Buffer.truncate 0 b

/// The `n` elements from index `i`, as a Buffer sharing this one's storage: a write to either
/// is seen through both. `b.[i .. i + n - 1]`.
let slice (b: Buffer<'a>) i n = b.[i .. i + n - 1]
