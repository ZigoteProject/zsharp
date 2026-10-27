/// Code that must not touch the heap (0012, decision 42): `[<NoAlloc>]` functions, interrupt
/// handlers, `Cpu.critical`'s bodies, and with `--no-heap` the whole program. Checked on the Core
/// after reference counting, so a fused pipeline, an unboxed union or a borrowed parameter
/// passes: a site builds an object, reuses a cell only when it's unique, drops a reference that
/// may free, writes an array that may be copied first, or calls code the check can't see; a
/// function's verdict is its first site or the callee one is reached through, memoized over the
/// call graph, and the error names the chain. The same sites, all of them, are the editor's
/// allocation hints (0011, 0026).
open Types.Ty
open Core.Ir
open Core.Program

/// Where a function touches the heap: what's done, the functions on the way (the one checked
/// first), and the place.
type Site = { what: string; chain: list<string>; file: string; line: int }

/// What a site does to the heap.
type Verdict =
  /// builds an object
  | Allocates
  /// builds a cell in the place of one it took apart, when that one was unique (else allocates)
  | Reuses
  /// drops a reference, which may be the last
  | Frees
  /// writes an array, which is copied first when anything else holds it
  | Copies
  /// calls code the check can't see: a function value, an effect's handler
  | Unseen
  /// waits, which an interrupt handler can't
  | Waits

/// A place where a function's own code touches the heap (not a callee's): what it does, as an
/// error says it (builds a string) and as a hint does (with the object's case and bytes, the cell
/// it reuses), the local it's about ("" for none), and its line.
type Touch = { verdict: Verdict; what: string; note: string; subject: string; line: int }

// what a function does, in order: what its own code touches, the functions it calls (at a line),
// and the paths a branch takes (an if's, a match's arms), each on its own
type private Step =
  | Own of Touch
  | Calls of string * int
  | Paths of list<list<Step>>

// what a primitive makes, if it makes an object (or may: a Buffer's push grows it)
let private builds (op: string) (args: list<CExpr>) : option<string> =
  let ofString =
    match args with
    | [ a ] -> a.ty = tStr
    | _ -> false
  match op with
  // a string is its own text
  | "string" when ofString -> None
  | "string"
  | "format"
  | "String.ofCStr" -> Some "builds a string"
  | "Array.create"
  | "array.copy"
  | "array.update"
  | "array.set" -> Some "builds an array"
  | "array.lit" -> if List.isEmpty args then None else Some "builds an array"
  | "buffer.push"
  | "buffer.blit" -> Some "may grow a Buffer"
  | "ref" -> Some "makes a ref cell"
  | "atomic.make" -> Some "makes an Atomic"
  | "spsc.create" -> Some "makes an Spsc"
  | "chan.make" -> Some "makes a Channel"
  | "mutex.make" -> Some "makes a Mutex"
  | "weak.new" -> Some "makes a weak reference"
  | "arena.with" -> Some "opens an arena"
  | "par.fork" -> Some "starts parallel work"
  | "ptr.alloc" -> Some "allocates memory"
  | "ptr.free" -> Some "frees memory"
  | _ when String.startsWith "dyn.box:" op -> Some "boxes a dyn value"
  | _ ->
    // the runtime's functions that give an object
    match Map.tryFind op Gen.Emit.runtimePrims with
    | Some(_, "ptr", _) -> Some(if String.startsWith "String." op then "builds a string" else $"builds an object ({op})")
    | _ -> None

// what waits, or needs the event loop: never in an interrupt handler, which preempts the code
// it would wait for
let private waits (op: string) =
  String.startsWith "mutex." op || String.startsWith "chan." op || String.startsWith "par." op || String.startsWith "task." op || String.startsWith "Loop." op

// a function's name as written: no instantiations (List.fold<Tree,int>: List.fold), an operator's
// < kept (Ledger.<+): a <…> right after a name's letter, digit, _ or ' goes
let private shown (name: string) : string =
  let word (b: u8) = (b >= u8 97 && b <= u8 122) || (b >= u8 65 && b <= u8 90) || (b >= u8 48 && b <= u8 57) || b = u8 95 || b = u8 39
  let kept = Buffer.empty
  let mutable depth = 0
  let mutable from = 0
  for i in 0 .. String.length name - 1 do
    let b = String.byte name i
    if b = u8 60 && (depth > 0 || (i > 0 && word (String.byte name (i - 1)))) then
      if depth = 0 then
        Buffer.push (String.sub name from (i - from)) kept
      depth <- depth + 1
    else if b = u8 62 && depth > 0 then
      depth <- depth - 1
      if depth = 0 then
        from <- i + 1
  if depth = 0 then
    Buffer.push (String.sub name from (String.length name - from)) kept
  String.concat (Array.toList (Buffer.toArray kept))

// a local's name as written: Core's numbering (t.2, l.3.r1) gone
let private written (x: string) : string = List.head (String.split "." x)

// what a touch is about: a local as written, none for the compiler's own ($rc1)
let private subjectOf (x: string) : string = if String.startsWith "$" x then "" else written x

// what f does, in order: what its own code touches, each with its line, the calls it makes (a
// call's arguments before it) and its branches' paths. word: the target's machine word, in bytes,
// for the objects' sizes
let private stepsOf (v: Types.Vars.Vars) (types: Map<string, TypeInfo>) (word: int) (f: MFun) : list<Step> =
  let heap (t: Ty) = Types.Repr.needsRc v types t
  let show (t: Ty) = Types.Show.show v t
  let bytes (t: Ty) =
    match Types.Repr.layout v types word t with
    | Some(n, _) -> n
    | None -> 0
  // a cell as code generation lays it out: the header word, a 32-bit target's tag word, the
  // fields; with its case's name
  let cell (t: Ty) (tag: int) : string =
    let case =
      match Types.Vars.prune v t with
      | TCon(u, _) ->
        match Map.tryFind u types with
        | Some { def = UnionDef cs } -> shortName (fst (List.item tag cs))
        | _ -> ""
      | _ -> ""
    match Types.Repr.cellShape v types t tag with
    | Some(tagged, fields) ->
      let header = if tagged && word = 4 then [ tInt; tcon "i32" ] else [ tInt ]
      $"{case}, {bytes (TTuple(List.append header fields))} B"
    | None -> case
  // a drop's words: a local's name as written; a value the compiler holds, its type
  let dropping (x: string) (t: Ty) =
    if subjectOf x = "" then $"drops a {show t} it holds, which may free it" else $"drops '{written x}' : {show t}, which may free it; borrow it, or keep it alive in the caller"
  let out = ref Buffer.empty
  let own (verdict: Verdict) (what: string) (note: string) (subject: string) (line: int) =
    Buffer.push (Own { verdict = verdict; what = what; note = note; subject = subject; line = line }) out.Value
  // the paths of a branch, each run on its own
  let paths (each: list<unit -> unit>) =
    let outer = out.Value
    let one (run: unit -> unit) =
      let mine = Buffer.empty
      out.Value <- mine
      run ()
      Array.toList (Buffer.toArray mine)
    let ps = List.map one each
    out.Value <- outer
    Buffer.push (Paths ps) outer
  // statics: the locals holding objects that are never freed (literals, cases without fields, a
  // scrutinee matched to one); tokens: each reuse token's matched cell
  let rec go (line: int) (statics: Set<string>) (tokens: Map<string, string>) (e: CExpr) =
    let rest () = List.iter (go line statics tokens) (children e.k)
    match e.k with
    | CLine(l, a) -> go l statics tokens a
    | CLet(x, w, body) ->
      // a span over a reference dup'd for it: dropping it gives back that one, never the last
      let rec view (e: CExpr) =
        match e.k with
        | CPrim(op, [ { k = CDup(y, _, { k = CLocal z }) } ]) -> y = z && String.startsWith "span.of" op
        | CLine(_, a) -> view a
        | _ -> false
      let isStatic =
        match w.k with
        | CStr _
        | CCtor(_, _, []) -> true
        | CPrim("array.lit", []) -> true
        | _ -> view w
      go line statics tokens w
      go line (if isStatic then Set.add x statics else statics) tokens body
    | CIf(c, t, el) ->
      go line statics tokens c
      paths [ (fun () -> go line statics tokens t); (fun () -> go line statics tokens el) ]
    | CMatch(s, cases) ->
      go line statics tokens s
      let arm (c: CPat * option<CExpr> * CExpr) () =
        let (p, g, b) = c
        // a case without fields: there the scrutinee is that case's static cell, never freed
        let known =
          match (s.k, p) with
          | (CLocal x, CPCtor(_, _, [])) -> Set.add x statics
          | _ -> statics
        match g with
        | Some guard -> go line known tokens guard
        | None -> ()
        go line known tokens b
      paths (List.map arm cases)
    | CCtor(_, tag, _) when Option.isSome (Types.Repr.cellShape v types e.ty tag) ->
      let what = $"builds a cell of {show e.ty}"
      own Allocates what $"{what} ({cell e.ty tag})" "" line
      rest ()
    | CCtorAt(tok, _, tag, _) ->
      let x = subjectOf (Option.defaultValue "$" (Map.tryFind tok tokens))
      let place = if x = "" then "a matched cell's place when that one is unique" else $"{x}'s place when {x} is unique"
      own Reuses $"builds a cell of {show e.ty} (in a dropped one's place only when that was unique)" $"builds a cell of {show e.ty} in {place}, else a new one ({cell e.ty tag})" x line
      rest ()
    | CMkClosure(_, caps) when not (List.isEmpty caps) ->
      let named (c: CExpr) =
        match c.k with
        | CLocal x -> Some(written x)
        | _ -> None
      let names = List.choose named caps
      let env = TTuple(tInt :: tInt :: tInt :: List.map (fun (c: CExpr) -> c.ty) caps)
      let capturing = if List.isEmpty names then "" else " capturing " + String.join ", " names
      own Allocates "builds a closure" $"builds a closure{capturing} ({bytes env} B)" "" line
      rest ()
    | CBin _ when isConcat e ->
      // one string for the whole chain, as code generation joins its pieces; none for a piece
      // alone ("" + s is s)
      let filled (p: CExpr) =
        match p.k with
        | CStr "" -> false
        | _ -> true
      let pieces = concatPieces e
      if List.length (List.filter filled pieces) > 1 then
        own Allocates "builds a string" "builds a string" "" line
      List.iter (go line statics tokens) pieces
    | CPrim(op, args) ->
      if waits op then
        own Waits $"waits ({op}), which an interrupt handler can't: push to an Spsc, and let the program's loop do the rest" $"waits ({op})" "" line
      match builds op args with
      | Some what -> own (if op = "ptr.free" then Frees else Allocates) what what "" line
      | None -> ()
      rest ()
    | CDrop(x, t, _) when heap t && not (Set.contains x statics) ->
      let what = dropping x t
      own Frees what what (subjectOf x) line
      rest ()
    | CDropFields(x, t, _, keep, tok, _) ->
      // a niche's value is its field (option<string>'s Some s is s): kept, nothing goes
      let niche =
        match Types.Repr.unionRep v types t with
        | Types.Repr.Niche _ -> Set.contains 0 keep
        | _ -> false
      if heap t && not (Set.contains x statics) && not niche then
        let what = dropping x t
        own Frees what what (subjectOf x) line
      let held =
        match tok with
        | Some k -> Map.add k x tokens
        | None -> tokens
      List.iter (go line statics held) (children e.k)
    | CArraySet(x, _, _) ->
      let what = $"writes the array '{written x}', which is copied first when anything else holds it"
      own Copies what what (subjectOf x) line
      rest ()
    | CApplyClo _ ->
      own Unseen "calls a function value, whose code the check can't see" "calls a function value" "" line
      rest ()
    | CPerform _
    | CHandle _ ->
      own Unseen "performs an effect" "performs an effect" "" line
      rest ()
    | CCallDirect(g, args) ->
      List.iter (go line statics tokens) args
      Buffer.push (Calls(g, line)) out.Value
    | _ -> rest ()
  go f.line Set.empty Map.empty f.body
  Array.toList (Buffer.toArray out.Value)

/// Of several lists of touches (the paths through a line, a generic function's instances), the
/// most of each verdict any one has.
let most (lists: list<list<Touch>>) : list<Touch> =
  let ofVerdict (v: Verdict) =
    let pick (best: list<Touch>) (ts: list<Touch>) =
      let these = List.filter (fun (t: Touch) -> t.verdict = v) ts
      if List.length these > List.length best then these else best
    List.fold pick [] lists
  List.collect ofVerdict [ Allocates; Reuses; Copies; Frees; Unseen; Waits ]

/// What f's own code touches (not its callees'), by line: on each, what the path through f
/// touching most there does (an if's branches and a match's arms are paths, so a decision tree's
/// copies of one arm count once). word: the target's machine word, in bytes, which objects' sizes
/// are in.
let touches (types: Map<string, TypeInfo>) (word: int) (f: MFun) : Map<int, list<Touch>> =
  let add (acc: Map<int, list<Touch>>) (line: int) (ts: list<Touch>) =
    if List.isEmpty ts then acc else Map.add line (List.append (Option.defaultValue [] (Map.tryFind line acc)) ts) acc
  let rec worst (steps: list<Step>) : Map<int, list<Touch>> =
    let step (acc: Map<int, list<Touch>>) (s: Step) =
      match s with
      | Own t -> add acc t.line [ t ]
      | Calls _ -> acc
      | Paths ps ->
        let each = List.map worst ps
        let on (l: int) (m: Map<int, list<Touch>>) = Option.defaultValue [] (Map.tryFind l m)
        let lines = List.distinct (List.collect (fun (m: Map<int, list<Touch>>) -> List.map fst (Map.toList m)) each)
        List.fold (fun (a: Map<int, list<Touch>>) (l: int) -> add a l (most (List.map (on l) each))) acc lines
    List.fold step Map.empty steps
  worst (stepsOf (Types.Vars.make ()) types word f)

/// The first site under `root` (or Some for a waiting operation in a handler), checking callees
/// through `funs`.
let firstSite (types: Map<string, TypeInfo>) (funs: list<MFun>) (handler: bool) : string -> option<Site> / <> =
  let v = Types.Vars.make ()
  let byName = Map.ofList (List.map (fun (f: MFun) -> (f.name, f)) funs)
  let memo = ref Map.empty
  let visiting = ref Set.empty
  let rec verdict (name: string) : option<Site> =
    match Map.tryFind name memo.Value with
    | Some r -> r
    | None when Set.contains name visiting.Value -> None
    | None ->
      match Map.tryFind name byName with
      | Some f ->
        visiting.Value <- Set.add name visiting.Value
        let r = pick f (stepsOf v types 8 f)
        visiting.Value <- Set.remove name visiting.Value
        let r2 = Option.map (fun (s: Site) -> { s with chain = shown name :: s.chain }) r
        memo.Value <- Map.add name r2 memo.Value
        r2
      | None -> Some { what = $"calls {shown name}, whose code the check can't see"; chain = []; file = ""; line = 0 }
  // the first site of the steps, in order (a branch's paths one after the other)
  and pick (f: MFun) (steps: list<Step>) : option<Site> = List.tryPick (first f) steps
  and first (f: MFun) (s: Step) : option<Site> =
    match s with
    | Own t when t.verdict = Waits && not handler -> None
    | Own t -> Some { what = t.what; chain = []; file = f.file; line = t.line }
    | Calls(g, line) ->
      match verdict g with
      | Some s -> Some { s with file = (if s.file = "" then f.file else s.file); line = (if s.line = 0 then line else s.line) }
      | None -> None
    | Paths ps -> List.tryPick (pick f) ps
  verdict

/// The roots' checks: each a function and how it's marked ("noalloc", "handler", "critical",
/// "noheap"); the first violation stops the build, naming the chain.
let check (types: Map<string, TypeInfo>) (funs: list<MFun>) (roots: list<string * string>) : unit / Stops =
  let plain = firstSite types funs false
  let handlers = firstSite types funs true
  for (name, how) in roots do
    let site = if how = "handler" then handlers name else plain name
    match site with
    | Some s ->
      let chain = String.join " -> " s.chain
      let n = shown name
      let message =
        match how with
        | "handler" -> $"interrupt handler '{n}' must not touch the heap, but {chain} {s.what}"
        | "critical" -> $"Cpu.critical's body runs with interrupts masked and must not touch the heap, but it {s.what}"
        | "noheap" when String.startsWith "$init." n -> $"--no-heap: the top-level value '{String.sub n 6 (String.length n - 6)}' is computed at startup, and {s.what}: make it a constant, or compute it in a function"
        | "noheap" -> $"--no-heap: {chain} {s.what}"
        | _ -> $"{n} is [<NoAlloc>], but {chain} {s.what}"
      Stops.stop { file = s.file; line = s.line; message = message }
    | None -> ()

/// The bodies Cpu.critical runs: the functions its closures are made of.
let criticalBodies (funs: list<MFun>) : list<string> =
  let found = Buffer.empty
  let rec scan (e: CExpr) =
    match e.k with
    | CPrim("cpu.critical", [ { k = CMkClosure(n, _) } ]) -> Buffer.push n found
    | _ -> ()
    List.iter scan (children e.k)
  for f in funs do
    scan f.body
  Array.toList (Buffer.toArray found)
