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
    /// How large the values may get: a property's cases grow from 0 to its `maxSize`.
    size: int }

/// Functions on `Source`.
module Source =
  /// A random stream from `r`, recording what's drawn, at `size`.
  let random (r: Numerics.Random) (size: int) : Source =
    { bytes = Buffer.ofArray [||]
      pos = ref 0
      random = Some r
      overrun = ref false
      discarded = ref false
      size = size }

  /// A given stream (a shrink candidate, a saved case), at `size`.
  let ofBytes (bytes: array<u8>) (size: int) : Source =
    { bytes = Buffer.ofArray bytes
      pos = ref 0
      random = None
      overrun = ref false
      discarded = ref false
      size = size }

  /// `n` bytes from the stream: the next of the given or recorded ones, else drawn at random and
  /// recorded, else (a given stream used up) zeros, and the source has overrun.
  let draw (n: int) (s: Source) : array<u8> =
    let mutable out = Array.create n (u8 0)
    for i in 0 .. n - 1 do
      let p = s.pos.Value + i
      if p < Buffer.length s.bytes then
        out.[i] <- s.bytes.[p]
      else
        match s.random with
        | Some r ->
          let b = u8 (Numerics.Random.nextInt 0 256 r)
          Buffer.push b s.bytes
          out.[i] <- b
        | None -> s.overrun.Value <- true
    s.pos.Value <- s.pos.Value + n
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

  // an offset from 0 to span (inclusive), from the fewest bytes that cover it, big-endian: all
  // zeros is 0
  let private offset (span: int) (s: Source) : int =
    if span <= 0 then
      0
    else
      let mutable n = 1
      let mutable top = 256
      while top <= span && n < 8 do
        n <- n + 1
        top <- top * 256
      let bytes = Source.draw n s
      let mutable v = 0
      for b in bytes do
        v <- Int.wrappingAdd (Int.wrappingMul v 256) (int b)
      (if v < 0 then -(v + 1) else v) % (span + 1)

  /// An integer from `lo` to `hi` (both in): `lo` is the simplest.
  let range (lo: int) (hi: int) : Gen<int> = Gen(fun s -> lo + offset (hi - lo) s)

  /// One of `xs`, the first the simplest.
  let elements (xs: list<'a>) : Gen<'a> =
    Gen(fun s ->
      match xs with
      | [] -> panic "Gen.elements of no elements"
      | _ -> List.item (offset (List.length xs - 1) s) xs)

  /// One of the generators, each as likely as its weight; the first the simplest.
  let frequency (pairs: list<int * Gen<'a>>) : Gen<'a> =
    let total = List.sumBy fst pairs
    if total <= 0 then
      panic "Gen.frequency needs weights above 0"
    Gen(fun s ->
      let mutable at = offset (total - 1) s
      let mutable chosen = None
      for (w, g) in pairs do
        if chosen.IsNone then
          if at < w then
            chosen <- Some g
          else
            at <- at - w
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

  /// A list of `g`, up to the size long: the length first, so a shorter stream is a shorter list.
  let list (g: Gen<'a>) : Gen<list<'a>> = Gen(fun s -> draw (listOfLength (offset s.size s) g) s)

  /// An array of `g`, as `list`.
  let array (g: Gen<'a>) : Gen<array<'a>> = map Array.ofList (list g)

  /// `None` first, else `g`.
  let option (g: Gen<'a>) : Gen<option<'a>> =
    Gen(fun s -> if offset 3 s = 0 then None else Some(draw g s))

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
  let unit : Gen<unit> = constant ()

  /// `true` or `false`; `false` first.
  let bool : Gen<bool> = Gen(fun s -> offset 1 s = 1)

  /// A character: printable ASCII first (space the simplest), then any scalar value.
  let char : Gen<char> =
    Gen(fun s ->
      let kind = offset 7 s
      if kind < 6 then
        char (32 + offset 94 s)
      else
        char (0xA1 + offset (0xD7FF - 0xA1) s))

  /// A string of `char`s, up to the size long.
  let string : Gen<string> = map String.ofChars (list char)

  /// An integer in `-size .. size`: zero the simplest, then small ones.
  let int : Gen<int> = Gen signed

  /// An `i8` as `int`, within the width.
  let i8 : Gen<i8> = map (fun n -> i8 (max -128 (min 127 n))) int

  /// An `i16` as `int`.
  let i16 : Gen<i16> = map (fun n -> i16 n) int

  /// An `i32` as `int`.
  let i32 : Gen<i32> = map (fun n -> i32 n) int

  /// An `i64` as `int`.
  let i64 : Gen<i64> = map (fun n -> i64 n) int

  /// A `u8` from 0 to the size (255 at most): zero the simplest.
  let u8 : Gen<u8> = Gen(fun s -> u8 (offset (min 255 s.size) s))

  /// A `u16` from 0 to the size.
  let u16 : Gen<u16> = Gen(fun s -> u16 (offset s.size s))

  /// A `u32` from 0 to the size.
  let u32 : Gen<u32> = Gen(fun s -> u32 (offset s.size s))

  /// A `u64` from 0 to the size.
  let u64 : Gen<u64> = Gen(fun s -> u64 (offset s.size s))

  /// A float: integer-valued first, then with a fraction, and now and then NaN or an infinity.
  let float : Gen<f64> =
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
  let f32 : Gen<f32> = map (fun x -> f32 x) float

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
/// a union a case (one without fields when the size is 0) and then its fields, each field at half
/// the size, so a recursive type's values are finite.
trait Arbitrary<'a> =
  /// The type's generator.
  abstract arbitrary : unit -> Gen<'a>

/// `()`.
impl Arbitrary<unit> =
  let arbitrary () = Gen.unit

/// `Gen.bool`.
impl Arbitrary<bool> =
  let arbitrary () = Gen.bool

/// `Gen.char`.
impl Arbitrary<char> =
  let arbitrary () = Gen.char

/// `Gen.string`.
impl Arbitrary<string> =
  let arbitrary () = Gen.string

/// `Gen.int`: `-size .. size`.
impl Arbitrary<int> =
  let arbitrary () = Gen.int

/// `Gen.i8`.
impl Arbitrary<i8> =
  let arbitrary () = Gen.i8

/// `Gen.i16`.
impl Arbitrary<i16> =
  let arbitrary () = Gen.i16

/// `Gen.i32`.
impl Arbitrary<i32> =
  let arbitrary () = Gen.i32

/// `Gen.i64`.
impl Arbitrary<i64> =
  let arbitrary () = Gen.i64

/// `Gen.u8`.
impl Arbitrary<u8> =
  let arbitrary () = Gen.u8

/// `Gen.u16`.
impl Arbitrary<u16> =
  let arbitrary () = Gen.u16

/// `Gen.u32`.
impl Arbitrary<u32> =
  let arbitrary () = Gen.u32

/// `Gen.u64`.
impl Arbitrary<u64> =
  let arbitrary () = Gen.u64

/// `Gen.float`.
impl Arbitrary<f64> =
  let arbitrary () = Gen.float

/// `Gen.f32`.
impl Arbitrary<f32> =
  let arbitrary () = Gen.f32

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

/// A union's case as a derive sees it (`Shape.cases`): its name, its index and how many fields.
type CaseInfo = { name: string; index: int; count: int }

/// A record draws each field; a union draws a case (one without fields when the size is 0, so a
/// recursive type ends), then its fields; a field is drawn at half the size.
derive Arbitrary =
  let arbitrary () : Gen<'self> =
    Gen(fun src ->
      let built =
        match Shape.kind with
        | RecordKind ->
          Shape.build (fun f -> Ok(Gen.draw (Gen.scale (fun n -> n / 2) (arbitrary ())) src))
        | UnionKind ->
          let leaves = List.filter (fun (c: CaseInfo) -> c.count = 0) Shape.cases
          let cases = if src.size = 0 && not (List.isEmpty leaves) then leaves else Shape.cases
          let c = Gen.draw (Gen.elements cases) src
          match Shape.buildCase c.name (fun f ->
            Ok(Gen.draw (Gen.scale (fun n -> n / 2) (arbitrary ())) src)) with
          | Some r -> r
          | None -> Error "a case from Shape.cases"
      match built with
      | Ok v -> v
      | Error e -> panic e)

/// What a property's body gives back, as a verdict: `unit` passes, `false` and an `Error` fail.
trait Verdict<'r> =
  /// `None` when the case passed; the failure's message otherwise.
  abstract verdict : 'r -> option<string>

/// A body that returns: the case passed.
impl Verdict<unit> =
  let verdict () = None

/// `false` fails the case.
impl Verdict<bool> =
  let verdict b = if b then None else Some "false"

/// An `Error` fails the case, shown.
impl Verdict<result<'a, 'e>> =
  let verdict r =
    match r with
    | Ok _ -> None
    | Error e -> Some $"Error {e}"

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
let private stillFails (prop: 'a -> 'r) (size: int) (bytes: array<u8>) : option<'a * string> =
  let src = Source.ofBytes bytes size
  let x = Gen.draw (arbitrary ()) src
  if Source.rejected src then
    None
  else
    match verdict (prop x) with
    | Some msg -> Some(x, msg)
    | None -> None

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
/// `true` or `Ok` passes a case. A case that returns `false` or an `Error` fails the property:
/// it's shrunk to a smallest failing case (shorter bytes, then smaller), which the failure
/// shows, with the seed to replay the run. A case that panics ends the test at once, with the
/// panic: `testPropertyWith { seed = Some s }` replays it.
let testPropertyWith (ps: PropertySettings) (name: string) (prop: 'a -> 'r) : Test =
  let body () =
    let seed =
      match ps.seed with
      | Some s -> s
      | None -> Runtime.ticks ()
    let r = Numerics.Random.create seed
    let mutable passed = 0
    let mutable discarded = 0
    let mutable failure = None
    while passed < ps.runs && failure.IsNone do
      let size = ps.maxSize * passed / max 1 (ps.runs - 1)
      let src = Source.random r size
      let x = Gen.draw (arbitrary ()) src
      if Source.rejected src then
        discarded <- discarded + 1
        if discarded > ps.maxDiscardRatio * max 1 passed + ps.maxDiscardRatio then
          panic $"{name}: {discarded} cases discarded for {passed} passed: generate valid values instead of filtering invalid ones (seed {seed})"
      else
        match verdict (prop x) with
        | None -> passed <- passed + 1
        | Some msg -> failure <- Some(x, msg, Buffer.toArray src.bytes, size)
    match failure with
    | None -> ()
    | Some(x0, msg0, bytes0, size) ->
      let (x, msg, steps) =
        if ps.shrink then
          let (bytes, steps) = shrink prop size bytes0
          match stillFails prop size bytes with
          | Some(x, msg) -> (x, msg, steps)
          | None -> (x0, msg0, steps)
        else
          (x0, msg0, 0)
      panic $"falsified after {passed + 1} cases ({steps} shrinks): {show x}\n  {msg}\n  replay: testPropertyWith {{ seed = Some (u64 {seed}) }}"
  Case(name, body, Normal, limit)

/// A property with the default settings: 100 cases, growing to size 100, shrunk on failure.
let testProperty (name: string) (prop: 'a -> 'r) : Test = testPropertyWith { runs = 100 } name prop
