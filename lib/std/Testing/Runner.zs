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
    bench: bool
    /// A property: its run, which `zs test` drives (recording, or replaying one case).
    property: option<PropertyDriver -> unit> }

let rec private leaves (prefix: string) (focus: Focus) (sequence: string) (t: Test) : list<Leaf> =
  match t with
  | Case(name, run, f, ms) ->
    [ { path = prefix + name
        run = run
        focus = (if focus = Normal then f else focus)
        timeout = ms
        sequence = sequence
        bench = false
        property = None } ]
  | Bench(name, run) ->
    [ { path = prefix + name
        run = run
        focus = focus
        timeout = 600000
        sequence = sequence
        bench = true
        property = None } ]
  | Property(name, run) ->
    [ { path = prefix + name
        run = (fun () -> run { replay = None; onCase = (fun _ _ _ -> ()); onDraw = None })
        focus = focus
        timeout = 60000
        sequence = sequence
        bench = false
        property = Some run } ]
  | Group(name, tests, f, sequenced) ->
    let path = prefix + name
    let focus = if focus = Normal then f else focus
    let sequence = if sequence = "" && sequenced then path else sequence
    List.collect (leaves (path + "/") focus sequence) tests

/// Lists the tests (`--list`: path, focus, time limit, sequenced group and kind, a line each,
/// tabs between), runs the one a path names, or times a benchmark (`--bench path runs`: three
/// warm-up runs, then the nanoseconds of each of `runs` runs on one line); the exit code. A
/// property run with `--record case record` notes each case's seed and size in the first file
/// and its bytes, as drawn, in the second (hex), so `zs test` can shrink a case that panics by
/// replaying the binary: `--replay bytes size` runs one case from a file of hex bytes, printing
/// the case, or `zs-discarded`.
let main (tests: list<Test>) : int =
  let all = List.collect (leaves "" Normal "") tests

  let word (f: Focus) =
    match f with
    | Normal -> "normal"
    | Focused -> "focused"
    | Pending -> "pending"

  let kind (l: Leaf) =
    if l.bench then "bench" else if Option.isSome l.property then "property" else "test"

  let find (path: string) = List.tryFind (fun (l: Leaf) -> l.path = path) all

  match Environment.args () with
  | [ "--list" ] ->
    for l in all do
      println $"{l.path}\t{word l.focus}\t{l.timeout}\t{l.sequence}\t{kind l}"
    0
  | [ path; "--record"; caseFile; recordFile ] ->
    match find path with
    | Some { property = Some run } ->
      let onCase (index: int) (seed: u64) (size: int) =
        IO.File.writeAllText caseFile $"{seed}\t{size}\t{index}\n" |> ignore
        IO.File.writeAllText recordFile "" |> ignore
      let onDraw (bytes: array<u8>) =
        IO.File.appendAllText recordFile (Text.Hex.encode bytes) |> ignore
      run { replay = None; onCase = onCase; onDraw = Some onDraw }
      0
    | Some l ->
      l.run ()
      0
    | None ->
      eprintln $"no test {path}"
      2
  | [ path; "--replay"; bytesFile; sizeText ] ->
    match (find path, IO.File.readAllText bytesFile, (Int.parse sizeText : option<int>)) with
    | (Some { property = Some run }, Ok hex, Some size) ->
      match Text.Hex.decode (String.trim hex) with
      | Some bytes ->
        run { replay = Some(bytes, size); onCase = (fun _ _ _ -> ()); onDraw = None }
        0
      | None ->
        eprintln $"{bytesFile}: not hex"
        2
    | _ ->
      eprintln $"no property {path}, or no bytes to replay"
      2
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
