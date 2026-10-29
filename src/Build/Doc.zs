/// zs doc: a file's Markdown reference, every documented item with its checked type (the F#
/// compiler's Driver.docItems and Main's doc), and the docs of the functions built into the
/// compiler, which have no definition to read a comment from. The editor's hover reads the same.
open Diag.Diagnostic

/// Docs for the functions built into the compiler (they have no definition to read a comment from):
/// the F# compiler's Driver.builtinDocs, then the SIMD functions', which every vector type's module has.
let private plainDocs : list<string * string> =
  [ ("print", "Writes the string to standard output, without a newline.")
    ("println", "Writes the string and a newline to standard output.")
    ("eprintln", "Writes the string and a newline to standard error.")
    ("string", "The text form of a value (`Show.show`): numbers, bools, strings, and any type with `Show`.")
    ("panic", "Stops the program with the message (and a backtrace). For bugs, not for errors a caller should handle.")
    ("failwith", "Same as `panic`.")
    ("assert", "Panics with \"assertion failed\" when the condition is false; for a comparison (`assert (a = b)`), the message shows both sides and where they first differ.")
    ("Float.toBits", "The number's 64 bits, as IEEE 754 lays them out (`Float.ofBits` gives it back).")
    ("Float.ofBits", "The number whose IEEE 754 bits these are (`Float.toBits` gives them).")
    ("Float.toBits32", "An `f32`'s 32 bits, as IEEE 754 lays them out (`Float.ofBits32` gives it back).")
    ("Float.ofBits32", "The `f32` whose IEEE 754 bits these are (`Float.toBits32` gives them).")
    ("ignore", "Discards a value.")
    ("ref", "A mutable cell holding the value; read and write it with `r.Value`.")
    ("Collections.Array.create", "An array of `n` copies of `x`.")
    ("Collections.Array.length", "The number of elements (of an array, a Buffer or a span).")
    ("Collections.Array.ofSpan", "An array with a copy of the span's elements.")
    ("Collections.Span.length", "The number of elements.")
    ("Collections.Fixed.length", "The number of elements: the N of fixed<'a, N>.")
    ("Collections.Fixed.get", "The element at index `i`. Panics if out of range.")
    ("Collections.Fixed.set", "The fixed-size array with element `i` replaced by `x` (a value: the original is unchanged).")
    ("Collections.Fixed.create", "N copies of `x`, N from the type expected of it.")
    ("Collections.Fixed.ofArray", "A fixed-size array with the elements of `a`, which must have exactly N (a panic otherwise).")
    ("Collections.Span.ofPtr", "A span over `n` elements of C memory at `p`, in `unsafe`: its lifetime isn't checked, so the span mustn't outlive the memory.")
    ("Collections.Buffer.ofSpan", "A new Buffer with a copy of the span's elements.")
    ("Text.String.bytes", "The string's bytes (its UTF-8), as a span: no copy.")
    ("Text.String.ofBytes", "A string with a copy of the bytes, each malformed UTF-8 byte replaced by U+FFFD.")
    ("Text.String.length", "The length in bytes (UTF-8).")
    ("Text.String.sub", "The `len` bytes of `s` starting at byte `start`. Panics if out of range.")
    ("Text.String.byte", "The byte at index `i`. Panics if out of range.")
    ("Text.String.ofByte", "A one-byte string.")
    ("Text.String.trim", "`s` without leading and trailing spaces, tabs and line breaks.")
    ("Text.String.toUpper", "`s` with ASCII letters in upper case.")
    ("Text.String.toLower", "`s` with ASCII letters in lower case.")
    ("Text.String.replace", "`s` with every occurrence of `old` replaced by `by`.")
    ("Text.String.ofCStr", "A Z# string copied from a C string (`const char*`).")
    ("Text.String.indexOfFrom", "The byte index of the first `sub` in `s` at or after byte `from`, or -1.")
    ("Collections.Array.set", "`a` with element `i` replaced by `x`. Arrays are values: `a` itself is unchanged (it is reused in place when nothing else refers to it).")
    ("Collections.Array.copy", "A new array with the same elements (copied at once, as by `memcpy`).")
    ("Collections.Buffer.create", "A Buffer of `n` copies of `x`. A Buffer is shared and mutable: a write is seen through every reference.")
    ("Collections.Buffer.length", "The number of elements.")
    ("Collections.Buffer.ofArray", "A new Buffer with the array's elements.")
    ("Collections.Buffer.toArray", "An array copy of the elements (of a Buffer, or of any span).")
    ("Int.wrappingAdd", "`a + b`, wrapping around on overflow instead of panicking.")
    ("Int.wrappingSub", "`a - b`, wrapping around on overflow instead of panicking.")
    ("Int.wrappingMul", "`a * b`, wrapping around on overflow instead of panicking.")
    ("Runtime.allocations", "The number of heap objects allocated so far.")
    ("Runtime.setClock", "On a microcontroller, the core's clock in Hz, after firmware changes it (its PLL): `Task.sleep` counts SysTick's cycles at this rate (the board's clock at reset unless set).")
    ("Runtime.mallocs", "The number of times memory was taken from the system allocator: for a chunk of the runtime's object pool, a large object, or an arena's block.")
    ("Runtime.marks", "The number of objects marked shared so far, at crossings to other threads: what a value moved to another thread holds alone stays unmarked (`ZS_STATS=1` prints it at exit).")
    ("Ptr.read", "The value the pointer points to. Unsafe: only inside `unsafe`.")
    ("Ptr.write", "Writes the value where the pointer points. Unsafe.")
    ("Ptr.readUnaligned", "The value the pointer points to, at any address (`Ptr.read` assumes the type's alignment): 8 bytes of a packet as a `u64` in one load. Unsafe.")
    ("Ptr.writeUnaligned", "Writes the value where the pointer points, at any address. Unsafe.")
    ("Ptr.diff", "The number of elements from the second pointer to the first (`Ptr.diff end start`), as C's `end - start`. Unsafe.")
    ("Ptr.add", "The pointer moved by a number of elements (pointer arithmetic). Unsafe.")
    ("Ptr.null", "The null pointer.")
    ("Ptr.isNull", "Whether the pointer is null.")
    ("Ptr.alloc", "C memory for a number of elements, zeroed (C's `calloc`); give it back with `Ptr.free`. Unsafe.")
    ("Ptr.free", "Frees memory from `Ptr.alloc` (C's `free`). Unsafe.")
    ("Ptr.ofCPtr", "A C pointer (`cptr`, as `import c` gives one) as a typed pointer. Unsafe.")
    ("Ptr.toCPtr", "The pointer as a `cptr`, to pass to a C function that takes one.")
    ("Ptr.cast", "The same address as a pointer to another type. Unsafe.")
    ("Threading.Atomic.make", "An atomic value holding `x`.")
    ("Threading.Atomic.get", "The value now.")
    ("Threading.Atomic.set", "Sets the value.")
    ("Threading.Atomic.exchange", "Sets the value, giving the one it replaced.")
    ("Threading.Atomic.compareExchange", "Sets the value to `desired` only if it is `expected`, giving the value it held (so it succeeded when that is `expected`), as .NET's `Interlocked.CompareExchange`.")
    ("Threading.Atomic.add", "Adds `n` to the value, giving the new value (an integer wraps around on overflow).")
    ("Threading.Mutex.make", "A mutex holding `x` (which is then shared between threads).")
    ("Threading.Mutex.get", "The value now (with a reference of its own, taken under the lock).")
    ("Threading.Mutex.set", "Replaces the value.")
    ("Threading.Mutex.update", "Replaces the value with `f` of it, holding the lock meanwhile (so updates from several threads don't lose one another), and gives the new value. `f` mustn't use the same mutex.")
    ("Threading.Channel.make", "A channel holding up to `capacity` values; with 0, a send waits for a receiver to take its value.")
    ("Threading.Channel.send", "Sends `x`, waiting while the channel is full. Panics once it's closed.")
    ("Threading.Channel.receive", "The next value, waiting for one: `None` once the channel is closed and empty.")
    ("Threading.Channel.close", "Closes the channel: receivers get what's left, then `None`; a send panics.")
    ("Weak.create", "A weak reference to the object: it doesn't keep the object alive.")
    ("Weak.get", "`Some` object while it lives (with a reference of its own), `None` once it has gone.")
    ("Arena.with", "Runs the function with an arena: what it allocates comes from the arena's blocks, freed at once when the last of those objects goes (when the function returns, unless something it made lives on).")
    ("Math.sqrt", "The square root of an `f64` or `f32` (NaN for a negative number): one instruction where the hardware has it.")
    ("Bits.toU8", "An 8-bit [<Bits>] record's integer.")
    ("Bits.toU16", "A 16-bit [<Bits>] record's integer.")
    ("Bits.toU32", "A 32-bit [<Bits>] record's integer: `Mmio.write32 address (Bits.toU32 r)`.")
    ("Bits.toU64", "A 64-bit [<Bits>] record's integer.")
    ("Bits.ofU8", "The 8-bit [<Bits>] record whose integer this is, gaps kept (the record's type from where it's used).")
    ("Bits.ofU16", "The 16-bit [<Bits>] record whose integer this is, gaps kept.")
    ("Bits.ofU32", "The 32-bit [<Bits>] record whose integer this is, gaps kept: `Bits.ofU32 (Mmio.read32 address)`.")
    ("Bits.ofU64", "The 64-bit [<Bits>] record whose integer this is, gaps kept.")
    ("Bits.raw", "A [<Bits>] record's integer as a u64, whatever its width.")
    ("Bits.ofRaw", "The [<Bits>] record whose integer this is; a bit set past its width panics.")
    ("Cpu.nop", "Nothing, for one instruction's time.")
    ("Cpu.wfi", "Sleeps until an interrupt (on a computer, nothing).")
    ("Cpu.wfe", "Sleeps until an event or an interrupt (on a computer, nothing).")
    ("Cpu.sev", "Signals an event, waking a `wfe` (on a computer, nothing).")
    ("Cpu.dmb", "A data memory barrier: the memory accesses before it complete, as others see them, before any after it.")
    ("Cpu.dsb", "A data synchronization barrier: nothing after it runs until the memory accesses before it complete.")
    ("Cpu.isb", "An instruction barrier: what follows is fetched again, seeing a change to the processor's state (on a computer, nothing).")
    ("Cpu.enableInterrupts", "Lets interrupts in (only on a microcontroller).")
    ("Cpu.disableInterrupts", "Keeps interrupts out until they're enabled again (only on a microcontroller).")
    ("Cpu.critical", "Runs `body` with interrupts masked and gives its value, for a change that handlers mustn't see halfway; one inside another is fine (only on a microcontroller).")
    ("Math.floor", "The largest whole number not above `x`, as an `f64` or `f32`.")
    ("Math.ceil", "The smallest whole number not below `x`, as an `f64` or `f32`.")
    ("Math.round", "The nearest whole number, halves to the even one (`round 2.5` is 2), as F#'s `round`.")
    ("Math.trunc", "`x` without its fraction: toward zero.")
    ("Math.exp", "e to the power `x`.")
    ("Math.log", "The natural logarithm (NaN below zero, minus infinity at zero).")
    ("Math.log2", "The base-2 logarithm.")
    ("Math.log10", "The base-10 logarithm.")
    ("Math.sin", "The sine of an angle in radians.")
    ("Math.cos", "The cosine of an angle in radians.")
    ("Math.tan", "The tangent of an angle in radians.")
    ("Math.pow", "`x` to the power `y`: `pow 2.0 10.0` is 1024.")
    ("Math.atan2", "The angle of the point (`x`, `y`) from the x axis, in radians from -π to π: `atan2 y x`, y first, as C's.")
    ("Runtime.ticks", "A cycle counter for timing code: on a Cortex-M the SysTick count, elsewhere nanoseconds.")
    ("Mmio.read32", "Reads the 32-bit hardware register at an address (a volatile load).")
    ("Mmio.write32", "Writes the 32-bit hardware register at an address (a volatile store).")
    ("Mmio.read8", "Reads the 8-bit hardware register at an address (a volatile load).")
    ("Mmio.write8", "Writes the 8-bit hardware register at an address (a volatile store).")
    ("Environment.exit", "Ends the program now with the exit code (output is flushed; nothing else is cleaned up).")
    ("IO.File.exists", "Whether `path` names an existing regular file.")
    ("IO.Directory.exists", "Whether `path` names an existing directory.") ]

// the SIMD functions' docs: every vector type's module has the same functions
let private simdDocs : list<string * string> =
  let vectors = Types.Ty.vectorTypes
  let one (v: string * string * int) : list<string * string> =
    let (n, e, k) = v
    let m = Types.Ty.simdModule n
    let lanes =
      [ (m + ".splat", $"A {n} with `x` in every lane.")
        (m + ".load", $"The {k} elements of the array from index `i` (all of them in it, or a panic).")
        (m + ".store", "The array with the lanes written into it from index `i`: in place when nothing else refers to it (arrays are values).")
        (m + ".get", $"Lane `i` (0 to {k - 1}).")
        (m + ".set", "The vector with lane `i` replaced by `x`.")
        (m + ".init", $"The vector of `f 0`, …, `f {k - 1}`.")
        (m + ".sum", "The lanes added together, in no particular order (a tree, as SIMD code adds them).")
        (m + ".min", "Lane by lane, the smaller.")
        (m + ".max", "Lane by lane, the larger.")
        (m + ".reduceMin", "The smallest lane.")
        (m + ".reduceMax", "The largest lane.")
        (m + ".abs", "Lane by lane, the absolute value.")
        (m + ".equal", $"Lane by lane, whether `a`'s equals `b`'s: a mask{k}.")
        (m + ".notEqual", $"Lane by lane, whether `a`'s differs from `b`'s: a mask{k}.")
        (m + ".lessThan", $"Lane by lane, whether `a`'s is less than `b`'s: a mask{k}.")
        (m + ".lessOrEqual", $"Lane by lane, whether `a`'s is at most `b`'s: a mask{k}.")
        (m + ".greaterThan", $"Lane by lane, whether `a`'s is greater than `b`'s: a mask{k}.")
        (m + ".greaterOrEqual", $"Lane by lane, whether `a`'s is at least `b`'s: a mask{k}.")
        (m + ".select", "Lane by lane, `a`'s where the mask is true, else `b`'s.")
        (m + ".shuffle", $"The lanes the indices pick (an array literal of {k} constants): 0 to {k - 1} from `a`, {k} to {2 * k - 1} from `b`.") ]
    let floating =
      if Set.contains e Types.Ty.floats then
        [ (m + ".sqrt", "Lane by lane, the square root.")
          (m + ".floor", "Lane by lane, the largest integer not above it.")
          (m + ".ceil", "Lane by lane, the smallest integer not below it.")
          (m + ".round", "Lane by lane, the nearest integer (halves to the even one).")
          (m + ".mulAdd", "Lane by lane, `a * b + c`, rounded once (a fused multiply-add).") ]
      else
        []
    let conversion (w: string * string * int) =
      let (n2, _, k2) = w
      if k2 = k && n2 <> n then [ (m + ".of" + Types.Ty.simdModule n2, $"A {n2} converted lane by lane (a float into an integer saturates).") ] else []
    List.concat [ lanes; floating; List.collect conversion vectors ]
  let mask (mk: string * int) : list<string * string> =
    let (mn, k) = mk
    let mm = Types.Ty.simdModule mn
    [ (mm + ".any", "Whether any lane is true.")
      (mm + ".all", "Whether every lane is true.")
      (mm + ".count", "How many lanes are true.")
      (mm + ".not", "Each lane negated.")
      (mm + ".get", $"Lane `i` (0 to {k - 1}).") ]
  let targets =
    [ ("Simd.X86.rsqrt4", "An estimate of 1 / sqrt x per lane, to within 1.5 × 2^-12 (SSE's rsqrtps).")
      ("Simd.X86.rsqrt8", "An estimate of 1 / sqrt x per lane, to within 1.5 × 2^-12 (AVX's vrsqrtps).")
      ("Simd.X86.rcp4", "An estimate of 1 / x per lane, to within 1.5 × 2^-12 (SSE's rcpps).")
      ("Simd.X86.rcp8", "An estimate of 1 / x per lane, to within 1.5 × 2^-12 (AVX's vrcpps).")
      ("Simd.X86.hadd4", "Pairs added: a0+a1, a2+a3, b0+b1, b2+b3 (SSE3's haddps).")
      ("Simd.X86.hadd8", "Pairs added within each 128-bit half (AVX's vhaddps).")
      ("Simd.X86.movemask4", "The lanes' sign bits as the low bits of an i32 (SSE's movmskps).")
      ("Simd.X86.movemask8", "The lanes' sign bits as the low bits of an i32 (AVX's vmovmskps).")
      ("Simd.X86.movemaskBytes16", "The bytes' top bits as the low bits of an i32 (SSE2's pmovmskb).")
      ("Simd.X86.movemaskBytes32", "The bytes' top bits as an i32 (AVX2's vpmovmskb).")
      ("Simd.X86.shuffleBytes16", "The bytes of `a` the indices in `b` pick; an index with its top bit set gives 0 (SSSE3's pshufb).")
      ("Simd.X86.shuffleBytes32", "pshufb within each 128-bit half (AVX2's vpshufb).")
      ("Simd.X86.maddPairs8", "The products of the i16 lanes, adjacent pairs added into i32s (SSE2's pmaddwd).")
      ("Simd.X86.maddPairs16", "pmaddwd over 256 bits (AVX2's vpmaddwd).")
      ("Simd.X86.sadBytes16", "The sums of absolute differences of each 8 bytes, as u64s (SSE2's psadbw).")
      ("Simd.X86.sadBytes32", "psadbw over 256 bits (AVX2's vpsadbw).")
      ("Simd.Arm.rsqrtEstimate4", "An estimate of 1 / sqrt x per lane, to 8 bits (NEON's frsqrte).")
      ("Simd.Arm.recipEstimate4", "An estimate of 1 / x per lane, to 8 bits (NEON's frecpe).")
      ("Simd.Arm.pairwiseAdd4", "Pairs added: a0+a1, a2+a3, b0+b1, b2+b3 (NEON's faddp).")
      ("Simd.Arm.tableLookup16", "The bytes of `a` the indices in `b` pick; an index past 15 gives 0 (NEON's tbl).")
      ("Simd.Arm.dotBytes16", "`acc` plus, per i32 lane, the dot product of 4 i8s of `a` and of `b` (the dotprod extension's sdot).") ]
  List.concat [ List.collect one vectors; List.collect mask Types.Ty.maskTypes; targets ]

/// The docs of the functions built into the compiler, in order (the editor's hover and zs doc
/// read them by name).
let builtinDocs : list<string * string> = List.append plainDocs simdDocs

/// A documented item of a source file: its kind (module or namespace for a file's header,
/// function, type, case, trait, method, effect, operation, derive, impl, member), what hovers
/// refer to it by (List.map, option, Some, Show.show, string#Length), the declaration as written
/// without its body, its line, and its doc comment.
type DocItem = { kind: string; key: string; title: string; line: int; doc: option<string> }

/// The doc comment above a line (from 1) of the lines: its `///` lines, attributes between them
/// skipped.
let docAbove (lines: array<string>) (line: int) : option<string> =
  let found = ref []
  let mutable i = line - 2
  let marked (l: string) =
    let t = String.trimStart l
    String.startsWith "///" t || String.startsWith "[<" t
  while i >= 0 && i < Array.length lines && marked lines.[i] do
    let t = String.trimStart lines.[i]
    if String.startsWith "///" t then
      let text = String.sub t 3 (String.length t - 3)
      found.Value <- (if String.startsWith " " text then String.sub text 1 (String.length text - 1) else text) :: found.Value
    i <- i - 1
  if List.isEmpty found.Value then None else Some(String.join "\n" found.Value)

// ---- reading declarations off a line: each reader takes the line and where to start, and gives
// where it stopped, or -1

let private isSpaceByte (b: u8) = b = u8 32 || b = u8 9 || b = u8 13 || b = u8 10

let private isIdentStart (b: u8) = (b >= u8 97 && b <= u8 122) || (b >= u8 65 && b <= u8 90) || b = u8 95

let private isIdentByte (b: u8) = isIdentStart b || (b >= u8 48 && b <= u8 57)

// one or more spaces
let private spaces1 (l: string) (i: int) : int =
  let mutable j = i
  while j < String.length l && isSpaceByte (String.byte l j) do
    j <- j + 1
  if j > i then j else -1

let private spaces0 (l: string) (i: int) : int =
  let j = spaces1 l i
  if j < 0 then i else j

// the word, then one or more spaces
let private word (w: string) (l: string) (i: int) : int =
  if i >= 0 && String.length l - i >= String.length w && String.sub l i (String.length w) = w then spaces1 l (i + String.length w) else -1

// the word with no spaces needed after it, but not inside a longer name
let private keyword (w: string) (l: string) (i: int) : int =
  let n = i + String.length w
  if i >= 0 && String.length l >= n && String.sub l i (String.length w) = w && (n = String.length l || not (isIdentByte (String.byte l n))) then n else -1

// [A-Za-z_][A-Za-z0-9_]* (dots too, with dots)
let private ident (dots: bool) (l: string) (i: int) : int =
  if i >= 0 && i < String.length l && isIdentStart (String.byte l i) then
    let mutable j = i + 1
    while j < String.length l && (isIdentByte (String.byte l j) || (dots && String.byte l j = u8 46)) do
      j <- j + 1
    j
  else
    -1

// an optional `w ` (the word and spaces): where after it, or i
let private optional (w: string) (l: string) (i: int) : int =
  let j = word w l i
  if j < 0 then i else j

// ``a name``, (|Active|Pattern|), (>>=), or a name (dots too, with dots)
let private letName (dots: bool) (l: string) (i: int) : int =
  let n = String.length l
  if i < 0 || i >= n then
    -1
  else if String.startsWith "``" (String.sub l i (n - i)) then
    match String.indexOfFrom l "``" (i + 2) with
    | k when k > i + 2 -> k + 2
    | _ -> -1
  else if dots && String.startsWith "(|" (String.sub l i (n - i)) then
    match String.indexOfFrom l ")" (i + 2) with
    | k when k > i + 2 && String.byte l (k - 1) = u8 124 -> k + 1
    | _ -> -1
  else if dots && String.byte l i = u8 40 then
    let mutable j = i + 1
    while j < n && String.contains (String.ofByte (String.byte l j)) "!%&*+-./<=>?@^|~$" do
      j <- j + 1
    if j > i + 1 && j < n && String.byte l j = u8 41 then j + 1 else -1
  else
    ident dots l i

// the declaration without its body: up to the first `=` with a space before it and a space or the
// end after it (not ==, <=, >=, <>)
let private header (l: string) : string =
  let t = String.trim l
  let n = String.length t
  let mutable cut = -1
  for i in 1 .. n - 1 do
    if cut < 0 && String.byte t i = u8 61 && isSpaceByte (String.byte t (i - 1)) && (i + 1 = n || isSpaceByte (String.byte t (i + 1))) then
      cut <- i - 1
  if cut < 0 then t else String.trim (String.sub t 0 cut)

let private trimChars (cs: string) (s: string) : string =
  let mutable a = 0
  let mutable b = String.length s
  while a < b && String.contains (String.ofByte (String.byte s a)) cs do
    a <- a + 1
  while b > a && String.contains (String.ofByte (String.byte s (b - 1))) cs do
    b <- b - 1
  String.sub s a (b - a)

/// The declarations of a file's text with their doc comments: top-level `let`, `type`, `trait`,
/// `effect`, `derive`, `impl`, a `module` block's functions, and union cases, trait methods,
/// effect operations and members under them.
let docItems (text: string) : list<DocItem> =
  let lines = Array.ofList (String.split "\n" (String.replace text "\r\n" "\n"))
  let items = Buffer.empty
  // the file's module or namespace, as names inside start: "Collections.List."
  let mutable prefix = ""
  // the type, extension, trait or module whose block we are in, and which it is
  let mutable container = ""
  let mutable containerKind = ""
  for i in 0 .. Array.length lines - 1 do
    let l = lines.[i]
    let add (kind: string) (key: string) = Buffer.push { kind = kind; key = key; title = header l; line = i + 1; doc = docAbove lines (i + 1) } items
    if String.length l > 0 && not (isSpaceByte (String.byte l 0)) && not (String.startsWith "//" l) && not (String.startsWith "[<" l) then
      container <- ""
      containerKind <- ""
      // module Collections.List / namespace Collections: what the file's names start with
      let headerWord = if word "module" l 0 >= 0 then "module" else if word "namespace" l 0 >= 0 then "namespace" else ""
      let headerEnd = if headerWord = "" then -1 else ident true l (word headerWord l 0)
      let afterLet = word "let" l 0
      let nameStart = if afterLet < 0 then -1 else optional "private" l (optional "rec" l afterLet)
      let isPrivate = afterLet >= 0 && word "private" l (optional "rec" l afterLet) >= 0
      let nameEnd = letName true l nameStart
      if headerEnd >= 0 && spaces0 l headerEnd = String.length l then
        let name = String.sub l (word headerWord l 0) (headerEnd - word headerWord l 0)
        prefix <- name + "."
        add headerWord name
      else if nameEnd >= 0 then
        // an operator's name is the operator: (>>=) is >>=
        let raw = String.sub l nameStart (nameEnd - nameStart)
        let name = if String.startsWith "(" raw && not (String.startsWith "(|" raw) then trimChars "()" raw else trimChars "`" raw
        if not isPrivate then
          add "function" (prefix + name)
      else
        let afterType = word "type" l 0
        let typeStart = if afterType < 0 then -1 else optional "private" l afterType
        let typeEnd = ident false l typeStart
        if typeEnd >= 0 then
          let name = String.sub l typeStart (typeEnd - typeStart)
          let typePrivate = word "private" l afterType >= 0
          // <...> then `with`: an extension
          let afterParams =
            if typeEnd < String.length l && String.byte l typeEnd = u8 60 then
              match String.indexOfFrom l ">" typeEnd with
              | k when k > typeEnd -> k + 1
              | _ -> typeEnd
            else
              typeEnd
          let isExtension = keyword "with" l (spaces0 l afterParams) >= 0
          // an extension of a built-in type (string, list) keeps the type's own name
          container <- if isExtension && String.byte name 0 >= u8 97 && String.byte name 0 <= u8 122 then name else prefix + name
          if typePrivate then
            containerKind <- "private"
          else if isExtension then
            containerKind <- "extension"
          else
            containerKind <- "type"
            add "type" container
        else
          let traitWord = if word "trait" l 0 >= 0 then "trait" else if word "effect" l 0 >= 0 then "effect" else ""
          let traitEnd = if traitWord = "" then -1 else ident false l (word traitWord l 0)
          if traitEnd >= 0 then
            container <- prefix + String.sub l (word traitWord l 0) (traitEnd - word traitWord l 0)
            containerKind <- traitWord
            add traitWord container
          else
            let deriveEnd = ident false l (word "derive" l 0)
            if deriveEnd >= 0 then
              add "derive" ("derive " + String.sub l (word "derive" l 0) (deriveEnd - word "derive" l 0))
            else
              let afterImpl = word "impl" l 0
              let t = String.trimEnd l
              if afterImpl >= 0 && String.endsWith "=" t then
                add "impl" ("impl " + String.trim (String.sub t afterImpl (String.length t - afterImpl - 1)))
              else
                // module Inner = …: its functions are Inner.name
                let moduleEnd = ident false l (word "module" l 0)
                if moduleEnd >= 0 && String.startsWith "=" (String.sub l (spaces0 l moduleEnd) (String.length l - spaces0 l moduleEnd)) then
                  container <- prefix + String.sub l (word "module" l 0) (moduleEnd - word "module" l 0)
                  containerKind <- "module"
    else if container <> "" then
      let t = String.trim l
      let caseEnd = if String.startsWith "|" t then ident false t (spaces0 t 1) else -1
      let isCase = caseEnd >= 0 && String.byte t (spaces0 t 1) >= u8 65 && String.byte t (spaces0 t 1) <= u8 90
      let afterLet = word "let" t 0
      let fnStart = if afterLet < 0 then -1 else optional "private" t (optional "rec" t afterLet)
      let fnPrivate = afterLet >= 0 && word "private" t (optional "rec" t afterLet) >= 0
      let fnEnd = letName false t fnStart
      if containerKind = "module" then
        // the module's own definitions, at the block's indentation (not local lets)
        if fnEnd >= 0 && not fnPrivate && String.startsWith "  " l && not (isSpaceByte (String.byte l 2)) then
          add "function" (container + "." + trimChars "`" (String.sub t fnStart (fnEnd - fnStart)))
      else if isCase && containerKind = "type" then
        add "case" (prefix + String.sub t (spaces0 t 1) (caseEnd - spaces0 t 1))
      else
        let abstractEnd = ident false t (word "abstract" t 0)
        if abstractEnd >= 0 && containerKind = "trait" then
          add "method" (container + "." + String.sub t (word "abstract" t 0) (abstractEnd - word "abstract" t 0))
        else if abstractEnd >= 0 && containerKind = "effect" then
          add "operation" (container + "." + String.sub t (word "abstract" t 0) (abstractEnd - word "abstract" t 0))
        else
          let memberStart = word "member" t (optional "static" t 0)
          // member x.Name: the name after the self's (a private type's members aren't listed)
          let first = ident false t memberStart
          if first >= 0 && containerKind <> "private" then
            let second = if first < String.length t && String.byte t first = u8 46 then ident false t (first + 1) else -1
            let name = if second >= 0 then String.sub t (first + 1) (second - first - 1) else String.sub t memberStart (first - memberStart)
            add "member" (container + "#" + name)
  Array.toList (Buffer.toArray items)

/// zs doc file.zs: the file's Markdown reference, every documented item, a function with its
/// checked type, then the functions built into the compiler that belong to its module.
let doc (src: string) : int =
  match Check.program src false false None "" with
  | Error(ds, sources) ->
    Check.report sources ds false |> ignore
    1
  | Ok c ->
    let cx = c.cx
    let errors = Array.filter (fun (d: Diagnostic) -> d.severity = Err) (Buffer.toArray cx.diagnostics)
    if Array.length errors > 0 then
      Check.report (List.map (fun (m: Modules.Loaded) -> m.source) c.modules) errors false |> ignore
      1
    else
      let show (t: Types.Ty.Ty) = Infer.Cx.show cx t
      let signature (h: Infer.Cx.Hover) =
        let needs = if h.constraints = "" then "" else " when " + h.constraints
        let words = if h.explain = "" then "" else "\n  " + h.explain
        (h.name, $"{Types.Ty.shortName h.name} : {show h.ty}{needs}{words}")
      let declared = List.map signature (List.filter (fun (h: Infer.Cx.Hover) -> h.decl) (Array.toList (Buffer.toArray cx.hovers)))
      let text =
        match File.readAllText src with
        | Ok t -> t
        | Error _ -> ""
      let own = docItems text
      let stem = Path.getFileNameWithoutExtension src
      let fileHeader = List.tryFind (fun (d: DocItem) -> d.kind = "module" || d.kind = "namespace") own
      // the page's module: a namespace file holds the one named after the file
      let moduleName =
        match fileHeader with
        | Some h when h.kind = "namespace" -> Some(h.key + "." + stem)
        | Some h -> Some h.key
        | None -> None
      // functions built into the compiler that belong to this module (the prelude's: the global
      // ones), after the file's own
      let inModule (name: string) =
        match moduleName with
        | Some m -> String.startsWith (m + ".") name && not (String.contains "." (String.sub name (String.length m + 1) (String.length name - String.length m - 1)))
        | None -> stem = "prelude" && not (String.contains "." name)
      let builtin (p: string * string) : option<DocItem * string> =
        let (name, d) = p
        match Infer.Builtins.builtinType name with
        | Some t when inModule name ->
          let words =
            match Types.Show.explain cx.v [] t with
            | "" -> ""
            | w -> "\n  " + w
          Some({ kind = "function"; key = name; title = ""; line = 0; doc = Some d }, $"{Types.Ty.shortName name} : {show t}{words}")
        | _ -> None
      let builtins = List.choose builtin builtinDocs
      let keyed (p: DocItem * string) =
        let (d, s) = p
        (d.key, s)
      let signatures = Map.ofList (List.append declared (List.map keyed builtins))
      let items = List.append own (List.sortBy (fun (d: DocItem) -> d.key) (List.map fst builtins))
      let section (title: string) (kinds: list<string>) =
        let chosen = List.filter (fun (d: DocItem) -> List.contains d.kind kinds) items
        if not (List.isEmpty chosen) then
          println $"## {title}\n"
          for d in chosen do
            let shown =
              match Map.tryFind d.key signatures with
              | Some s when d.kind = "function" -> s
              | _ -> d.title
            let heading = if List.contains d.kind [ "case"; "method"; "member"; "operation" ] then "####" else "###"
            println $"{heading} `{Types.Ty.shortName d.key}`\n\n```zsharp\n{shown}\n```\n"
            match d.doc with
            | Some text -> println $"{text}\n"
            | None -> println "_Undocumented._\n"
      // the page is the file's module, with the doc comment above its header
      println $"# {Option.defaultValue stem moduleName}\n"
      match Option.bind (fun (h: DocItem) -> h.doc) fileHeader with
      | Some text -> println $"{text}\n"
      | None -> ()
      section "Traits" [ "trait"; "method" ]
      section "Effects" [ "effect"; "operation" ]
      section "Types" [ "type"; "case"; "member" ]
      section "Derives and impls" [ "derive"; "impl" ]
      section "Functions" [ "function" ]
      0
