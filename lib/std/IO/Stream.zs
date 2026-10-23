/// Readers and writers: a file, a pipe or a standard stream read or written through a buffer,
/// as bytes or as text. They block, as reading a file does; a task that must not stall its loop
/// reads on `Task.blocking`'s thread. `use` closes one (a writer is flushed first).
namespace IO

/// A stream being read (`File.openRead`, `Console.openStandardInput`, a process's piped output).
type Reader =
  { /// The file descriptor.
    fd: int
    /// What has been read from the stream: bytes `start` to `filled` aren't taken yet.
    buffer: Buffer<u8>
    /// The first byte not taken.
    start: ref<int>
    /// The end of what's been read.
    filled: ref<int> }

/// A stream being written (`File.openWrite`, `Console.openStandardOutput`, a process's piped
/// input): bytes collect in `buffer` until it's full or flushed.
type Writer =
  { /// The file descriptor.
    fd: int
    /// The bytes written and not flushed yet: `used` of them.
    buffer: Buffer<u8>
    /// How many of `buffer`'s bytes are waiting.
    used: ref<int> }

/// Functions on `Reader`.
module Reader =
  /// A reader of an open file descriptor (it closes it when it's disposed).
  let ofFd (fd: int) : Reader =
    { fd = fd; buffer = Buffer.create 65536 (u8 0); start = ref 0; filled = ref 0 }

  // reads more into the buffer, the bytes not taken moved to its front first: how many came
  // (0 at the end)
  let private fill (r: Reader) : result<int, string> =
    let keep = r.filled.Value - r.start.Value
    Buffer.blit r.buffer r.start.Value r.buffer 0 keep
    r.start.Value <- 0
    r.filled.Value <- keep
    let n = Native.fdRead r.fd r.buffer keep (Buffer.length r.buffer - keep)
    if n < 0 then
      Error (Native.errorText n)
    else
      r.filled.Value <- keep + n
      Ok n

  // bytes i to j - 1 of the buffer as a string
  let private text (r: Reader) (i: int) (j: int) = String.ofBytes r.buffer.[i .. j - 1]

  /// The next line, without its line ending (`\n` or `\r\n`); `None` at the end. A last line
  /// without a newline is a line.
  let rec readLine (r: Reader) : result<option<string>, string> =
    let rec scan (acc: string) =
      let mutable i = r.start.Value
      while i < r.filled.Value && r.buffer.[i] <> u8 10 do
        i <- i + 1
      if i < r.filled.Value then
        let line = acc + text r r.start.Value i
        r.start.Value <- i + 1
        Ok (Some (if String.endsWith "\r" line then
            String.sub line 0 (String.length line - 1)
          else
            line))
      else
        // no newline yet: take what's there and read on
        let acc = acc + text r r.start.Value r.filled.Value
        r.start.Value <- r.filled.Value
        match fill r with
        | Error e -> Error e
        | Ok 0 -> Ok (if String.isEmpty acc then None else Some acc)
        | Ok _ -> scan acc
    scan ""

  /// Reads into `buf`, up to its length: how many bytes came, 0 at the end.
  let readBytes (r: Reader) (buf: Buffer<u8>) : result<int, string> =
    if r.start.Value = r.filled.Value then
      Native.fdRead r.fd buf 0 (Buffer.length buf)
      |> fun n -> if n < 0 then Error (Native.errorText n) else Ok n
    else
      let n = min (Buffer.length buf) (r.filled.Value - r.start.Value)
      Buffer.blit r.buffer r.start.Value buf 0 n
      r.start.Value <- r.start.Value + n
      Ok n

  /// Reads exactly `n` bytes into the start of `buf` (an LSP message's `Content-Length`); an
  /// `Error` when the stream ends first.
  let readExactly (r: Reader) (buf: Buffer<u8>) (n: int) : result<unit, string> =
    let rec go (got: int) =
      if got = n then
        Ok ()
      else
        let k = (readBytes r buf.[got .. n - 1])?
        if k = 0 then Error $"the stream ended after {got} of {n} bytes" else go (got + k)
    go 0

  /// What's left of the stream, as text.
  let readToEnd (r: Reader) : result<string, string> =
    let rec go (acc: string) =
      let acc = acc + text r r.start.Value r.filled.Value
      r.start.Value <- r.filled.Value
      match fill r with
      | Error e -> Error e
      | Ok 0 -> Ok acc
      | Ok _ -> go acc
    go ""

/// Functions on `Writer`.
module Writer =
  /// A writer of an open file descriptor (it closes it when it's disposed).
  let ofFd (fd: int) : Writer = { fd = fd; buffer = Buffer.create 65536 (u8 0); used = ref 0 }

  // writes bytes i to j - 1 of buf to the stream, all of them
  let rec private put (fd: int) (buf: Buffer<u8>) (i: int) (j: int) : result<unit, string> =
    if i = j then
      Ok ()
    else
      let n = Native.fdWrite fd buf i (j - i)
      if n < 0 then Error (Native.errorText n) else put fd buf (i + n) j

  /// Writes what's waiting to the stream.
  let flush (w: Writer) : result<unit, string> =
    let n = w.used.Value
    w.used.Value <- 0
    put w.fd w.buffer 0 n

  /// Writes the bytes (an array, a Buffer, a slice or `String.bytes s`).
  let write (w: Writer) (bytes: span<u8>) : result<unit, string> =
    let n = Span.length bytes
    let room = if w.used.Value + n > Buffer.length w.buffer then flush w else Ok ()
    room?
    if n >= Buffer.length w.buffer then
      // too big to wait: straight to the stream
      put w.fd (Buffer.ofSpan bytes) 0 n
    else
      Buffer.blit bytes 0 w.buffer w.used.Value n
      w.used.Value <- w.used.Value + n
      Ok ()

  /// Writes the text's bytes.
  let writeText (w: Writer) (s: string) = write w (String.bytes s)

/// `use` closes the stream.
impl Dispose<Reader> =
  let dispose (r: Reader) = Native.fdClose r.fd

/// `use` flushes what's waiting, then closes the stream.
impl Dispose<Writer> =
  let dispose (w: Writer) =
    Writer.flush w |> ignore
    Native.fdClose w.fd
