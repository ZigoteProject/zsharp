/// A host executable's build by module (0007), the F# compiler's Driver.compileUnits and
/// linkParts: each source file of the program is an LLVM module of its own functions (its
/// non-generic ones, which the others call), with a copy of each library function and instance of
/// a generic one they use, so LLVM inlines within a module as it would in one big one. Nothing of
/// another module's code is in it but what that module's ABI says of its functions (their types
/// after uncurrying, the parameters they borrow, what they reach that threads can't share). So a
/// module's code is made from its checked result, the library's, the generic functions it copies
/// and the ABIs of what it calls; a key of those (its world) finds its object, and a build makes
/// again only the modules for which one of them changed, monomorphization through code
/// generation. The objects are compiled in parallel, from the cache when it has them, and linked
/// (with ThinLTO in a release build, when lld is there).
open Types.Ty
open Core.Program

/// A function of a module as the others call it: its parameters' types and its result's after
/// uncurrying, the parameters it borrows, and what it reaches that threads can't share.
[<Derive(Binary)>]
type AbiFun = { aname: string; apars: list<Ty>; aret: Ty; borrowed: list<int>; reach: option<string * list<string> * Ty> }

/// What a module's code was made from, as the module cache keeps it: the modules it depends on and
/// how (another module's checked result, for the generic functions it copied from it, or its ABI,
/// for the functions it calls), its own functions' ABI, and what its code needs of the runtime
/// (weak references, wide vectors, threads).
[<Derive(Binary)>]
type World = { deps: list<string * string * string>; abi: list<AbiFun>; facts: list<string> }

/// A module of the program: its object from the module cache, or its LLVM IR and key.
type Part =
  | Cached of string
  | Fresh of string * string

/// A module made this build: its functions after reference counting, and the other modules' it
/// calls (their ABI).
type private Made = { mfuns: list<MFun>; calls: list<AbiFun> }

// a module's world in the cache, under a key of its checked result and the library's
let private worldFile (pre: string) = Path.combine (Path.combine (Tools.cacheRoot ()) "worlds") (pre + ".bin")

let private loadWorld (pre: string) : option<World> =
  if not (Tools.cacheOn ()) then
    None
  else
    match File.readAllBytes (worldFile pre) with
    | Ok bytes ->
      let read : result<World, string> = Binary.ofBytes bytes
      match read with
      | Ok w ->
        File.touch (worldFile pre) |> ignore
        Some w
      | Error _ -> None
    | Error _ -> None

let private saveWorld (pre: string) (w: World) =
  if Tools.cacheOn () then
    Tools.writeWhole (worldFile pre) (Binary.toBytes w)

// whether a function waits (a task's state machine)
let rec private waits (e: Core.Ir.CExpr) : bool =
  match e.k with
  | Core.Ir.CPrim(op, _) -> op = "task.suspend" || op = "task.abandon" || List.exists waits (Core.Ir.children e.k)
  | k -> List.exists waits (Core.Ir.children k)

// the functions an expression names: calls, closures, globals, and those in a vtable
let private refs (e: Core.Ir.CExpr) : list<string> =
  let acc = Buffer.empty
  let rec walk (e: Core.Ir.CExpr) =
    match e.k with
    | Core.Ir.CGlobal(g, _) -> Buffer.push g acc
    | Core.Ir.CCallDirect(g, _) -> Buffer.push g acc
    | Core.Ir.CMkClosure(g, _) -> Buffer.push g acc
    | Core.Ir.CPrim(op, _) when String.startsWith "fn:" op -> Buffer.push (String.sub op 3 (String.length op - 3)) acc
    | _ -> ()
    for c in Core.Ir.children e.k do
      walk c
  walk e
  Array.toList (Buffer.toArray acc)

// runs f, its milliseconds kept for --time
let private timedInto (lines: Buffer<string * float>) (name: string) (f: unit -> 'a / 'e) : 'a / 'e =
  let sw = Diagnostics.Stopwatch.startNew ()
  let r = f ()
  Buffer.push (name, float (int sw.ElapsedNanoseconds) / 1000000.0) lines
  r

// f x, timed: x is given to f (a closure holding it instead would keep a reference, and what f
// moves to other threads would cross shared)
let private timedOn (lines: Buffer<string * float>) (name: string) (f: 'a -> 'b / 'e) (x: 'a) : 'b / 'e =
  let sw = Diagnostics.Stopwatch.startNew ()
  let r = f x
  Buffer.push (name, float (int sw.ElapsedNanoseconds) / 1000000.0) lines
  r

/// What the split build left: its parts (in order: each program module's own functions, then its
/// copies; or the one module of a program of one file), the settings its code was made with (for
/// the runtime) and the lines --time shows.
type Built = { parts: list<Part>; checkedHeap: bool; wideVectors: bool; threaded: bool; lines: list<string * float> }

/// The program's modules: each one's object from the module cache (`cached`, by key), or its LLVM
/// IR, made for the modules a change reached. A program of one file is one module.
let parts (o: Options.Options) (c: Check.Checked) (testBuild: bool) (cached: string -> option<string> / <>) : result<Built, PassError> / Stops =
  let prog = Opt.Mono.lowered (Check.tablesOf c)
  let units = Array.ofList c.units
  let lib = List.filter (fun (u: Check.Unit) -> u.library) c.units
  let mods = Array.ofList (List.filter (fun (u: Check.Unit) -> not u.library) c.units)
  let mainUnit = mods.[Array.length mods - 1]
  let keyOf = Map.ofList (List.map (fun (u: Check.Unit) -> (u.file, u.key)) c.units)
  let libKey = Tools.hashOf ("library" :: List.map (fun (u: Check.Unit) -> u.key) lib)
  let decide = Option.isNone (Environment.getVariable "ZS_NO_DECIDE")
  let simple = Option.isSome (Environment.getVariable "ZS_NO_SIMPLIFY") || o.debugInfo
  // the settings a module's code is made with (its object's are in its key)
  let settings = $"{o.debugInfo} {testBuild} {decide}"
  let compiler = Tools.compilerId ()
  // which module defines each function, and a module's own functions: its non-generic ones (in a
  // test build, not main)
  let declaredIn = ref Map.empty
  let owner = ref Map.empty
  for u in units do
    for (n, ngen) in u.names do
      declaredIn.Value <- Map.add n u declaredIn.Value
      if not u.library && ngen = 0 && not (testBuild && n = "main") then
        owner.Value <- Map.add n u.file owner.Value
  // a lifted lambda or local function goes with the function it's in
  let root (name: string) : string / <> =
    let i = String.indexOfFrom name "$" 1
    if i < 0 then name else String.sub name 0 i
  let owners = owner.Value
  let unitOf (name: string) : option<string> / <> = Map.tryFind (root name) owners
  let ownOf (u: Check.Unit) = List.choose (fun (n, ngen) -> if Map.containsKey n owner.Value && ngen = 0 then Some n else None) u.names
  // the main module also starts the library's values
  let isLibraryFun (i: string) =
    match Map.tryFind i declaredIn.Value with
    | Some u -> u.library
    | None -> false
  let libraryInits = List.filter isLibraryFun (List.map snd prog.values)
  let seeds (u: Check.Unit) = List.append (ownOf u) (if u.file = mainUnit.file then libraryInits else [])
  // the checked Core of a function, its module's read the first time one of them is needed
  let defs = ref Map.empty
  let read = ref Set.empty
  let defOf (name: string) : Core.Ir.FunDef =
    match Map.tryFind name defs.Value with
    | Some f -> f
    | None ->
      let u = Map.find name declaredIn.Value
      if not (Set.contains u.file read.Value) then
        read.Value <- Set.add u.file read.Value
        for f in u.funs () do
          defs.Value <- Map.add f.name (Check.settle c.cx f) defs.Value
      Map.find name defs.Value
  let pre (u: Check.Unit) = Tools.hashOf [ "world"; compiler; settings; u.file; u.key; libKey ]
  let worlds = ref Map.empty
  let abiHash = ref Map.empty
  let abiFun = ref Map.empty
  let made = ref Map.empty
  let types = ref prog.types
  let accept (u: Check.Unit) (w: World) =
    worlds.Value <- Map.add u.file w worlds.Value
    abiHash.Value <- Map.add u.file (Xxhash.hex (Binary.toBytes w.abi)) abiHash.Value
    for f in w.abi do
      abiFun.Value <- Map.add f.aname f abiFun.Value
  let fixedNames = Set.ofList ("main" :: List.append prog.tests (List.map (fun (e: Core.Ir.Export) -> e.fname) prog.exports))
  // [<Target>] and [<Multiversion>] functions stay whole: their code is for features their callers
  // may not have
  let kept (n: string) = Map.containsKey (Core.Ir.baseFunName n) prog.targets
  let timedLines = Buffer.empty
  // makes the code of these modules: one run of the passes over their own functions and the copies
  // they need, the other modules' functions known by their ABI
  let make (these: list<Check.Unit>) : unit / Stops =
    let mine = Set.ofList (List.map (fun (u: Check.Unit) -> u.file) these)
    let external (g: string) =
      match Map.tryFind g owner.Value with
      | Some f -> not (Set.contains f mine)
      | None -> false
    let roots = List.collect seeds these
    let reachOf (g: string) : option<string * list<string> * Ty> =
      match Map.tryFind g abiFun.Value with
      | Some a -> a.reach
      | None -> None
    let check (pass: string) (funs: list<MFun>) = Compile.checkedAfter o.checkIr pass funs
    let monomorphic = timedInto timedLines "monomorphize" (fun () -> Opt.Mono.runFrom prog defOf roots external)
    let (reach, _) = Opt.Mono.reaching prog monomorphic reachOf
    let mono0 = check "monomorphize" (timedInto timedLines "monomorphize" (fun () -> Opt.Mono.fuse (Opt.Mono.checkSharedWith prog reachOf monomorphic)))
    // what each function monomorphization made refers to (what a module's code was made from is
    // what it copied, before inlining hid some of it); the functions themselves go here, so the
    // passes' jobs own theirs (a function something else held would cross shared)
    let monoRefs = Map.ofList (List.map (fun (f: MFun) -> (f.name, refs f.body)) monomorphic)
    let mayInline (caller: string) (g: string) =
      match unitOf g with
      | None -> true
      | u -> unitOf caller = u
    let mono1 = check "inline" (if o.debugInfo then mono0 else timedInto timedLines "inline" (fun () -> Opt.Inline.runWith kept mayInline (Opt.Inline.uncurry fixedNames mono0)))
    let mono2 = check "simplify" (timedOn timedLines "simplify" (fun (fs: list<MFun>) -> if simple then fs else Opt.Simplify.run types.Value fs) mono1)
    let (lowered, mono3a) = timedInto timedLines "effects" (fun () -> Opt.Evidence.run types.Value prog.effects mono2)
    let mono3 = check "effects" mono3a
    types.Value <- lowered
    let mono4 = check "decision trees" (timedOn timedLines "decision trees" (fun (fs: list<MFun>) -> if decide then Opt.Decide.run types.Value fs else fs) mono3)
    // the other modules' ABIs, as the jobs read them
    let abis = abiFun.Value
    let arityOf (g: string) : option<int> / <> =
      match Map.tryFind g abis with
      | Some a -> Some(List.length a.apars)
      | None -> None
    let lifted = check "lift closures" (timedOn timedLines "lift closures" (Opt.Lift.runWith arityOf true) mono4)
    // a task's state machine owns its parameters: they live in its coroutine frame past the call
    // that starts it
    let machines = Set.ofList (List.map (fun (f: MFun) -> f.name) (List.filter (fun (f: MFun) -> waits f.body) lifted))
    let borrowedOf (g: string) : option<Set<int>> / <> =
      match Map.tryFind g abis with
      | Some a -> Some(Set.ofList a.borrowed)
      | None -> None
    let borrowed = timedInto timedLines "borrowed parameters" (fun () -> Opt.Rc.borrowingWith types.Value (Set.union fixedNames machines) borrowedOf lifted)
    let byName = Map.ofList (List.map (fun (f: MFun) -> (f.name, f)) lifted)
    // what each function refers to, found once, however many modules reach it
    let liftedRefs = Map.ofList (List.map (fun (f: MFun) -> (f.name, refs f.body)) lifted)
    // each module's functions (its own and their lambdas), in one pass
    let byUnit =
      let add (m: Map<string, list<string>>) (f: MFun) =
        match unitOf f.name with
        | Some u -> Map.add u (f.name :: Option.defaultValue [] (Map.tryFind u m)) m
        | None -> m
      List.fold add Map.empty lifted
    // what a module's functions reach in a list of functions: those of its own and the copies
    // (shared ones), and the other modules' it calls
    let reached (unit: string) (start: list<string>) (refsOf: Map<string, list<string>>) : Set<string> * Set<string> =
      let inModule = ref Set.empty
      let others = ref Set.empty
      let queue = Buffer.empty
      let enqueue (n: string) =
        if not (Set.contains n inModule.Value) then
          inModule.Value <- Set.add n inModule.Value
          Buffer.push n queue
      for n in start do
        if Map.containsKey n refsOf then
          enqueue n
      let mutable i = 0
      while i < Buffer.length queue do
        let n = queue.[i]
        i <- i + 1
        for g in Map.find n refsOf do
          if Map.containsKey g refsOf then
            match unitOf g with
            | None -> enqueue g
            | Some u when u = unit -> enqueue g
            | Some _ -> others.Value <- Set.add g others.Value
          else if external g || Map.containsKey g abiFun.Value then
            others.Value <- Set.add g others.Value
      (inModule.Value, others.Value)
    for u in these do
      let ownNames = ownOf u
      let start = Option.defaultValue [] (Map.tryFind u.file byUnit)
      let (funsHere, others) = reached u.file (List.append start (seeds u)) liftedRefs
      // its ABI: its own functions as the others call them
      let abiOf (n: string) : AbiFun =
        let f = Map.find n byName
        let b =
          match Map.tryFind n borrowed with
          | Some s -> Set.toList s
          | None -> []
        { aname = n; apars = List.map snd f.pars; aret = f.ret; borrowed = b; reach = reach n }
      let abi = List.map abiOf ownNames
      // what it was made from: the generic functions it copied (before inlining, so those inlined
      // count), and the other modules it calls
      let (copied, _) = reached u.file (seeds u) monoRefs
      let checkOf (n: string) : option<string> =
        match unitOf n with
        | None ->
          match Map.tryFind (Core.Ir.baseFunName n) declaredIn.Value with
          | Some d when not d.library && d.file <> u.file -> Some d.file
          | _ -> None
        | _ -> None
      let checks = List.distinct (List.choose checkOf (Set.toList copied))
      let calls = List.distinct (List.filter (fun f -> f <> u.file) (List.choose unitOf (Set.toList others)))
      // by name: the order the run made them in depends on what else it made
      let funs = List.map (fun (n: string) -> Map.find n byName) (Set.toList funsHere)
      let facts =
        List.filter (fun x -> x <> "") [ (if Compile.usesPrim Compile.heapPrims funs then "weak" else ""); (if Compile.wideVectors funs then "wide" else ""); (if Compile.threaded prog.externs funs || List.exists (fun (e: Core.Ir.Export) -> e.interrupt) prog.exports then "threads" else "") ]
      let deps = List.append (List.map (fun d -> (d, "check", Map.find d keyOf)) (List.sort checks)) (List.map (fun d -> (d, "abi", "")) (List.sort calls))
      let w : World = { deps = deps; abi = abi; facts = facts }
      made.Value <- Map.add u.file { mfuns = funs; calls = [] } made.Value
      worlds.Value <- Map.add u.file w worlds.Value
    // the ABIs, now that all of these modules have one; then each one's dependencies on the
    // others' ABIs, and its code with reference counting
    for u in these do
      accept u (Map.find u.file worlds.Value)
    let counting = Buffer.empty
    for u in these do
      let w0 = Map.find u.file worlds.Value
      let deps = List.map (fun (d, kind, h) -> if kind = "abi" then (d, kind, Map.find d abiHash.Value) else (d, kind, h)) w0.deps
      let w = { w0 with deps = deps }
      worlds.Value <- Map.add u.file w worlds.Value
      saveWorld (pre u) w
      let m = Map.find u.file made.Value
      let defined = Set.ofList (List.map (fun (f: MFun) -> f.name) m.mfuns)
      let externals = ref Set.empty
      for f in m.mfuns do
        for g in Map.find f.name liftedRefs do
          if not (Set.contains g defined) && Map.containsKey g abiFun.Value then
            externals.Value <- Set.add g externals.Value
      // reference counting with the parameters each callee borrows, this module's own and the
      // others'
      let all = List.fold (fun acc g -> Map.add g (Set.ofList (Map.find g abiFun.Value).borrowed) acc) borrowed (Set.toList externals.Value)
      Buffer.push (u, Set.toList externals.Value, all) counting
    // the modules' code counted on the pool, moved into the jobs: taken out of made first
    let input (p: Check.Unit * list<string> * Map<string, Set<int>>) =
      let (u, _, all) = p
      (all, (Map.find u.file made.Value).mfuns)
    let inputs = Array.map input (Buffer.toArray counting)
    for k in 0 .. Buffer.length counting - 1 do
      let (u, _, _) = counting.[k]
      made.Value <- Map.remove u.file made.Value
    let typesNow = types.Value
    let count (p: Map<string, Set<int>> * list<MFun>) : list<MFun> / <> =
      let (all, mfuns) = p
      Opt.Rc.lower typesNow all mfuns
    let counted = timedOn timedLines "reference counting" (Array.Parallel.map count) inputs
    for k in 0 .. Buffer.length counting - 1 do
      let (u, externals, _) = counting.[k]
      let mine = check "reference counting" counted.[k]
      Compile.dumpAt "rc" mine
      made.Value <- Map.add u.file { mfuns = mine; calls = List.map (fun g -> Map.find g abiFun.Value) externals } made.Value
  // a module's code is current when what it was made from is: its checked result's key and the
  // library's (in its key), the generic functions it copied, and the ABIs of the modules it calls;
  // those come before it, so they're known in order. One made now may change an ABI a later one
  // was made with: it's made then too.
  let mutable pending = Array.toList mods
  while not (List.isEmpty pending) do
    let todo = Buffer.empty
    let later = Buffer.empty
    let inRound (f: string) = Array.exists (fun (t: Check.Unit) -> t.file = f) (Buffer.toArray todo) || Array.exists (fun (t: Check.Unit) -> t.file = f) (Buffer.toArray later)
    // made now, unless a module before it waits: it may call that one, whose ABI isn't known
    // until the next round
    let remake (u: Check.Unit) = if Buffer.length later > 0 then Buffer.push u later else Buffer.push u todo
    for u in pending do
      match loadWorld (pre u) with
      | Some w ->
        let state (dep: string * string * string) =
          let (d, kind, h) = dep
          if kind = "check" then
            if Map.tryFind d keyOf = Some h then 1 else 0
          else
            match Map.tryFind d abiHash.Value with
            | Some current -> if current = h then 1 else 0
            | None -> if inRound d then 2 else 0
        let states = List.map state w.deps
        if List.contains 0 states then remake u
        else if List.contains 2 states then Buffer.push u later
        else accept u w
      | None -> remake u
    if Buffer.length todo > 0 then
      make (Array.toList (Buffer.toArray todo))
    pending <- Array.toList (Buffer.toArray later)
  // the runtime's settings, from every module's code
  let allFacts = List.collect (fun (p: string * World) -> (snd p).facts) (Map.toList worlds.Value)
  let checkedHeap = List.contains "weak" allFacts
  let wideVectors = List.contains "wide" allFacts
  let threaded = List.contains "threads" allFacts
  let level = Options.optLevel o
  // a module's object: under a key of its world, and of what code generation adds
  let objectKey (u: Check.Unit) =
    let w = Map.find u.file worlds.Value
    let settled = $"{level = "-Os"} {checkedHeap} {wideVectors} {threaded} {o.target} {o.cpu} {Array.length mods}"
    Tools.hashOf (List.append [ "module"; pre u; settled ] (List.map (fun (d, kind, h) -> d + " " + kind + " " + h) w.deps))
  // a module of a program of several files is two LLVM modules: its own functions, and its copies
  // of library functions and generic instances, which change only when the copies it needs do
  // (so a change to its code compiles only its own again); a program of one file is one module
  let kinds = if Array.length mods = 1 then [ "whole" ] else [ "own"; "copies" ]
  let partsOf = Array.ofList (List.collect (fun (u: Check.Unit) -> List.map (fun k -> (u, k)) kinds) (Array.toList mods))
  let keys = Array.map (fun (p: Check.Unit * string) -> Tools.hashOf [ objectKey (fst p); snd p ]) partsOf
  let found = Array.map cached keys
  let missing = ref []
  for i in 0 .. Array.length partsOf - 1 do
    let (u, _) = partsOf.[i]
    if Option.isNone found.[i] && not (Map.containsKey u.file made.Value) && not (List.exists (fun (x: Check.Unit) -> x.file = u.file) missing.Value) then
      missing.Value <- List.append missing.Value [ u ]
  // current, but its object is gone (or made with other settings): made again
  if not (List.isEmpty missing.Value) then
    make missing.Value
  let hits = Array.length (Array.filter Option.isSome found)
  Buffer.push ($"module cache ({hits} of {Array.length partsOf})", 0.0) timedLines
  let names = List.map (fun (u: Check.Unit) -> Path.getFileName u.file) (List.filter (fun (u: Check.Unit) -> Map.containsKey u.file made.Value) (Array.toList mods))
  Buffer.push ($"made ({(if List.isEmpty names then "none" else String.join " " names)})", 0.0) timedLines
  // a module is named after its source file (relative to the main one): what a profile calls its
  // internal functions, which must be the same in every build
  let mainFile = mainUnit.file
  let nameOf (file: string) : string / <> = Path.getRelativePath (Path.getDirectoryName (Path.getFullPath mainFile)) (Path.getFullPath file)
  let gopts : Gen.Emit.Options =
    { debugInfo = o.debugInfo
      optimized = level <> "-O0"
      optimizeSize = level = "-Os"
      target = o.target
      arch = Options.arch o
      checkedHeap = checkedHeap
      targets = prog.targets
      cpu = o.cpu
      wideVectors = wideVectors
      threaded = threaded }
  let stub (a: AbiFun) : MFun / <> =
    { name = a.aname
      pars = List.mapi (fun i t -> ($"a{i}", t)) a.apars
      ret = a.aret
      row = rowEmpty
      body = Core.Ir.mk Core.Ir.CUnit tUnit
      file = ""
      line = 0 }
  // the ABIs, as the jobs read them (the main module's entries)
  let abiNow = abiFun.Value
  // the types as bytes: each job reads a copy of its own (every job looks types up all the time,
  // and the counts of a table they shared would be atomic ones all the jobs wait on)
  let typesBytes = Binary.toBytes types.Value
  let dumpDir = Environment.getVariable "ZS_DUMP_IR"
  // what they read of the program: not its functions' Core, which isn't theirs to mark shared
  let (externs, exports, tests, values, clayouts) = (prog.externs, prog.exports, prog.tests, prog.values, prog.clayouts)
  // a part's IR, made by a job that owns what it walks (0020's *Crossings move*): the part's
  // file and kind (own, copies or whole), its module's own functions' names, the functions it
  // defines, the module's others by their signatures (it declares them) and the other modules'
  // it calls
  let compileOne (p: string * string * Set<string> * list<MFun> * list<MFun> * list<AbiFun>) : result<string, PassError> / <> =
    let (file, kind, own, defined, others, calls) = p
    let typesHere : Map<string, TypeInfo> =
      match Binary.ofBytes typesBytes with
      | Ok t -> t
      | Error e -> panic $"the types' copy: {e}"
    let part : option<Gen.Emit.Part> =
      if kind = "whole" then
        None
      else
        let p : Gen.Emit.Part = { defines = Set.ofList (List.map (fun (f: MFun) -> f.name) defined); called = own; entry = (kind = "own" && file = mainFile); copies = (kind = "copies"); file = Path.getFullPath file }
        Some p
    // the other modules' functions it calls, by their ABI; and the entry's: main, the tests,
    // exports and the values' initializers
    let stubs = List.map stub calls
    let have = ref (Set.ofList (List.map (fun (f: MFun) -> f.name) (List.concat [ defined; others; stubs ])))
    let entry (n: string) : option<MFun> =
      match Map.tryFind n abiNow with
      | Some a when not (Set.contains n have.Value) ->
        have.Value <- Set.add n have.Value
        Some(stub a)
      | _ -> None
    let entries = if file <> mainFile then [] else List.choose entry (List.append (Set.toList fixedNames) (List.map snd values))
    let name = if kind = "copies" then nameOf file + "#copies" else nameOf file
    // the functions it calls in the module's other part are declared, from its functions
    match Gen.Module.compile gopts typesHere externs exports tests values clayouts part (List.concat [ defined; others; stubs; entries ]) with
    | Ok(ir0, _) ->
      let ir = $"source_filename = \"{name}\"\n" + ir0
      match dumpDir with
      | Some dir -> File.writeAllText (Path.combine dir (String.replace name "/" "_" + ".ll")) ir |> ignore
      | None -> ()
      Ok ir
    | Error(line, msg) -> Error { file = file; line = line; message = msg }
  let sw = Diagnostics.Stopwatch.startNew ()
  // the parts the cache doesn't have, each one's IR made on the pool (decision 76): a job reads
  // the tables above and makes its module's code on its own, so the bytes don't depend on the
  // workers
  let wanted = List.filter (fun i -> Option.isNone found.[i]) (List.init (Array.length partsOf) (fun i -> i))
  // a module's functions split between its parts: the ones a part defines, with their code, and
  // the others' signatures
  let signature (f: MFun) : MFun = { f with body = Core.Ir.mk Core.Ir.CUnit tUnit }
  let jobOf (i: int) =
    let (u, kind) = partsOf.[i]
    let m = Map.find u.file made.Value
    let mine (f: MFun) = kind = "whole" || (kind = "own") = (unitOf f.name = Some u.file)
    let (defined, others) = List.partition mine m.mfuns
    (u.file, kind, Set.ofList (ownOf u), defined, List.map signature others, m.calls)
  let jobs = Array.ofList (List.map jobOf wanted)
  // nothing else holds the modules' code now: it moves into the jobs, its counts plain
  made.Value <- Map.empty
  let irs = Array.Parallel.map compileOne jobs
  let rec compileAll (i: int) (j: int) (acc: list<Part>) : result<list<Part>, PassError> =
    if i = Array.length partsOf then
      Ok(List.rev acc)
    else
      match found.[i] with
      | Some obj -> compileAll (i + 1) j (Cached obj :: acc)
      | None ->
        match irs.[j] with
        | Ok ir -> compileAll (i + 1) (j + 1) (Fresh(ir, keys.[i]) :: acc)
        | Error e -> Error e
  let result = compileAll 0 0 []
  Buffer.push ("LLVM IR", float (int sw.ElapsedNanoseconds) / 1000000.0) timedLines
  match result with
  | Error e -> Error e
  | Ok ps -> Ok { parts = ps; checkedHeap = checkedHeap; wideVectors = wideVectors; threaded = threaded; lines = Array.toList (Buffer.toArray timedLines) }

// ---- objects and the link

// the cache's directories
let private objectsDir () = Path.combine (Tools.cacheRoot ()) "objects"

let private modulesDir () = Path.combine (Tools.cacheRoot ()) "modules"

// keeps a cache directory's n most recently used files with this extension
let private evict (dir: string) (ext: string) (n: int) =
  match Directory.list dir with
  | Ok names ->
    let files = List.filter (fun (f: string) -> String.endsWith ext f) names
    if List.length files > n then
      let timed (f: string) =
        let p = Path.combine dir f
        (Result.defaultValue DateTime.unixEpoch (File.modifiedAt p), p)
      let byAge = List.sortBy (fun (t, _) -> t) (List.map timed files)
      for (_, p) in List.take (List.length files - n) byAge do
        File.delete p |> ignore
  | Error _ -> ()

/// The flags for a profile, and what the object cache keys on (the profile's contents).
let private profileFlags (o: Options.Options) : list<string> * string =
  if o.profileGenerate then
    ([ "-fprofile-generate" ], "generate")
  else
    match o.profileUse with
    | Some p -> ([ "-fprofile-use=" + Path.getFullPath p ], Tools.hashOf [ "profile"; Result.defaultValue "" (File.readAllText p) ])
    | None -> ([], "")

/// Whether lld is there: ThinLTO for a release build, and a faster link for every build.
let private lld () = Tools.onPath "ld.lld"

/// ThinLTO in this build: a release one, with lld (ZS_NO_LTO=1: none).
let private useLto (o: Options.Options) = o.release && lld () && Option.isNone (Environment.getVariable "ZS_NO_LTO")

/// The clang flags of a host build's objects.
let objectFlags (o: Options.Options) : list<string> =
  List.concat [ [ Options.optLevel o ]; Compile.cpuFlags o; fst (profileFlags o); (if useLto o then [ "-flto=thin" ] else []); Options.sectionFlags o ]

/// Where the module cache keeps the object of a module's key, built with this build's flags.
let private moduleObject (o: Options.Options) (key: string) =
  Path.combine (modulesDir ()) (Tools.hashOf (key :: snd (profileFlags o) :: objectFlags o) + ".o")

/// The module cache's object for a module's key, when it has one.
let cachedModule (o: Options.Options) (key: string) : option<string> =
  let obj = moduleObject o key
  if Tools.cacheOn () && File.exists obj then
    File.touch obj |> ignore
    Some obj
  else
    None

// an object to have: from the cache when it has one for exactly its source and flags, else
// compiled from its input (the IR written to a file of its own, or the C file) and kept there
type private Job = { obj: string; input: string; written: bool; flags: list<string>; keep: option<string>; size: int }

/// Compiles the program's modules to objects in parallel (each one the caches haven't seen), the
/// runtime too and the C of the program's packages, and links them into the executable: Error with
/// the tool's message; the lines --time shows.
let link (o: Options.Options) (built: Built) (linked: Modules.Linked) : result<list<string * float>, string> =
  let flags = objectFlags o
  let (profile, profileKey) = profileFlags o
  let dir = objectsDir ()
  Tools.makeDirectory dir
  let sw = Diagnostics.Stopwatch.startNew ()
  // what an object is made from: its source's text and the flags
  let job (source: string) (cFile: option<string>) (fs: list<string>) (keep: option<string>) : Job =
    let key = Tools.hashOf (List.concat [ [ "object"; (if Option.isSome cFile then "true" else "false"); profileKey ]; fs; [ source ] ])
    let obj = Path.combine dir (key + ".o")
    // one there is recently used: kept longest
    if File.exists obj then
      File.touch obj |> ignore
    match cFile with
    | Some c -> { obj = obj; input = c; written = false; flags = fs; keep = keep; size = String.length source }
    | None ->
      if File.exists obj then
        { obj = obj; input = ""; written = false; flags = fs; keep = keep; size = String.length source }
      else
        let input = Path.combine dir (key + ".ll")
        File.writeAllText input source |> ignore
        { obj = obj; input = input; written = true; flags = fs; keep = keep; size = String.length source }
  // the runtime optimized in a debug build too (a program debugs its own code)
  let rt = Options.runtimeDir ()
  let rtFile = Path.combine rt "rt.c"
  let defines = List.append (if built.threaded then [ "-DZS_THREADS" ] else []) (if Option.isSome (Environment.getVariable "ZS_NO_POOL") then [ "-DZS_NO_POOL" ] else [])
  let rtFlags = List.append (if useLto o then flags else List.concat [ [ "-O2" ]; Compile.cpuFlags o; profile; Options.sectionFlags o ]) defines
  let runtime = job (Result.defaultValue "" (File.readAllText rtFile)) (Some rtFile) rtFlags None
  let ofPart (p: Part) : option<Job> =
    match p with
    | Cached _ -> None
    | Fresh(ir, key) -> Some(job ir None flags (Some key))
  // the C sources of [<Link>]s and [c] sections, cached as the runtime is, by their text and the
  // headers beside them (which they may include)
  let ofC (c: string) =
    let d = Path.getDirectoryName c
    let headers =
      match Directory.list d with
      | Ok names -> List.map (fun (h: string) -> Result.defaultValue "" (File.readAllText (Path.combine d h))) (List.filter (fun (h: string) -> String.endsWith ".h" h) names)
      | Error _ -> []
    job (String.join "\n" (Result.defaultValue "" (File.readAllText c) :: headers)) (Some c) (List.append flags linked.cflags) None
  let cSources = List.filter (fun (l: string) -> String.endsWith ".c" l) linked.links
  let jobs = List.concat [ [ runtime ]; List.choose ofPart built.parts; List.map ofC cSources ]
  // the biggest first: clang takes at least as long as its biggest job, which mustn't start last
  let fresh = List.sortBy (fun (j: Job) -> 0 - j.size) (List.filter (fun (j: Job) -> not (File.exists j.obj)) jobs)
  let unique (j: Job) = j.obj + "." + Path.getFileName (Result.defaultValue "tmp" (File.createTemp "zs-")) + ".o"
  let tmps = List.map unique fresh
  let cmds = List.map2 (fun (j: Job) (t: string) -> ("clang", List.concat [ j.flags; [ "-c"; "-Wno-override-module"; j.input; "-o"; t ] ])) fresh tmps
  let results = Tools.runMany cmds
  for (j, t) in List.zip fresh tmps do
    if File.exists t then
      File.move t j.obj |> ignore
    if j.written then
      File.delete j.input |> ignore
  // a module's object kept under its key for the next build
  for j in jobs do
    match j.keep with
    | Some key when Tools.cacheOn () && File.exists j.obj ->
      let path = moduleObject o key
      match File.readAllBytes j.obj with
      | Ok bytes -> Tools.writeWhole path bytes
      | Error _ -> ()
    | _ -> ()
  let all = List.length jobs + List.length (List.filter (fun (p: Part) -> match p with | Cached _ -> true | Fresh _ -> false) built.parts)
  let clangLine = ($"clang ({List.length fresh} of {all} new)", float (int sw.ElapsedNanoseconds) / 1000000.0)
  match List.tryPick (fun (r: result<unit, string>) -> match r with | Error e -> Some e | Ok () -> None) results with
  | Some e -> Error e
  | None ->
    evict dir ".o" 256
    evict (modulesDir ()) ".o" 256
    let partObjects = List.map (fun (p: Part) -> match p with | Cached obj -> obj | Fresh(_, key) -> (List.find (fun (j: Job) -> j.keep = Some key) jobs).obj) built.parts
    let files = List.concat [ [ runtime.obj ]; partObjects; List.map (fun (c: string) -> (ofC c).obj) cSources ]
    let libs = List.map (fun (l: string) -> if String.startsWith "-" l || String.contains "/" l then l else "-l" + l) (List.filter (fun (l: string) -> not (String.endsWith ".c" l)) linked.links)
    let ltoLink =
      if useLto o then
        // ld64.lld (macOS) names the ThinLTO cache its own way
        let cache = Path.combine (Tools.cacheRoot ()) "lto"
        [ "-fuse-ld=lld"; (if Tools.hostOs () = "macos" then "-Wl,-cache_path_lto," + cache else "-Wl,--thinlto-cache-dir=" + cache) ]
      else if lld () then [ "-fuse-ld=lld" ]
      else []
    let linkSw = Diagnostics.Stopwatch.startNew ()
    match Tools.run "clang" (List.concat [ flags; ltoLink; Options.unusedLinkFlags o; files; libs; [ "-o"; o.out; "-lm" ] ]) with
    | Error e -> Error e
    | Ok () -> Ok [ clangLine; ("link", float (int linkSw.ElapsedNanoseconds) / 1000000.0) ]
