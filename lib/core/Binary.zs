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
    strings: Buffer<string> }

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

  /// A signed number: zigzag (0, -1, 1, -2, … as 0, 1, 2, 3, …), then as `uvarint`.
  let varint (w: BinaryWriter) (n: int) = uvarint w (u64 ((n <<< 1) ^^^ (n >>> 63)))

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

  /// A signed number as `BinaryWriter.varint` writes it.
  let varint (r: BinaryReader) : result<int, string> =
    let n = (uvarint r)?
    Ok(int (n >>> 1) ^^^ -(int (n &&& u64 1)))

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
    let n = (uvarint r)?
    let n = int n
    if n > 0 then
      if n <= Buffer.length r.strings then
        Ok r.strings.[n - 1]
      else
        Error $"string {n} isn't written yet"
    else
      let len = (uvarint r)?
      let len = int len
      let i = r.pos.Value
      if i + len > Span.length r.bytes then
        Error $"the bytes end in a string at {i}"
      else
        r.pos.Value <- i + len
        let s = String.ofBytes r.bytes.[i .. i + len - 1]
        Buffer.push s r.strings
        Ok s

/// `toBytes` and `ofBytes`.
module Binary =
  /// The value's bytes.
  let toBytes (x: 'a) : array<u8> =
    let w = BinaryWriter.create ()
    write w x
    Buffer.toArray w.bytes

  /// The value the bytes hold; an `Error` when they don't hold one, or hold more than one.
  let ofBytes (bytes: span<u8>) : result<'a, string> =
    let r = BinaryReader.create bytes
    let x = (read r)?
    if r.pos.Value = Span.length bytes then
      Ok x
    else
      Error $"{Span.length bytes - r.pos.Value} bytes after the value"

/// As a zigzag varint (BinaryWriter.varint).
impl Binary<int> =
  let write w (x: int) = BinaryWriter.varint w x
  let read r = BinaryReader.varint r

/// As a zigzag varint.
impl Binary<i8> =
  let write w (x: i8) = BinaryWriter.varint w (int x)
  let read r = Result.map i8 (BinaryReader.varint r)

/// As a zigzag varint.
impl Binary<i16> =
  let write w (x: i16) = BinaryWriter.varint w (int x)
  let read r = Result.map i16 (BinaryReader.varint r)

/// As a zigzag varint.
impl Binary<i32> =
  let write w (x: i32) = BinaryWriter.varint w (int x)
  let read r = Result.map i32 (BinaryReader.varint r)

/// As a zigzag varint.
impl Binary<i64> =
  let write w (x: i64) = BinaryWriter.varint w (int x)
  let read r = Result.map i64 (BinaryReader.varint r)

/// As one byte.
impl Binary<u8> =
  let write w (x: u8) = BinaryWriter.byte w x
  let read r = BinaryReader.byte r

/// As a varint (BinaryWriter.uvarint).
impl Binary<u16> =
  let write w (x: u16) = BinaryWriter.uvarint w (u64 x)
  let read r = Result.map u16 (BinaryReader.uvarint r)

/// As a varint.
impl Binary<u32> =
  let write w (x: u32) = BinaryWriter.uvarint w (u64 x)
  let read r = Result.map u32 (BinaryReader.uvarint r)

/// As a varint.
impl Binary<u64> =
  let write w (x: u64) = BinaryWriter.uvarint w x
  let read r = BinaryReader.uvarint r

/// As a varint.
impl Binary<usize> =
  let write w (x: usize) = BinaryWriter.uvarint w (u64 x)
  let read r = Result.map usize (BinaryReader.uvarint r)

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

/// Its length, then its elements.
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
        let x = (read r)?
        go (i + 1) (x :: acc)
    go 0 []

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
    match Shape.kind with
    | RecordKind -> Shape.build (fun f -> read r)
    | UnionKind ->
      let name = (BinaryReader.string r)?
      match Shape.buildCase name (fun f -> read r) with
      | Some built -> built
      | None -> Error $"unknown case {name}"
