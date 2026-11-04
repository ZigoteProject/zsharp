/// The test binary's entry: `zs test` builds one from a file's `[<Tests>]` values, lists its
/// tests with `--list`, and runs each by its path in a process of its own; `zs bench` times a
/// benchmark with `--bench path runs`.
module Testing.Runner

/// A test with its path and what it has from the groups above it.
type private Leaf =
  { path: string
    run: unit -> unit
    focus: Focus
    timeout: int
    /// The sequenced group it's in ("" for none): its tests run one at a time.
    sequence: string
    /// A test, or a benchmark.
    bench: bool }

let rec private leaves (prefix: string) (focus: Focus) (sequence: string) (t: Test) : list<Leaf> =
  match t with
  | Case(name, run, f, ms) ->
    [ { path = prefix + name
        run = run
        focus = (if focus = Normal then f else focus)
        timeout = ms
        sequence = sequence
        bench = false } ]
  | Bench(name, run) ->
    [ { path = prefix + name
        run = run
        focus = focus
        timeout = 600000
        sequence = sequence
        bench = true } ]
  | Group(name, tests, f, sequenced) ->
    let path = prefix + name
    let focus = if focus = Normal then f else focus
    let sequence = if sequence = "" && sequenced then path else sequence
    List.collect (leaves (path + "/") focus sequence) tests

/// Lists the tests (`--list`: path, focus, time limit, sequenced group and kind, a line each,
/// tabs between), runs the one a path names, or times a benchmark (`--bench path runs`: three
/// warm-up runs, then the nanoseconds of each of `runs` runs on one line); the exit code.
let main (tests: list<Test>) : int =
  let all = List.collect (leaves "" Normal "") tests

  let word (f: Focus) =
    match f with
    | Normal -> "normal"
    | Focused -> "focused"
    | Pending -> "pending"

  match Environment.args () with
  | [ "--list" ] ->
    for l in all do
      println $"{l.path}\t{word l.focus}\t{l.timeout}\t{l.sequence}\t{(if l.bench then "bench" else "test")}"
    0
  | [ "--bench"; path; runs ] ->
    match (List.tryFind (fun (l: Leaf) -> l.path = path) all, (Int.parse runs : option<int>)) with
    | (Some l, Some n) when n > 0 ->
      for _ in 1 .. 3 do
        l.run ()
      let samples = Buffer.empty
      for _ in 1 .. n do
        let t0 = Runtime.ticks ()
        l.run ()
        Buffer.push (string (Runtime.ticks () - t0)) samples
      println (String.join " " (Array.toList (Buffer.toArray samples)))
      0
    | _ ->
      eprintln $"no benchmark {path}"
      2
  | [ path ] ->
    match List.tryFind (fun (l: Leaf) -> l.path = path) all with
    | Some l ->
      l.run ()
      0
    | None ->
      eprintln $"no test {path}"
      2
  | _ ->
    eprintln "usage: <tests> --list | <tests> <path>"
    2
