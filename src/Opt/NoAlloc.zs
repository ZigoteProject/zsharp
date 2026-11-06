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

// a Buffer's element type (a Buffer is a ref to its storage cell from monomorphization on)
let private bufferElement (t: Ty) : option<Ty> =
  match t with
  | TCon("ref", [ TCon("$buffer", [ el ]) ]) -> Some el
  | _ -> None

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
  | "String.ofCStr"
  | "Udp.from"
  | "Dns.lookup" -> Some "builds a string"
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
  // a reference that's never the last: a top-level value's (read with a reference of its own, the
  // value keeping one until exit), or one to a local that's never freed
  let rec neverLast (statics: Set<string>) (e: CExpr) : bool =
    match e.k with
    | CLet(r, { k = CGlobalVal _ }, { k = CDup(y, _, { k = CLocal z }) }) -> y = r && z = r
    | CDup(y, _, { k = CLocal z }) -> y = z && Set.contains y statics
    | CLocal x -> Set.contains x statics
    | CLine(_, a) -> neverLast statics a
    | _ -> false
  // a value a primitive drops, which frees nothing only when that reference is provably not the
  // last: a dup of a variable that holds its own, a top-level value's, or one read out of a
  // container (a field, an element, a ref's value) that holds one too (where the container's own
  // last reference goes, its drop is reported). On every path of an if or a match; anything else
  // is taken as last. st: the locals within that are never the last (as statics), a value matched
  // from one giving its pattern's variables too
  let reads (op: string) = op = "array.get" || op = "array.get#b" || op = "ref.get" || op = "ref.get#b"
  let rec held (st: Set<string>) (b: CExpr) : bool =
    match b.k with
    | CDup(y, _, { k = CLocal z }) -> y = z
    | CLocal x -> Set.contains x st
    | CField _ -> true
    | CPrim(op, _) when reads op -> true
    | CLet(x, w, body) -> held (if held st w then Set.add x st else st) body
    // a path that panics gives nothing to drop
    | CPrim("panic", _) -> true
    | CLine(_, a)
    | CSeq(_, a)
    | CDrop(_, _, a)
    | CDropFields(_, _, _, _, _, a) -> held st a
    | CIf(_, t, f) -> held st t && held st f
    | CMatch(sc, cases) ->
      let fromHeld = held st sc
      let arm (c: CPat * option<CExpr> * CExpr) =
        let (p, _, body) = c
        held (if fromHeld then Set.union st (Set.ofList (List.map fst (patVars p))) else st) body
      List.forall arm cases
    | _ -> neverLast st b
  // the local an argument is, as written ("" for none, or the compiler's own)
  let named (a: CExpr) : string =
    match a.k with
    | CLocal x -> subjectOf x
    | CDup(y, _, { k = CLocal z }) when y = z -> subjectOf y
    | _ -> ""
  // a Buffer argument's elements, when they hold a reference count
  let heapElements (args: list<CExpr>) : option<Ty> =
    let elements (a: CExpr) =
      match bufferElement a.ty with
      | Some t when heap t -> Some t
      | _ -> None
    List.tryPick elements args
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
        | _ -> view w || neverLast statics w
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
    | CPrim(op, buf :: _) when (op = "array.set" || op = "array.set#b") && Option.isSome (bufferElement buf.ty) ->
      // a Buffer's element written in place: no new object, but the overwritten element is
      // dropped (it may be the last reference to it). The write borrows the Buffer (array.set#b);
      // one Rc couldn't lend is passed in and dropped by the write, which frees it only when the
      // write had its last reference: a local's, a call's result, a mutable moved in (a dup of a
      // variable or of a field is another reference, never the last)
      let el = Option.get (bufferElement buf.ty)
      if heap el then
        own Frees "overwrites a Buffer element, which drops the old one (it may be the last reference)" "drops the element it overwrites" "" line
      if op = "array.set" && heap buf.ty && not (neverLast statics buf) then
        // a Buffer the write doesn't borrow is dropped by it, which frees nothing only when that
        // reference is provably not the last (held). What the write may free, said by where the
        // Buffer came from
        let rec source (b: CExpr) : string =
          match b.k with
          | CLet(x, w, { k = CLocal y }) when x = y -> source w
          | CLine(_, a)
          | CLet(_, _, a)
          | CSeq(_, a) -> source a
          | CCallDirect _
          | CApplyClo _
          | CExtern _ -> "writes a Buffer a call gave and then drops it, which may free it"
          | CPrim("slot.take", [ { k = CLocal m } ]) -> $"moves the mutable '{written m}' into the write, which drops it and may free it"
          | CDropFields _ -> "writes a Buffer taken out of a value it frees, then drops the Buffer, which may free it"
          // the path that isn't held
          | CIf(_, t, f) -> source (if held statics t then f else t)
          | CMatch(_, cases) ->
            match List.tryFind (fun (_, _, body) -> not (held statics body)) cases with
            | Some(_, _, body) -> source body
            | None -> "writes a Buffer it then drops, whose last reference may be the write's, which may free it"
          | _ -> "writes a Buffer it then drops, whose last reference may be the write's, which may free it"
        if not (held statics buf) then
          match buf.k with
          | CLocal x ->
            let what = dropping x buf.ty
            own Frees what what (subjectOf x) line
          | _ ->
            let what = source buf
            own Frees what what "" line
      rest ()
    // what primitives drop, copy or build in their own code (Gen), none of it a node here
    | CPrim("ignore", [ a ]) when heap a.ty && not (held statics a) ->
      // the value discarded is dropped there
      let x = named a
      let what = if x = "" then $"drops the {show a.ty} it discards, which may free it" else $"drops '{x}' : {show a.ty}, which it discards, and may free it"
      own Frees what what x line
      rest ()
    | CPrim("ref.set", [ _; w ]) when heap w.ty ->
      own Frees "overwrites a ref's value, which drops the old one (it may be the last reference)" "drops the value it overwrites" "" line
      rest ()
    | CPrim(op, args) when (op = "buffer.truncate" || op = "buffer.removeLast") && Option.isSome (heapElements args) ->
      // the elements past the new end (and what a shared storage's cut left past it) are dropped
      let what = $"shortens a Buffer of {show (Option.get (heapElements args))}, which drops the elements past its end (each may be the last reference)"
      own Frees what "drops the elements it cuts" "" line
      rest ()
    | CPrim("vec.store", a :: _) ->
      // the array written is made unique first, as a.[i] <- v's is
      let x = named a
      let what = if x = "" then "writes an array, which is copied first when anything else holds it" else $"writes the array '{x}', which is copied first when anything else holds it"
      own Copies what what x line
      rest ()
    | CPrim("window.slice", _) when Option.isSome (bufferElement e.ty) ->
      // a Buffer's slice is a Buffer of its own over the same storage
      own Allocates "slices a Buffer, which builds a Buffer of its own" "builds a Buffer over the same storage" "" line
      rest ()
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
