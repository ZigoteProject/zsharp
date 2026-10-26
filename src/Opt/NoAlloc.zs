/// Code that must not touch the heap (0012, decision 42): `[<NoAlloc>]` functions, interrupt
/// handlers, `Cpu.critical`'s bodies, and with `--no-heap` the whole program. Checked on the Core
/// after reference counting, so a fused pipeline, an unboxed union or a borrowed parameter
/// passes: a site builds an object, reuses a cell only when it's unique, drops a reference that
/// may free, writes an array that may be copied first, or calls code the check can't see; a
/// function's verdict is its first site or the callee one is reached through, memoized over the
/// call graph, and the error names the chain.
open Types.Ty
open Core.Ir
open Core.Program

/// Where a function touches the heap: what's done, the functions on the way (the one checked
/// first), and the place.
type Site = { what: string; chain: list<string>; file: string; line: int }

// what a primitive makes, if it makes an object (or may: a Buffer's push grows it)
let private builds (op: string) (args: list<CExpr>) : option<string> =
  match op with
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

// a function's name as written: no instantiation, no module of a lambda's
let private shown (name: string) : string = List.head (String.split "<" name)

/// The first site under `root` (or Some for a waiting operation in a handler), checking callees
/// through `funs`.
let firstSite (types: Map<string, TypeInfo>) (funs: list<MFun>) (handler: bool) : string -> option<Site> / <> =
  let v = Types.Vars.make ()
  let byName = Map.ofList (List.map (fun (f: MFun) -> (f.name, f)) funs)
  let memo = ref Map.empty
  let visiting = ref Set.empty
  let heap (t: Ty) = Types.Repr.needsRc v types t
  let show (t: Ty) = Types.Show.show v t
  let rec verdict (name: string) : option<Site> =
    match Map.tryFind name memo.Value with
    | Some r -> r
    | None when Set.contains name visiting.Value -> None
    | None ->
      match Map.tryFind name byName with
      | Some f ->
        visiting.Value <- Set.add name visiting.Value
        let r = walk f f.line Set.empty f.body
        visiting.Value <- Set.remove name visiting.Value
        let r2 = Option.map (fun (s: Site) -> { s with chain = shown name :: s.chain }) r
        memo.Value <- Map.add name r2 memo.Value
        r2
      | None -> Some { what = $"calls {shown name}, whose code the check can't see"; chain = []; file = ""; line = 0 }
  // statics: the locals holding objects that are never freed (literals, cases without fields)
  and walk (f: MFun) (line: int) (statics: Set<string>) (e: CExpr) : option<Site> =
    let at (what: string) = Some { what = what; chain = []; file = f.file; line = line }
    let rest () = List.tryPick (walk f line statics) (children e.k)
    match e.k with
    | CLine(l, a) -> walk f l statics a
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
      match walk f line statics w with
      | Some s -> Some s
      | None -> walk f line (if isStatic then Set.add x statics else statics) body
    | CCtor(_, tag, _) when Option.isSome (Types.Repr.cellShape v types e.ty tag) -> at $"builds a cell of {show e.ty}"
    | CCtorAt _ -> at $"builds a cell of {show e.ty} (in a dropped one's place only when that was unique)"
    | CMkClosure(_, caps) when not (List.isEmpty caps) -> at "builds a closure"
    | CBin("+", a, _) when show a.ty = "string" -> at "builds a string"
    | CPrim(op, _) when handler && waits op -> at $"waits ({op}), which an interrupt handler can't: push to an Spsc, and let the program's loop do the rest"
    | CPrim(op, args) when Option.isSome (builds op args) -> at (Option.get (builds op args))
    | CDrop(x, t, _)
    | CDropFields(x, t, _, _, _, _) when heap t && not (Set.contains x statics) ->
      at $"drops '{x}' : {show t}, which may free it; borrow it, or keep it alive in the caller"
    | CArraySet(x, _, _) -> at $"writes the array '{x}', which is copied first when anything else holds it"
    | CApplyClo _ -> at "calls a function value, whose code the check can't see"
    | CPerform _
    | CHandle _ -> at "performs an effect"
    | CCallDirect(g, args) ->
      match List.tryPick (walk f line statics) args with
      | Some s -> Some s
      | None ->
        match verdict g with
        | Some s -> Some { s with file = (if s.file = "" then f.file else s.file); line = (if s.line = 0 then line else s.line) }
        | None -> None
    | _ -> rest ()
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
