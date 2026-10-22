/// Buffers: an array's storage as a shared, mutable reference, so a write is seen through every
/// reference (an `array` is a value instead). A slice of a Buffer (`b.[i..j]`) is a Buffer
/// too, a window sharing its storage. Its other functions are built into the compiler.
module Collections.Buffer

/// The `n` elements from index `i`, as a Buffer sharing this one's storage: a write to either
/// is seen through both. `b.[i .. i + n - 1]`.
let slice (b: Buffer<'a>) i n = b.[i .. i + n - 1]
