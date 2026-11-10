/// Values as bytes and back (0020): for a cache, or messages between processes. A record or a
/// union has `Binary` with `[<Derive(Binary)>]`; numbers, `bool`, `char`, `string`, `unit`,
/// lists, arrays, options, results, tuples, `Map`, `Set` and `HashMap` have it.
/// `Binary.toBytes x` writes a value, and `Binary.ofBytes bytes` reads one back.

/// Where values are written: bytes collect in a Buffer, and a string written again is the
/// number of its first time.
type BinaryWriter =
  { /// The bytes so far.
    bytes: Buffer<u8>
    /// The strings written so far, with their numbers.
    strings: ref<HashMap<string, int>> }

/// Where values are read from.
type BinaryReader =
  { bytes: span<u8>
    /// The next byte's index.
    pos: ref<int>
    /// The strings read so far, by their numbers.
    strings: Buffer<string>
    /// How many records and unions the read is inside of.
    nesting: ref<int> = ref 0
    /// How many may nest, a derived read's `Error` past them; -1, as `create` makes it, for no
    /// limit (`Binary.ofBytes` sets one).
    maxNesting: int = -1 }

/// A value that can be written as bytes and read back.
trait Binary<'a> =
  /// Writes the value.
  abstract write : BinaryWriter -> 'a -> unit
  /// Reads a value, or says why the bytes aren't one.
  abstract read : BinaryReader -> result<'a, string>

/// The forms values are made of: bytes, variable-length integers, floats and strings.
module BinaryWriter =
  /// A writer with nothing written.
  let create () : BinaryWriter = { bytes = Buffer.empty; strings = ref HashMap.empty }

  /// One byte.
  let byte (w: BinaryWriter) (b: u8) = Buffer.push b w.bytes

  /// An unsigned number in 7-bit groups, low first, the high bit set on all but the last.
  let rec uvarint (w: BinaryWriter) (n: u64) =
    if n < u64 128 then
      byte w (u8 n)
    else
      byte w (u8 ((n &&& u64 127) ||| u64 128))
      uvarint w (n >>> 7)

  /// A signed 64-bit number: zigzag (0, -1, 1, -2, … as 0, 1, 2, 3, …), then as `uvarint`.
  let varint64 (w: BinaryWriter) (n: i64) = uvarint w (u64 ((n <<< 1) ^^^ (n >>> 63)))

  /// A signed number, as `varint64`: the same bytes whether `int` is 32 or 64 bits.
  let varint (w: BinaryWriter) (n: int) = varint64 w (i64 n)

  /// A float's 64 bits, low byte first.
  let float (w: BinaryWriter) (x: f64) =
    let bits = Float.toBits x
    for i in 0 .. 7 do
      byte w (u8 ((bits >>> u64 (8 * i)) &&& u64 255))

  /// A string: 0, its length and its bytes the first time; then the number it had, plus 1.
  let string (w: BinaryWriter) (s: string) =
    match HashMap.tryFind s w.strings.Value with
    | Some i -> uvarint w (u64 (i + 1))
    | None ->
      uvarint w (u64 0)
      uvarint w (u64 (String.length s))
      for b in String.bytes s do
        byte w b
      w.strings.Value <- HashMap.add s (HashMap.count w.strings.Value) w.strings.Value

/// Reading what `BinaryWriter` wrote; each says when the bytes end too early.
module BinaryReader =
  /// A reader of the bytes from the start.
  let create (bytes: span<u8>) : BinaryReader =
    { bytes = bytes; pos = ref 0; strings = Buffer.empty }

  /// One byte.
  let byte (r: BinaryReader) : result<u8, string> =
    let i = r.pos.Value
    if i < Span.length r.bytes then
      r.pos.Value <- i + 1
      Ok r.bytes.[i]
    else
      Error $"the bytes end at {i}"

  /// An unsigned number as `BinaryWriter.uvarint` writes it.
  let uvarint (r: BinaryReader) : result<u64, string> =
    let rec go (acc: u64) (shift: int) =
      if shift > 63 then
        Error "a number is longer than 64 bits"
      else
        let b = (byte r)?
        let acc = acc ||| ((u64 b &&& u64 127) <<< u64 shift)
        if b < u8 128 then Ok acc else go acc (shift + 7)
    go (u64 0) 0

  /// A signed 64-bit number as `BinaryWriter.varint64` writes it.
  let varint64 (r: BinaryReader) : result<i64, string> =
    let n = (uvarint r)?
    Ok(i64 (n >>> 1) ^^^ -(i64 (n &&& u64 1)))

  /// A signed number as `BinaryWriter.varint` writes it; an `Error` for one that doesn't fit an
  /// `int` (a 64-bit machine's, read where `int` is 32 bits).
  let varint (r: BinaryReader) : result<int, string> =
    let n = (varint64 r)?
    if i64 (int n) = n then Ok(int n) else Error $"{n} doesn't fit an int"

  /// A float as `BinaryWriter.float` writes it.
  let float (r: BinaryReader) : result<f64, string> =
    let rec go (acc: u64) (i: int) =
      if i = 8 then
        Ok(Float.ofBits acc)
      else
        let b = (byte r)?
        go (acc ||| (u64 b <<< u64 (8 * i))) (i + 1)
    go (u64 0) 0

  /// A string as `BinaryWriter.string` writes it.
  let string (r: BinaryReader) : result<string, string> =
    // the numbers compared as read, u64s: one past int's range would wrap, converted first
    let n = (uvarint r)?
    if n > u64 0 then
      if n <= u64 (Buffer.length r.strings) then
        Ok r.strings.[int n - 1]
      else
        Error $"string {n} isn't written yet"
    else
      let len = (uvarint r)?
      let i = r.pos.Value
      if len > u64 (Span.length r.bytes - i) then
        Error $"the bytes end in a string at {i}"
      else
        let len = int len
        r.pos.Value <- i + len
        let s = String.ofBytes r.bytes.[i .. i + len - 1]
        Buffer.push s r.strings
        Ok s

/// `toBytes` and `ofBytes`.
module Binary =
  /// How `ofBytesWith` reads: records and unions nest at most `depth` levels (a tree as deep as
  /// its longest branch), an `Error` past them.
  type Options = { depth: int = 1000 }

  /// The value's bytes.
  let toBytes (x: 'a) : array<u8> =
    let w = BinaryWriter.create ()
    write w x
    Buffer.toArray w.bytes

  /// The value the bytes hold, its records and unions nested at most `options.depth` levels; an
  /// `Error` when they don't hold one, or hold more than one.
  let ofBytesWith (options: Options) (bytes: span<u8>) : result<'a, string> =
    let r0 = BinaryReader.create bytes
    let r = { r0 with maxNesting = max 0 options.depth }
    let x = (read r)?
    if r.pos.Value = Span.length bytes then
      Ok x
    else
      Error $"{Span.length bytes - r.pos.Value} bytes after the value"

  /// The value the bytes hold; an `Error` when they don't hold one, or hold more than one.
  /// Records and unions nest at most 1,000 levels, 32 where `int` is 32 bits (a microcontroller's
  /// stack can be 4 KB, and a level is a call); `ofBytesWith` sets another limit.
  let ofBytes (bytes: span<u8>) : result<'a, string> =
    ofBytesWith { depth = (if sizeof<int> = 4 then 32 else 1000) } bytes

/// As a zigzag varint (BinaryWriter.varint).
impl Binary<int> =
  let write w (x: int) = BinaryWriter.varint w x
  let read r = BinaryReader.varint r

/// As a zigzag varint.
impl Binary<i8> =
  let write w (x: i8) = BinaryWriter.varint w (int x)
  let read r =
    let n = (BinaryReader.varint r)?
    if int (i8 n) = n then Ok(i8 n) else Error $"{n} doesn't fit an i8"

/// As a zigzag varint.
impl Binary<i16> =
  let write w (x: i16) = BinaryWriter.varint w (int x)
  let read r =
    let n = (BinaryReader.varint r)?
    if int (i16 n) = n then Ok(i16 n) else Error $"{n} doesn't fit an i16"

/// As a zigzag varint.
impl Binary<i32> =
  let write w (x: i32) = BinaryWriter.varint w (int x)
  let read r =
    let n = (BinaryReader.varint r)?
    if int (i32 n) = n then Ok(i32 n) else Error $"{n} doesn't fit an i32"

/// As a zigzag varint (BinaryWriter.varint64).
impl Binary<i64> =
  let write w (x: i64) = BinaryWriter.varint64 w x
  let read r = BinaryReader.varint64 r

/// As one byte.
impl Binary<u8> =
  let write w (x: u8) = BinaryWriter.byte w x
  let read r = BinaryReader.byte r

/// As a varint (BinaryWriter.uvarint).
impl Binary<u16> =
  let write w (x: u16) = BinaryWriter.uvarint w (u64 x)
  let read r =
    let n = (BinaryReader.uvarint r)?
    if u64 (u16 n) = n then Ok(u16 n) else Error $"{n} doesn't fit a u16"

/// As a varint.
impl Binary<u32> =
  let write w (x: u32) = BinaryWriter.uvarint w (u64 x)
  let read r =
    let n = (BinaryReader.uvarint r)?
    if u64 (u32 n) = n then Ok(u32 n) else Error $"{n} doesn't fit a u32"

/// As a varint.
impl Binary<u64> =
  let write w (x: u64) = BinaryWriter.uvarint w x
  let read r = BinaryReader.uvarint r

/// As a varint.
impl Binary<usize> =
  let write w (x: usize) = BinaryWriter.uvarint w (u64 x)
  let read r =
    let n = (BinaryReader.uvarint r)?
    if u64 (usize n) = n then Ok(usize n) else Error $"{n} doesn't fit a usize"

/// Its 64 bits, low byte first.
impl Binary<f64> =
  let write w (x: f64) = BinaryWriter.float w x
  let read r = BinaryReader.float r

/// As an f64 (which holds every f32 exactly).
impl Binary<f32> =
  let write w (x: f32) = BinaryWriter.float w (f64 x)
  let read r = Result.map f32 (BinaryReader.float r)

/// As one byte, 0 or 1.
impl Binary<bool> =
  let write w (x: bool) = BinaryWriter.byte w (if x then u8 1 else u8 0)
  let read r = Result.map (fun b -> b <> u8 0) (BinaryReader.byte r)

/// Its code point, as a varint.
impl Binary<char> =
  let write w (x: char) = BinaryWriter.varint w (int x)
  let read r = Result.map char (BinaryReader.varint r)

/// Its length and bytes the first time, its number after.
impl Binary<string> =
  let write w (x: string) = BinaryWriter.string w x
  let read r = BinaryReader.string r

/// Nothing.
impl Binary<unit> =
  let write _ () = ()
  let read _ = Ok ()

/// Its length, then its elements. A length the bytes left can't hold is an `Error` (elements
/// that take no bytes, `unit`'s, at most 65,536 of them).
impl Binary<list<'a>> =
  let write w xs =
    BinaryWriter.varint w (List.length xs)
    for x in xs do
      write w x
  let read r =
    let n = (BinaryReader.varint r)?
    let rec go (i: int) acc =
      if i = n then
        Ok(List.rev acc)
      else
        let at = r.pos.Value
        let x = (read r)?
        // an element that took a byte means each after it takes one: a length from elsewhere
        // makes no list longer than the bytes (nor one of nothing longer than the cap)
        let left = Span.length r.bytes - r.pos.Value
        if (r.pos.Value > at && n - i - 1 > left) || (r.pos.Value = at && n > 65536) then
          Error $"a list of {n} elements, with {left} bytes left"
        else
          go (i + 1) (x :: acc)
    if n < 0 then Error $"a list of {n} elements" else go 0 []

/// Its length, then its elements.
impl Binary<array<'a>> =
  let write w (a: array<'a>) =
    BinaryWriter.varint w (Array.length a)
    for x in a do
      write w x
  let read r = Result.map Array.ofList (read r)

/// 0 for None, 1 and the value for Some.
impl Binary<option<'a>> =
  let write w o =
    match o with
    | None -> BinaryWriter.byte w (u8 0)
    | Some x ->
      BinaryWriter.byte w (u8 1)
      write w x
  let read r =
    let tag = (BinaryReader.byte r)?
    if tag = u8 0 then Ok None else Result.map Some (read r)

/// 0 and the value for Ok, 1 and the error for Error.
impl Binary<result<'a, 'e>> =
  let write w x =
    match x with
    | Ok v ->
      BinaryWriter.byte w (u8 0)
      write w v
    | Error e ->
      BinaryWriter.byte w (u8 1)
      write w e
  let read r =
    let tag = (BinaryReader.byte r)?
    if tag = u8 0 then Result.map Ok (read r) else Result.map Error (read r)

/// Its elements in order.
impl Binary<'a * 'b> =
  let write w (a, b) =
    write w a
    write w b
  let read r =
    let a = (read r)?
    let b = (read r)?
    Ok(a, b)

/// Its elements in order.
impl Binary<'a * 'b * 'c> =
  let write w (a, b, c) =
    write w a
    write w b
    write w c
  let read r =
    let a = (read r)?
    let b = (read r)?
    let c = (read r)?
    Ok(a, b, c)

/// Its elements in order.
impl Binary<'a * 'b * 'c * 'd> =
  let write w (a, b, c, d) =
    write w a
    write w b
    write w c
    write w d
  let read r =
    let a = (read r)?
    let b = (read r)?
    let c = (read r)?
    let d = (read r)?
    Ok(a, b, c, d)

/// Its entries, as a list of pairs in key order.
impl Binary<Map<'k, 'v>> =
  let write w m = write w (Map.toList m)
  let read r = Result.map Map.ofList (read r)

/// Its elements, as a list in order.
impl Binary<Set<'a>> =
  let write w s = write w (Set.toList s)
  let read r = Result.map Set.ofList (read r)

/// Its entries, as a list of pairs.
impl Binary<HashMap<'k, 'v>> =
  let write w m = write w (HashMap.toList m)
  let read r = Result.map (List.fold (fun m (k, v) -> HashMap.add k v m) HashMap.empty) (read r)

/// A record's fields in order; a union's case (by name, written once) and then its fields.
derive Binary =
  let write (w: BinaryWriter) (x: 'self) =
    match Shape.of x with
    | Record r ->
      for f in r.fields do
        write w f.value
    | Union c ->
      BinaryWriter.string w c.name
      for f in c.fields do
        write w f.value
  let read (r: BinaryReader) : result<'self, string> =
    // a level is a call, and after a recursive type's case is written once a level is a byte:
    // past the reader's limit an Error, not a stack run out
    if r.maxNesting >= 0 && r.nesting.Value >= r.maxNesting then
      Error $"nesting deeper than {r.maxNesting} levels"
    else
      r.nesting.Value <- r.nesting.Value + 1
      let x =
        match Shape.kind with
        | RecordKind -> Shape.build (fun f -> read r)
        | UnionKind ->
          let name = (BinaryReader.string r)?
          match Shape.buildCase name (fun f -> read r) with
          | Some built -> built
          | None -> Error $"unknown case {name}"
      r.nesting.Value <- r.nesting.Value - 1
      x
