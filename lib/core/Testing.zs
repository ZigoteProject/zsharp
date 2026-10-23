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
