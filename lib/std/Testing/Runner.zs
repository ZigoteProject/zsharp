/// The test binary's entry: `zs test` builds one from a file's `[<Tests>]` values, lists its
/// tests with `--list`, and runs each by its path in a process of its own.
module Testing.Runner

/// A test with its path and what it has from the groups above it.
type private Leaf =
  { path: string
    run: unit -> unit
    focus: Focus
    timeout: int
    /// The sequenced group it's in ("" for none): its tests run one at a time.
    sequence: string }

let rec private leaves (prefix: string) (focus: Focus) (sequence: string) (t: Test) : list<Leaf> =
  match t with
  | Case(name, run, f, ms) ->
    [ { path = prefix + name
        run = run
        focus = (if focus = Normal then f else focus)
        timeout = ms
        sequence = sequence } ]
  | Group(name, tests, f, sequenced) ->
    let path = prefix + name
    let focus = if focus = Normal then f else focus
    let sequence = if sequence = "" && sequenced then path else sequence
    List.collect (leaves (path + "/") focus sequence) tests

/// Lists the tests (`--list`: path, focus, time limit and sequenced group, a line each, tabs
/// between) or runs the one a path names; the exit code.
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
      println $"{l.path}\t{word l.focus}\t{l.timeout}\t{l.sequence}"
    0
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
