// What log lines add up to. Stats is a monoid (Add): a line is a one-entry Stats, a chunk the
// sum of its lines, the run the sum of its chunks. + is associative, so chunks can be counted
// on any core and merged in order. Even line numbers add up: a chunk numbers its lines from 1,
// and + shifts them past the lines seen before it in the same file.
open Entry

type Route = { hits: int; totalMs: int; errors: int }

impl Add<Route> =
  let add a b = { hits = a.hits + b.hits; totalMs = a.totalMs + b.totalMs; errors = a.errors + b.errors }
  let zero = { hits = 0; totalMs = 0; errors = 0 }

// a line that didn't parse
type Bad = { file: string; line: int; why: string }

type Stats =
  { lines: int                 // entries counted
    seen: Map<string, int>     // every line read, blank and bad too, per file
    bad: list<Bad>             // in file order
    levels: Map<string, int>
    routes: Map<string, Route>
    slowest: list<Entry> }     // at most `keep`, slowest first

let private keep = 5

// ---- adding

let private bump key v m = Map.add key (v + Option.defaultValue Add.zero (Map.tryFind key m)) m

// the two maps merged, values under the same key added
let private merge a b = Map.fold (fun m k v -> bump k v m) a b

// a bad line of a later part, numbered past the lines `seen` before it in its file
let private after seen (b: Bad) = { b with line = b.line + Option.defaultValue 0 (Map.tryFind b.file seen) }

impl Add<Stats> =
  let add a b =
    { lines = a.lines + b.lines
      seen = merge a.seen b.seen
      bad = if b.bad = [] then a.bad else List.append a.bad (List.map (after a.seen) b.bad)  // most add none: don't copy
      levels = merge a.levels b.levels
      routes = merge a.routes b.routes
      slowest = List.append a.slowest b.slowest |> List.sortBy (fun e -> -e.ms) |> List.take keep }
  let zero = { lines = 0; seen = Map.empty; bad = []; levels = Map.empty; routes = Map.empty; slowest = [] }

// ---- one entry

let private routeName (e: Entry) = e.meth + " " + e.path

let private routeOf (e: Entry) = { hits = 1; totalMs = e.ms; errors = if e.status >= 500 then 1 else 0 }

// the definition: a line's Stats
let ofEntry (e: Entry) : Stats =
  { Add.zero with
      lines = 1
      levels = Map.ofList [ (levelName e.level, 1) ]
      routes = Map.ofList [ (routeName e, routeOf e) ]
      slowest = [ e ] }

// e after the requests at least as slow: where + would put it
let rec private insert (e: Entry) xs =
  match xs with
  | x :: rest when x.ms >= e.ms -> x :: insert e rest
  | _ -> e :: xs

// the fast path, once per line: s + ofEntry e without building ofEntry e (PropertyTests checks
// the two agree). Most requests aren't among the slowest, and leave that list alone.
let addEntry (s: Stats) (e: Entry) =
  let slow = List.length s.slowest < keep || e.ms > (List.item (keep - 1) s.slowest).ms
  { s with
      lines = s.lines + 1
      levels = bump (levelName e.level) 1 s.levels
      routes = bump (routeName e) (routeOf e) s.routes
      slowest = if slow then List.take keep (insert e s.slowest) else s.slowest }

let addBad (s: Stats) (b: Bad) = { s with bad = List.append s.bad [ b ] }
