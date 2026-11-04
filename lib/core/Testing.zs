/// Tests as values (0009): `test "name" (fun () -> …)` is a `Test`, `testList` groups them, and
/// a top-level value marked `[<Tests>]` is what `zs test` runs, each test in its own process.
module Testing

/// Whether a test runs: as usual; only with the other focused ones while any are (`ftest`); or
/// not, and said so (`ptest`).
type Focus =
  /// Runs as usual.
  | Normal
  /// Runs, and while any test is focused only the focused ones do.
  | Focused
  /// Doesn't run, and is listed as skipped.
  | Pending

/// A test, or a group of them. A test's path is the names down to it: `parser/parses`.
type Test =
  /// One test: its name, its body (a failure panics), its focus and its time limit (ms).
  | Case of name: string * run: (unit -> unit) * focus: Focus * timeout: int
  /// A group: its name, its tests, its focus, and whether they run one at a time.
  | Group of name: string * tests: list<Test> * focus: Focus * sequenced: bool
  /// A benchmark: its name and its body, which `zs bench` times (`zs test` runs it once).
  | Bench of name: string * run: (unit -> unit)
  /// A property (`testProperty`): its name and its run, driven by the test binary's runner
  /// (which records each case for `zs test`, or replays one).
  | Property of name: string * run: (PropertyDriver -> unit)

/// How the test binary's runner drives a property (0010): a random run, each case's seed and
/// size noted and its bytes recorded as drawn (so `zs test` can shrink a case that panics by
/// replaying the binary), or one case replayed from given bytes.
and PropertyDriver =
  { /// The bytes and size of one case to run instead of a random run.
    replay: option<array<u8> * int>
    /// Before each random case: its index, its seed and its size.
    onCase: int -> u64 -> int -> unit
    /// Each block drawn at random.
    onDraw: option<array<u8> -> unit>
    /// Nothing printed for a replayed case (`zs fuzz` runs millions).
    quiet: bool }

/// What a test's body gives back: nothing (a panic fails it), a `result` (an `Error` fails it),
/// or a task (Std's impl runs it on the event loop).
trait Outcome<'r> =
  /// Panics when the outcome is a failure.
  abstract finish : 'r -> unit

/// A body that returns: it passed.
impl Outcome<unit> =
  let finish () = ()

/// An `Error` fails the test, shown.
impl Outcome<result<'a, 'e>> =
  let finish r =
    match r with
    | Ok _ -> ()
    | Error e -> panic $"Error {e}"

let private limit = 60000

let private case name (body: unit -> 'r) focus ms =
  Case(name, (fun () -> finish (body ())), focus, ms)

/// A test: its name and its body (a panic or an `Error` fails it). It may take 60 s.
let test (name: string) (body: unit -> 'r) : Test = case name body Normal limit

/// A test that may take `ms` milliseconds.
let testWithTimeout (ms: int) (name: string) (body: unit -> 'r) : Test = case name body Normal ms

/// A focused test: while any test is focused, only those run (`zs test --fail-on-focused` fails
/// a run that has one).
let ftest (name: string) (body: unit -> 'r) : Test = case name body Focused limit

/// A pending test: not run, and listed as skipped.
let ptest (name: string) (body: unit -> 'r) : Test = case name body Pending limit

/// A group of tests, run at once (each in its own process).
let testList (name: string) (tests: list<Test>) : Test = Group(name, tests, Normal, false)

/// A group of tests run one at a time: tests that share a file or a port.
let testSequenced (name: string) (tests: list<Test>) : Test = Group(name, tests, Normal, true)

/// A focused group.
let ftestList (name: string) (tests: list<Test>) : Test = Group(name, tests, Focused, false)

/// A pending group.
let ptestList (name: string) (tests: list<Test>) : Test = Group(name, tests, Pending, false)

/// A benchmark: `zs bench` warms it up, times enough runs for a median and a confidence
/// interval, and reports a change from the last run beyond the noise; `zs test` runs it once.
let bench (name: string) (body: unit -> 'r) : Test = Bench(name, (fun () -> body () |> ignore))

// how many of the paired rounds one side must win for the sign test to say it's faster: 19 of
// 25 happens by chance under one time in a hundred
let private rounds = 25

let private winsNeeded = 19

/// A test that passes when `fast` is faster than `slow` with statistical confidence: the two
/// run in paired rounds, in alternating order, and `fast` must win 19 of 25 (a sign test at
/// 1%), so a performance claim can't silently regress. Both run once each per round: give each
/// enough work to time.
let testFaster (name: string) (fast: unit -> 'a) (slow: unit -> 'b) : Test =
  let body () =
    let time (f: unit -> unit) : i64 =
      let t0 = Runtime.ticks ()
      f ()
      i64 (Runtime.ticks () - t0)
    let runFast () = fast () |> ignore
    let runSlow () = slow () |> ignore
    // a warm-up round, not counted
    runFast ()
    runSlow ()
    let mutable wins = 0
    let mutable fastTotal = i64 0
    let mutable slowTotal = i64 0
    for i in 1 .. rounds do
      let (tf, ts) =
        if i % 2 = 0 then
          let tf = time runFast
          (tf, time runSlow)
        else
          let ts = time runSlow
          (time runFast, ts)
      fastTotal <- fastTotal + tf
      slowTotal <- slowTotal + ts
      if tf < ts then
        wins <- wins + 1
    if wins < winsNeeded then
      panic $"not faster with confidence: faster in {wins} of {rounds} rounds (19 needed); mean {fastTotal / i64 rounds} against {slowTotal / i64 rounds} ticks"
  Case(name, body, Normal, limit)

// the expected text as a literal on lines of its own writes it: without the line break after
// the opening quotes, the indentation its lines share, and the line the closing quotes are on
let private normal (s: string) =
  if not (String.startsWith "\n" s) then
    s
  else
    let lines = String.splitLines (String.sub s 1 (String.length s - 1))
    let indent (l: string) = String.length l - String.length (String.trimStart l)
    let shared =
      lines
      |> List.filter (fun l -> String.trim l <> "")
      |> List.map indent
      |> List.fold min 1000000
    let lines =
      lines
      |> List.map (fun l ->
        if String.length l >= shared then String.sub l shared (String.length l - shared) else "")
    let lines =
      if not lines.IsEmpty && String.trim (List.last lines) = "" then
        List.take (List.length lines - 1) lines
      else
        lines
    String.join "\n" lines

/// Compares the value's text (through Show) with the literal next to it, which
/// `zs test --update` rewrites when they differ (an expect test, 0009). The compiler gives it
/// its place: `expect` is `expectAt` with the file and line.
let expectAt (value: 'a) (expected: string) (file: string) (line: int) : unit =
  let actual = show value
  let want = normal expected
  if actual <> want then
    // what zs test --update needs: the place and the text it should have
    eprintln $"zs-expect {file}:{line}\n{actual}\nzs-expect-end"
    panic $"expect failed at {file}:{line}\n  expected: {want}\n  actual:   {actual}"

/// An expect test: `expect (parse "1 + 2") """Add (Num 1, Num 2)"""`.
let expect (value: 'a) (expected: string) : unit = expectAt value expected "" 0

/// Runs every test in order, in this process: what `zs test --target <chip>` builds into the
/// image (a chip has no processes, 0009 D11). Prints `test path` before each, `ok   path` after,
/// `skip path` for a pending one (or one left out while others are focused), and the counts; a
/// failure's panic ends the run after `test path`, which names it.
let runAll (tests: list<Test>) : int =
  let rec leaves (prefix: string) (focus: Focus) (t: Test) : list<string * (unit -> unit) * Focus> =
    match t with
    | Case(name, run, f, _) -> [ (prefix + name, run, (if focus = Normal then f else focus)) ]
    // a benchmark runs once here, as a test of its body
    | Bench(name, run) -> [ (prefix + name, run, focus) ]
    // a property runs at random, nothing recorded (a chip has no files)
    | Property(name, run) ->
      [ (prefix + name,
          (fun () -> run { replay = None; onCase = (fun _ _ _ -> ()); onDraw = None; quiet = false }),
          focus) ]
    | Group(name, ts, f, _) ->
      List.collect (leaves (prefix + name + "/") (if focus = Normal then f else focus)) ts
  let all = List.collect (leaves "" Normal) tests
  let focused = List.exists (fun (_, _, f) -> f = Focused) all
  let mutable passed = 0
  let mutable skipped = 0
  for (path, run, f) in all do
    if f = Pending || (focused && f <> Focused) then
      skipped <- skipped + 1
      println $"skip {path}{(if f = Pending then " (pending)" else "")}"
    else
      println $"test {path}"
      run ()
      passed <- passed + 1
      println $"ok   {path}"
  println $"{passed} passed, {skipped} skipped"
  0

// ---- properties (0010): generators over a stream of bytes, Arbitrary, testProperty

/// Where a generator's bytes come from (0010): a random stream from a seed, recorded as it's
/// drawn, so a failing case can be shrunk and replayed, or a stream given (a shrink candidate).
/// Drawing past a given stream's end is an overrun, which discards the case. All-zero bytes mean
/// the simplest value, and a shorter or smaller stream a simpler one.
type Source =
  { bytes: Buffer<u8>
    pos: ref<int>
    random: option<Numerics.Random>
    overrun: ref<bool>
    discarded: ref<bool>
    /// The case's labels (`Prop.label`, `Prop.classify`), reported with the result.
    labels: Buffer<string>
    /// Told each block drawn at random (the test binary records them, so `zs test` can shrink
    /// a case that panics).
    onDraw: option<array<u8> -> unit>
    /// How large the values may get: a property's cases grow from 0 to its `maxSize`.
    size: int }

/// Functions on `Source`.
module Source =
  /// A random stream from `r`, recording what's drawn, at `size`; `onDraw` is told each block.
  let randomWith (r: Numerics.Random) (size: int) (onDraw: option<array<u8> -> unit>) : Source =
    { bytes = Buffer.ofArray [||]
      pos = ref 0
      random = Some r
      overrun = ref false
      discarded = ref false
      labels = Buffer.ofArray [||]
      onDraw = onDraw
      size = size }

  /// A random stream from `r`, recording what's drawn, at `size`.
  let random (r: Numerics.Random) (size: int) : Source = randomWith r size None

  /// A given stream (a shrink candidate, a saved case), at `size`.
  let ofBytes (bytes: array<u8>) (size: int) : Source =
    { bytes = Buffer.ofArray bytes
      pos = ref 0
      random = None
      overrun = ref false
      discarded = ref false
      labels = Buffer.ofArray [||]
      onDraw = None
      size = size }

  /// `n` bytes from the stream: the next of the given or recorded ones, else drawn at random and
  /// recorded, else (a given stream used up) zeros, and the source has overrun.
  let draw (n: int) (s: Source) : array<u8> =
    let mutable out = Array.create n (u8 0)
    let fresh = Buffer.ofArray [||]
    for i in 0 .. n - 1 do
      let p = s.pos.Value + i
      if p < Buffer.length s.bytes then
        out.[i] <- s.bytes.[p]
      else
        match s.random with
        | Some r ->
          let b = u8 (Numerics.Random.nextInt 0 256 r)
          Buffer.push b s.bytes
          Buffer.push b fresh
          out.[i] <- b
        | None -> s.overrun.Value <- true
    s.pos.Value <- s.pos.Value + n
    match s.onDraw with
    | Some f when Buffer.length fresh > 0 -> f (Buffer.toArray fresh)
    | _ -> ()
    out

  /// Whether the case is to be discarded: a filter that never held, or an overrun.
  let rejected (s: Source) : bool = s.discarded.Value || s.overrun.Value

/// A generator: a function from a source of bytes to a value. Every one shrinks, since shrinking
/// the bytes it reads shrinks what it makes.
type Gen<'a> = Gen of (Source -> 'a)

/// Functions on `Gen`, and the `gen { }` builder.
module Gen =
  /// Runs `g` on a source.
  let draw (Gen f) (s: Source) : 'a = f s

  /// Always `x`; draws nothing.
  let constant (x: 'a) : Gen<'a> = Gen(fun _ -> x)

  /// `f` of what `g` makes.
  let map (f: 'a -> 'b) (g: Gen<'a>) : Gen<'b> = Gen(fun s -> f (draw g s))

  /// `g`, then the generator `f` chooses from its value.
  let bind (f: 'a -> Gen<'b>) (g: Gen<'a>) : Gen<'b> = Gen(fun s -> draw (f (draw g s)) s)

  // an offset from 0 to span (inclusive, unsigned), from the fewest bytes that cover it,
  // big-endian: all zeros is 0. Unsigned, so a span past Int's max (a range across zero on a
  // 32-bit chip, or all of u64) draws without overflowing
  let private offsetU (span: u64) (s: Source) : u64 =
    if span = u64 0 then
      u64 0
    else
      let mutable n = 1
      while n < 8 && (span >>> u64 (8 * n)) <> u64 0 do
        n <- n + 1
      let bytes = Source.draw n s
      let mutable v = u64 0
      for b in bytes do
        v <- (v <<< u64 8) ||| u64 b
      // all of u64: every value is an offset, and span + 1 would wrap to 0
      let count = Int.wrappingAdd span (u64 1)
      if count = u64 0 then v else v % count

  // offsetU for a span from 0 to Int's max
  let private offset (span: int) (s: Source) : int =
    if span <= 0 then 0 else int (offsetU (u64 span) s)

  /// An integer from `lo` to `hi` (both in): `lo` is the simplest.
  let range (lo: int) (hi: int) : Gen<int> =
    if lo > hi then
      panic $"Gen.range {lo} {hi}: the low end is above the high one"
    // hi - lo in u64: sign extension keeps both values, so the difference is exact at any width
    let span = Int.wrappingSub (u64 hi) (u64 lo)
    Gen(fun s -> Int.wrappingAdd lo (int (offsetU span s)))

  /// One of `xs`, the first the simplest.
  let elements (xs: list<'a>) : Gen<'a> =
    Gen(fun s ->
      match xs with
      | [] -> panic "Gen.elements of no elements"
      | _ -> List.item (offset (List.length xs - 1) s) xs)

  /// One of the generators, each as likely as its weight; the first the simplest.
  let frequency (pairs: list<int * Gen<'a>>) : Gen<'a> =
    if List.exists (fun (w, _) -> w < 0) pairs then
      panic "Gen.frequency needs weights of 0 or more"
    // summed in u64, as a total past Int's max (or a 32-bit chip's) still draws
    let total = List.fold (fun (t: u64) (w, _) -> Int.wrappingAdd t (u64 w)) (u64 0) pairs
    if total = u64 0 then
      panic "Gen.frequency needs a weight above 0"
    Gen(fun s ->
      let mutable at = offsetU (total - u64 1) s
      let mutable chosen = None
      for (w, g) in pairs do
        if chosen.IsNone then
          if at < u64 w then
            chosen <- Some g
          else
            at <- at - u64 w
      match chosen with
      | Some g -> draw g s
      | None -> draw (snd (List.head pairs)) s)

  /// One of the generators, each as likely as the others.
  let oneOf (gens: list<Gen<'a>>) : Gen<'a> = frequency (List.map (fun g -> (1, g)) gens)

  /// `g` again, up to a hundred times, until `p` holds; then the case is discarded. Generate
  /// valid values where you can: a filter that rejects most of them discards most cases.
  let filter (p: 'a -> bool) (g: Gen<'a>) : Gen<'a> =
    Gen(fun s ->
      let mutable tries = 0
      let mutable v = draw g s
      while not (p v) && tries < 100 do
        tries <- tries + 1
        v <- draw g s
      if not (p v) then
        s.discarded.Value <- true
      v)

  /// `n` of `g`.
  let listOfLength (n: int) (g: Gen<'a>) : Gen<list<'a>> =
    Gen(fun s -> List.init n (fun _ -> draw g s))

  /// A list of `g`: before each element one byte, "another?", then the element; a zero stops,
  /// so the empty list is one zero byte, and zeroing a byte in a failing case ends the list
  /// there, which is how a list shrinks to its first elements. The chance of another falls with
  /// the size, and the list stops at the size's length.
  let list (g: Gen<'a>) : Gen<list<'a>> =
    Gen(fun s ->
      let out = Buffer.ofArray [||]
      let mutable more = true
      while more && Buffer.length out < s.size do
        // another element while the byte is below the threshold the size sets: at size 0 never
        let b = (Source.draw 1 s).[0]
        if int b < 256 * s.size / (s.size + 1) && int b > 0 then
          Buffer.push (draw g s) out
        else
          more <- false
      Array.toList (Buffer.toArray out))

  /// An array of `g`, as `list`.
  let array (g: Gen<'a>) : Gen<array<'a>> = map Array.ofList (list g)

  /// Raw bytes: at random, up to the size many; from a given stream (a replay, or `zs fuzz`'s
  /// input), all that's left, so a property over bytes takes the fuzzer's input as it is.
  let bytes () : Gen<array<u8>> =
    Gen(fun s ->
      match s.random with
      | Some _ -> Source.draw (offset s.size s) s
      | None -> Source.draw (max 0 (Buffer.length s.bytes - s.pos.Value)) s)

  /// `None` first (always at size 0, so a recursive type through an option ends), else `g`.
  let option (g: Gen<'a>) : Gen<option<'a>> =
    Gen(fun s -> if s.size = 0 || offset 3 s = 0 then None else Some(draw g s))

  /// What `f size` draws: a generator that depends on the size.
  let sized (f: int -> Gen<'a>) : Gen<'a> = Gen(fun s -> draw (f s.size) s)

  /// `g` at the size `f size`: `Gen.scale (fun n -> n / 2) g` for a field of a recursive type.
  let scale (f: int -> int) (g: Gen<'a>) : Gen<'a> =
    Gen(fun s -> draw g { s with size = max 0 (f s.size) })

  /// `n` values from `g`, from a seed, at sizes growing to 100: to look at what a generator makes.
  let sample (seed: u64) (n: int) (g: Gen<'a>) : list<'a> =
    let r = Numerics.Random.create seed
    List.init n (fun i -> draw g (Source.random r (100 * i / max 1 (n - 1))))

  // a magnitude up to the size, then a sign: zero is all zeros, small values first
  let private signed (s: Source) : int =
    let m = offset s.size s
    if offset 1 s = 0 then m else -m

  /// `()`; draws nothing.
  let unit () : Gen<unit> = constant ()

  /// `true` or `false`; `false` first.
  let bool () : Gen<bool> = Gen(fun s -> offset 1 s = 1)

  /// A character: printable ASCII first (space the simplest), then any scalar value, from U+00A0
  /// on (the controls below it last, so a case shrinks to a printable one; the surrogates,
  /// which aren't characters, skipped).
  let char () : Gen<char> =
    Gen(fun s ->
      let kind = offset 7 s
      if kind < 6 then
        char (32 + offset 94 s)
      else
        // the scalar values in order from U+00A0, wrapping round to U+0000 .. U+009F; those at or
        // above the surrogates moved past them
        let count = 0x110000 - 0x800
        let v = (offset (count - 1) s + 0xA0) % count
        char (if v >= 0xD800 then v + 0x800 else v))

  /// A string of `char`s, up to the size long.
  let string () : Gen<string> = map String.ofChars (list (char ()))

  /// An integer in `-size .. size`: zero the simplest, then small ones.
  let int () : Gen<int> = Gen signed

  /// An `i8` as `int`, within the width.
  let i8 () : Gen<i8> = map (fun n -> i8 (max -128 (min 127 n))) (int ())

  /// An `i16` as `int`.
  let i16 () : Gen<i16> = map (fun n -> i16 n) (int ())

  /// An `i32` as `int`.
  let i32 () : Gen<i32> = map (fun n -> i32 n) (int ())

  /// An `i64` as `int`.
  let i64 () : Gen<i64> = map (fun n -> i64 n) (int ())

  /// A `u8` from 0 to the size (255 at most): zero the simplest.
  let u8 () : Gen<u8> = Gen(fun s -> u8 (offset (min 255 s.size) s))

  /// A `u16` from 0 to the size.
  let u16 () : Gen<u16> = Gen(fun s -> u16 (offset s.size s))

  /// A `u32` from 0 to the size.
  let u32 () : Gen<u32> = Gen(fun s -> u32 (offset s.size s))

  /// A `u64` from 0 to the size.
  let u64 () : Gen<u64> = Gen(fun s -> u64 (offset s.size s))

  /// A float: integer-valued first, then with a fraction, and now and then NaN or an infinity.
  let float () : Gen<f64> =
    Gen(fun s ->
      let kind = offset 15 s
      let m = f64 (signed s)
      if kind < 10 then m
      else if kind < 14 then m + f64 (offset 99 s) / 100.0
      else
        match offset 2 s with
        | 0 -> 0.0 / 0.0
        | 1 -> 1.0 / 0.0
        | _ -> -1.0 / 0.0)

  /// `float`, single precision.
  let f32 () : Gen<f32> = map (fun x -> f32 x) (float ())

  /// The `gen { }` builder: `let!` draws, `return` makes a value.
  module Builder =
    /// `let!`: the rest with what the generator draws.
    let bind (g: Gen<'a>) (f: 'a -> Gen<'b>) : Gen<'b> = Gen(fun s -> draw (f (draw g s)) s)

    /// `return x`.
    let ret (x: 'a) : Gen<'a> = constant x

    /// An `if` without `else`.
    let zero () : Gen<unit> = constant ()

    /// The body, run when drawn.
    let delay (f: unit -> Gen<'a>) : Gen<'a> = Gen(fun s -> draw (f ()) s)

/// A type with a default generator: what `testProperty` draws its parameters with. Core's types
/// have it, and `[<Derive(Arbitrary)>]` gives it to a record or union: a record draws each field,
/// a union a case and then its fields, each field at half the size. At size 0, and past a
/// replayed stream's end, a union takes a case that ends a value, so a recursive type's values
/// are finite (see the derive).
trait Arbitrary<'a> =
  /// The type's generator.
  abstract arbitrary : unit -> Gen<'a>

/// `()`.
impl Arbitrary<unit> =
  let arbitrary () = Gen.unit ()

/// `Gen.bool`.
impl Arbitrary<bool> =
  let arbitrary () = Gen.bool ()

/// `Gen.char`.
impl Arbitrary<char> =
  let arbitrary () = Gen.char ()

/// `Gen.string`.
impl Arbitrary<string> =
  let arbitrary () = Gen.string ()

/// `Gen.int`: `-size .. size`.
impl Arbitrary<int> =
  let arbitrary () = Gen.int ()

/// `Gen.i8`.
impl Arbitrary<i8> =
  let arbitrary () = Gen.i8 ()

/// `Gen.i16`.
impl Arbitrary<i16> =
  let arbitrary () = Gen.i16 ()

/// `Gen.i32`.
impl Arbitrary<i32> =
  let arbitrary () = Gen.i32 ()

/// `Gen.i64`.
impl Arbitrary<i64> =
  let arbitrary () = Gen.i64 ()

/// `Gen.u8`.
impl Arbitrary<u8> =
  let arbitrary () = Gen.u8 ()

/// `Gen.u16`.
impl Arbitrary<u16> =
  let arbitrary () = Gen.u16 ()

/// `Gen.u32`.
impl Arbitrary<u32> =
  let arbitrary () = Gen.u32 ()

/// `Gen.u64`.
impl Arbitrary<u64> =
  let arbitrary () = Gen.u64 ()

/// `Gen.float`.
impl Arbitrary<f64> =
  let arbitrary () = Gen.float ()

/// `Gen.f32`.
impl Arbitrary<f32> =
  let arbitrary () = Gen.f32 ()

/// A list of the element's values, up to the size long.
impl Arbitrary<list<'a>> =
  let arbitrary () = Gen.list (arbitrary ())

/// An array of the element's values.
impl Arbitrary<array<'a>> =
  let arbitrary () = Gen.array (arbitrary ())

/// `None` first.
impl Arbitrary<option<'a>> =
  let arbitrary () = Gen.option (arbitrary ())

/// `Ok` first.
impl Arbitrary<result<'a, 'e>> =
  let arbitrary () = Gen.oneOf [ Gen.map Ok (arbitrary ()); Gen.map Error (arbitrary ()) ]

/// A pair of the parts' values, drawn in order.
impl Arbitrary<'a * 'b> =
  let arbitrary () = Gen(fun s -> (Gen.draw (arbitrary ()) s, Gen.draw (arbitrary ()) s))

/// A triple of the parts' values, drawn in order.
impl Arbitrary<'a * 'b * 'c> =
  let arbitrary () = Gen(fun s ->
    (Gen.draw (arbitrary ()) s, Gen.draw (arbitrary ()) s, Gen.draw (arbitrary ()) s))

/// Four values, drawn in order.
impl Arbitrary<'a * 'b * 'c * 'd> =
  let arbitrary () =
    Gen(fun s ->
      (Gen.draw (arbitrary ()) s,
        Gen.draw (arbitrary ()) s,
        Gen.draw (arbitrary ()) s,
        Gen.draw (arbitrary ()) s))

/// A union's case as a derive sees it (`Shape.cases`): its name, its index, how many fields, and
/// its rank, how readily a generated value of it ends: 0 when no field can hold a value of the
/// type, 1 when only lists, arrays and options can (empty at size 0 and from zero bytes), 2
/// otherwise (a field that is the type, or holds it in a record, a tuple, a result or another
/// union, or is a type parameter, which may be the type).
type CaseInfo = { name: string; index: int; count: int; rank: int }

/// A record draws each field; a union draws a case, then its fields; a field is drawn at half the
/// size. The cases come in order of rank, so zero bytes take one of the lowest; at size 0 and past
/// a replayed stream's end the choice is the lowest rank's cases with the fewest fields. So a
/// value ends when its type has a case of rank 0 or 1, at every level; a type whose every case
/// is rank 2 (each holds the type outright) may not.
derive Arbitrary =
  let arbitrary () : Gen<'self> =
    Gen(fun src ->
      let built =
        match Shape.kind with
        | RecordKind ->
          Shape.build (fun f -> Ok(Gen.draw (Gen.scale (fun n -> n / 2) (arbitrary ())) src))
        | UnionKind ->
          let all = Shape.cases
          let lowest = List.fold (fun m (c: CaseInfo) -> min m c.rank) 2 all
          let ends = List.filter (fun (c: CaseInfo) -> c.rank = lowest) all
          // of those, the ones with the fewest fields: the only choice at size 0 or past the end
          let fewest = List.fold (fun m (c: CaseInfo) -> min m c.count) (List.head ends).count ends
          let least = List.filter (fun (c: CaseInfo) -> c.count = fewest) ends
          let ranked (r: int) = List.filter (fun (c: CaseInfo) -> c.rank = r) all
          let cases =
            if src.size = 0 || src.overrun.Value then
              least
            else
              List.append (ranked 0) (List.append (ranked 1) (ranked 2))
          let c = Gen.draw (Gen.elements cases) src
          match Shape.buildCase c.name (fun f ->
            Ok(Gen.draw (Gen.scale (fun n -> n / 2) (arbitrary ())) src)) with
          | Some r -> r
          | None -> Error "a case from Shape.cases"
      match built with
      | Ok v -> v
      | Error e -> panic e)

/// What a property's body gives back, checked against the case's source: `unit` passes, `false`
/// and an `Error` fail, and a `Prop` runs on the source (drawing more, discarding, labelling).
trait Checks<'r> =
  /// `None` when the case passed; the failure's message otherwise.
  abstract check : 'r -> Source -> option<string>

/// A body that returns: the case passed.
impl Checks<unit> =
  let check () (_: Source) = None

/// `false` fails the case.
impl Checks<bool> =
  let check b (_: Source) = if b then None else Some "false"

/// An `Error` fails the case, shown.
impl Checks<result<'a, 'e>> =
  let check r (_: Source) =
    match r with
    | Ok _ -> None
    | Error e -> Some $"Error {e}"

/// How a case of a `Prop` ended.
type Verdict =
  /// The checks held.
  | Passed
  /// A check failed: its message.
  | Failed of string
  /// The case doesn't count (`Prop.assume` was false, or a filter never held).
  | Discarded

/// A property that draws as it goes: `prop { let! x = Gen.int … do! Prop.assume (x <> 0) …
/// return x / x = 1 }`. Its draws come from the case's source, after the parameters', so they
/// shrink with them.
type Prop = Prop of (Source -> Verdict)

/// A system checked against a model by a sequence of commands (`Prop.model`): `init` makes the
/// two, and `step` applies a command to both, or says how they disagree.
type Model<'c, 's, 'm> =
  { /// The system and the model to start from.
    init: unit -> 's * 'm
    /// Both after a command, or an `Error` naming the disagreement.
    step: 'c -> 's * 'm -> result<'s * 'm, string> }

/// Functions on `Prop`, and the `prop { }` builder.
module Prop =
  /// Runs the property's checks on a source.
  let run (Prop f) (s: Source) : Verdict = f s

  /// `do! Prop.assume cond`: a false condition discards the case, and nothing after it runs
  /// (FsCheck's `==>`). Generate valid values where you can: discards cost cases.
  let assume (cond: bool) : Gen<unit> =
    Gen(fun s ->
      if not cond then
        s.discarded.Value <- true)

  /// `do! Prop.label name`: names the case; a failure shows its labels, and a passing property
  /// reports how its cases were labelled.
  let label (name: string) : Gen<unit> = Gen(fun s -> Buffer.push name s.labels)

  /// `do! Prop.classify cond name`: labels the case `name` when `cond` holds.
  let classify (cond: bool) (name: string) : Gen<unit> = if cond then label name else Gen.unit ()

  /// `do! Prop.collect value`: labels the case with the value's text.
  let collect (value: 'a) : Gen<unit> = label (show value)

  /// Applies each command to the system and the model, in turn; the first disagreement is the
  /// failure, with the commands before it, so a failing sequence shrinks to the fewest commands
  /// with the smallest arguments.
  let model (commands: list<'c>) (m: Model<'c, 's, 'm>) : result<unit, string> =
    let rec go (i: int) (state: 's * 'm) (rest: list<'c>) : result<unit, string> =
      match rest with
      | [] -> Ok()
      | c :: more ->
        match m.step c state with
        | Ok next -> go (i + 1) next more
        | Error e -> Error $"after {i} commands, {show c}: {e}"
    go 0 (m.init ()) commands

  /// The `prop { }` builder: `let!` draws from a generator, `do!` runs a check or a draw of
  /// unit, and `return` gives the case's result (`unit`, `bool`, a `result` or another `Prop`).
  module Builder =
    /// `let!`: the rest with what the generator draws, unless the case was discarded.
    let bind (g: Gen<'a>) (f: 'a -> Prop) : Prop =
      Prop(fun s ->
        let x = Gen.draw g s
        if Source.rejected s then Discarded else run (f x) s)

    /// `return x`: the case's result, checked.
    let ret (x: 'r) : Prop =
      Prop(fun s ->
        match check x s with
        | None -> if s.discarded.Value then Discarded else Passed
        | Some m -> Failed m)

    /// A body that ends in a statement: the case passed.
    let zero () : Prop = Prop(fun _ -> Passed)

    /// The body, run with the case.
    let delay (f: unit -> Prop) : Prop = Prop(fun s -> run (f ()) s)

/// A `Prop` runs on the case's source: a `Failed` fails the case, a `Discarded` discards it.
impl Checks<Prop> =
  let check p (s: Source) =
    match Prop.run p s with
    | Passed -> None
    | Failed m -> Some m
    | Discarded ->
      s.discarded.Value <- true
      None

/// A property's settings: `testPropertyWith { runs = 1000 } "name" …` names what changes.
type PropertySettings =
  { /// Cases that must pass.
    runs: int = 100
    /// The size the cases grow to over the runs.
    maxSize: int = 100
    /// Discarded cases allowed per passing one, before the property fails.
    maxDiscardRatio: int = 10
    /// The seed; `None` draws a new one each run, printed on failure.
    seed: option<u64> = None
    /// Whether a failing case is shrunk.
    shrink: bool = true }

// a shrink candidate's bytes, re-run: whether the property still fails on them (not an overrun
// or a discard), and the value and message then
let private stillFails (prop: 'a -> 'r) (size: int) (bytes: array<u8>) : option<'a * string * list<string>> =
  let src = Source.ofBytes bytes size
  let x = Gen.draw (arbitrary ()) src
  if Source.rejected src then
    None
  else
    match check (prop x) src with
    | Some msg when not (Source.rejected src) ->
      Some(x, msg, Array.toList (Buffer.toArray src.labels))
    | _ -> None

// the failing stream made shorter, then its bytes smaller, while the property still fails:
// shorter first (Hypothesis's order), a block at a time, then each byte zeroed, halved or one
// less; until a pass over it changes nothing
let private shrink (prop: 'a -> 'r) (size: int) (bytes0: array<u8>) : array<u8> * int =
  let bytes = ref bytes0
  let steps = ref 0
  let progress = ref true
  let accept (candidate: array<u8>) : bool =
    if Array.toList candidate = Array.toList bytes.Value then
      false
    else
      match stillFails prop size candidate with
      | Some _ ->
        bytes.Value <- candidate
        steps.Value <- steps.Value + 1
        progress.Value <- true
        true
      | None -> false
  while progress.Value && steps.Value < 2000 do
    progress.Value <- false
    // blocks dropped, the largest first
    let mutable block = Array.length bytes.Value / 2
    while block >= 1 do
      let mutable at = 0
      while at + block <= Array.length bytes.Value do
        let now = bytes.Value
        if not (accept (Array.append (Array.sub now 0 at) (Array.sub now (at + block) (Array.length now - at - block)))) then
          at <- at + block
      block <- block / 2
    // bytes made smaller: zero, half, one less
    for i in 0 .. Array.length bytes.Value - 1 do
      if i < Array.length bytes.Value then
        let b = bytes.Value.[i]
        let tryWith (v: u8) =
          let mutable candidate = Array.copy bytes.Value
          candidate.[i] <- v
          accept candidate
        if b > u8 0 then
          if not (tryWith (u8 0)) then
            if not (tryWith (b / u8 2)) then
              tryWith (b - u8 1) |> ignore
  (bytes.Value, steps.Value)

/// A property with its settings: `prop` runs on `runs` cases drawn with `Arbitrary` at its
/// parameter's type (a tuple for several), the cases growing from size 0 to `maxSize`; `unit`,
/// `true`, `Ok` or a `Prop` that passes passes a case (a `Prop` draws more as it goes, and may
/// discard the case or label it). A case that returns `false` or an `Error` fails the property:
/// it's shrunk to a smallest failing case (shorter bytes, then smaller), which the failure
/// shows, with the seed to replay the run. A case that panics ends the test at once, with the
/// panic: `testPropertyWith { seed = Some s }` replays it.
let testPropertyWith (ps: PropertySettings) (name: string) (prop: 'a -> 'r) : Test =
  let labelled (ls: list<string>) =
    if List.isEmpty ls then "" else $"\n  labels: {String.join ", " ls}"
  // one case from given bytes (zs test's replay of a case that panicked, or a saved one): the
  // case shown, then run; a discarded one is said so
  let replay (bytes: array<u8>) (size: int) (quiet: bool) =
    let src = Source.ofBytes bytes size
    let x = Gen.draw (arbitrary ()) src
    if Source.rejected src then
      if not quiet then
        println "zs-discarded"
    else
      if not quiet then
        println $"case: {show x}"
      match check (prop x) src with
      | Some msg when not (Source.rejected src) ->
        panic $"falsified: {show x}\n  {msg}{labelled (Array.toList (Buffer.toArray src.labels))}"
      | Some _ ->
        if not quiet then
          println "zs-discarded"
      | None -> ()
  let body (d: PropertyDriver) =
    let seed =
      match ps.seed with
      | Some s -> s
      | None -> Runtime.ticks ()
    let mutable passed = 0
    let mutable discarded = 0
    let mutable failure = None
    let counts = ref Map.empty
    while passed < ps.runs && failure.IsNone do
      // the size grows with the cases, discarded ones included: at size 0 a filter may never hold
      let size = min ps.maxSize (ps.maxSize * (passed + discarded) / max 1 (ps.runs - 1))
      // each case from its own seed, so one regenerates alone
      let index = passed + discarded
      let caseSeed =
        Int.wrappingAdd seed (Int.wrappingMul (u64 (index + 1)) (u64 0x9E3779B97F4A7C15))
      d.onCase index caseSeed size
      let src = Source.randomWith (Numerics.Random.create caseSeed) size d.onDraw
      let x = Gen.draw (arbitrary ()) src
      let result = if Source.rejected src then None else check (prop x) src
      if Source.rejected src then
        discarded <- discarded + 1
        if discarded > ps.maxDiscardRatio * max 1 passed + ps.maxDiscardRatio then
          panic $"gave up: {name}: {discarded} cases discarded for {passed} passed: generate valid values instead of filtering invalid ones (seed {seed})"
      else
        match result with
        | None ->
          passed <- passed + 1
          for l in Buffer.toArray src.labels do
            counts.Value <- Map.add l (1 + Option.defaultValue 0 (Map.tryFind l counts.Value)) counts.Value
        | Some msg ->
          failure <- Some(x,
            msg,
            Array.toList (Buffer.toArray src.labels),
            Buffer.toArray src.bytes,
            size)
    match failure with
    | None ->
      // how the cases were labelled, when any were
      if not (Map.isEmpty counts.Value) then
        let total = max 1 passed
        let parts = List.map (fun (l, n) -> $"{100 * n / total}% {l}") (Map.toList counts.Value)
        println $"  {name}: {passed} cases, {discarded} discarded; {String.join ", " parts}"
    | Some(x0, msg0, labels0, bytes0, size) ->
      let (x, msg, labels, steps) =
        if ps.shrink then
          let (bytes, steps) = shrink prop size bytes0
          match stillFails prop size bytes with
          | Some(x, msg, labels) -> (x, msg, labels, steps)
          | None -> (x0, msg0, labels0, steps)
        else
          (x0, msg0, labels0, 0)
      panic $"falsified after {passed + 1} cases ({steps} shrinks): {show x}\n  {msg}{labelled labels}\n  replay: testPropertyWith {{ seed = Some (u64 {seed}) }}"
  let run (d: PropertyDriver) =
    match d.replay with
    | Some(bytes, size) -> replay bytes size d.quiet
    | None -> body d
  Property(name, run)

/// A property with the default settings: 100 cases, growing to size 100, shrunk on failure.
let testProperty (name: string) (prop: 'a -> 'r) : Test = testPropertyWith { runs = 100 } name prop
