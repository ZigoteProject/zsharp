/// A checked program built (the F# compiler's Driver.lift, lower and build): the passes after
/// checking (monomorphization with the share check and fusion, inlining, effects as evidence,
/// closure conversion and reference counting), code generation, and clang with the runtime.
// ponytail: one module, no cache, executables for the host (0007's cache, --lib and --target to
// come)
open Types.Ty
open Core.Program

/// ZS_DUMP_CORE=name (* for all): the Core of matching functions after reference counting, or
/// after the stage ZS_DUMP_STAGE names (mono, inline, simplify, effects, decide, lift), as the F#
/// compiler shows it.
let dumpAt (stage: string) (funs: list<MFun>) =
  let wanted =
    match Environment.getVariable "ZS_DUMP_STAGE" with
    | Some s -> if s = "" then "rc" else s
    | None -> "rc"
  match Environment.getVariable "ZS_DUMP_CORE" with
  | Some name ->
    if wanted = stage then
      let v = Types.Vars.make ()
      for f in funs do
        if name = "*" || String.contains name f.name then
          let pars = String.join ", " (List.map fst f.pars)
          eprintln $"{f.name}({pars}) =\n{Core.Ir.showCore (Types.Show.show v) 1 f.body}\n"
  | None -> ()

let private stage (name: string) (funs: list<MFun>) : list<MFun> =
  dumpAt name funs
  funs

/// After a pass: with --check-ir (ZS_CHECK_IR=1), the IR checked (Core.Check), a failure stopping
/// the build there as an internal error naming the pass and the function.
let checkedAfter (on: bool) (pass: string) (funs: list<MFun>) : list<MFun> / Stops =
  if on then
    match Core.Check.core pass true funs with
    | Some what -> Stops.stop { file = ""; line = 0; message = "internal error (--check-ir): " + what }
    | None -> funs
  else
    funs

/// A phase's milliseconds as zs build --time shows them.
let timeLine (name: string) (ms: float) : string = String.padRight 20 name + " " + String.padLeft 8 $"{ms:F1}" + " ms"

/// Runs a phase: with `on` (zs build --time), its milliseconds on standard error after it.
let timed (on: bool) (name: string) (f: unit -> 'a / 'e) : 'a / 'e =
  if on then
    let sw = Diagnostics.Stopwatch.startNew ()
    let r = f ()
    eprintln (timeLine name (float (int sw.ElapsedNanoseconds) / 1000000.0))
    r
  else
    f ()

// whether a function waits (a task's state machine)
let rec private waits (e: Core.Ir.CExpr) : bool =
  match e.k with
  | Core.Ir.CPrim(op, _) -> op = "task.suspend" || op = "task.abandon" || List.exists waits (Core.Ir.children e.k)
  | k -> List.exists waits (Core.Ir.children k)

// what must not touch the heap (0012), and why: the [<NoAlloc>] functions (every instance),
// interrupt handlers, Cpu.critical's bodies, and with --no-heap the program's entries
let private noAllocRoots (prog: Program) (funs: list<MFun>) (noHeap: bool) : list<string * string> =
  let marked = List.filter (fun (f: MFun) -> Map.tryFind (Core.Ir.baseFunName f.name) prog.targets = Some [ "noalloc" ]) funs
  let handlers = List.filter (fun (e: Core.Ir.Export) -> e.interrupt) prog.exports
  // a value whose initializer is a static object (0014 item 1) has no startup code to check
  let isStatic (vi: string * string) =
    let (v, init) = vi
    let placed = Map.containsKey v prog.placements
    List.exists (fun (f: MFun) -> f.name = init && (Core.Ir.staticInit f.body || (placed && Option.isSome (Core.Ir.placedInit f.body)))) funs
  let entries = if noHeap then "main" :: List.append (List.map snd (List.filter (fun vi -> not (isStatic vi)) prog.values)) (List.map (fun (e: Core.Ir.Export) -> e.fname) prog.exports) else []
  let present (n: string) = List.exists (fun (f: MFun) -> f.name = n) funs
  let byAttribute = List.map (fun (f: MFun) -> (f.name, "noalloc")) marked
  let byHandler = List.map (fun (e: Core.Ir.Export) -> (e.fname, "handler")) handlers
  let byCritical = List.map (fun n -> (n, "critical")) (Opt.NoAlloc.criticalBodies funs)
  let byNoHeap = List.map (fun n -> (n, "noheap")) (List.filter present entries)
  List.concat [ byAttribute; byHandler; byCritical; byNoHeap ]

/// What a bare-metal target can't run (0016): the library's function, its name as written and
/// why. Threads and file descriptors aren't on a chip; an interrupt controller isn't on
/// WebAssembly.
let unrunnable (m: Options.Mcu) : Map<string, string * string> =
  let hosted =
    [ ("Threading.Task.spawn", ("Task.spawn", $"needs a thread, and {m.name} has none: run the task on this loop with let!"))
      ("Threading.Task.blocking", ("Task.blocking", $"needs a helper thread, and {m.name} has none: call the function, or wait for its interrupt with Irq.wait"))
      ("Threading.Task.waitFor", ("Task.waitFor", $"needs file descriptors, and {m.name} has none")) ]
  let interrupts (f: string) = (f, (String.replace f "Threading." "", $"needs an interrupt controller, and {m.name} has none"))
  let lines = List.map interrupts [ "Irq.wait"; "Threading.Signal.create"; "Threading.Signal.set"; "Threading.Signal.wait" ]
  Map.ofList (if m.board = "" then List.append hosted lines else hosted)

// the first function the program reaches (from its entries) that the target can't run stops the
// build, at the call, naming the functions on the way; walked before inlining, which hides calls
let private reachable (cant: Map<string, string * string>) (roots: list<string>) (funs: list<MFun>) : unit / Stops =
  let byName = Map.ofList (List.map (fun (f: MFun) -> (f.name, f)) funs)
  let seen = ref Set.empty
  let rec inFun (chain: list<string>) (name: string) =
    if not (Set.contains name seen.Value) then
      seen.Value <- Set.add name seen.Value
      match Map.tryFind name byName with
      | Some f -> walk (Core.Ir.baseFunName name :: chain) f f.line f.body
      | None -> ()
  and walk (chain: list<string>) (f: MFun) (line: int) (e: Core.Ir.CExpr) =
    match e.k with
    | Core.Ir.CLine(l, a) -> walk chain f l a
    | Core.Ir.CGlobal(g, _) ->
      match Map.tryFind (Core.Ir.baseFunName g) cant with
      | Some(shown, why) ->
        let path = String.join " -> " (List.rev (shown :: chain))
        Stops.stop { file = f.file; line = line; message = $"{shown} {why} ({path})" }
      | None -> inFun chain g
    | k -> List.iter (walk chain f line) (Core.Ir.children k)
  List.iter (inFun []) roots

/// A checked program's functions monomorphic, closure-converted and reference counted, with the
/// program as the passes took it and the types they added (effects' frames); Error where a pass
/// can't go on. What must not touch the heap isn't checked (lower does it; the editor shows what
/// does). A debug build keeps every function whole (no inlining), so breakpoints on them hit.
/// cant: the functions the target can't run (unrunnable).
let counted (prog0: Program) (debugInfo: bool) (time: bool) (checkIr: bool) (cant: Map<string, string * string>) : result<Program * Map<string, TypeInfo> * list<MFun>, PassError> =
  let prog = Opt.Mono.lowered prog0
  // functions called from outside keep their signatures (main, the tests, C exports)
  let fixedNames = Set.ofList ("main" :: List.append prog.tests (List.map (fun (e: Core.Ir.Export) -> e.fname) prog.exports))
  // [<Target>] and [<Multiversion>] functions stay whole: their code is for features their
  // callers may not have
  let kept (n: string) = Map.containsKey (Core.Ir.baseFunName n) prog.targets
  let passes () : result<Program * Map<string, TypeInfo> * list<MFun>, PassError> / Stops =
    let check (pass: string) (funs: list<MFun>) = checkedAfter checkIr pass funs
    let mono = check "monomorphize" (stage "mono" (timed time "monomorphize" (fun () -> Opt.Mono.fuse (Opt.Mono.checkShared prog (Opt.Mono.run prog)))))
    if not (Map.isEmpty cant) then
      reachable cant (List.append (Set.toList fixedNames) (List.map snd prog.values)) mono
    let inlined = check "inline" (stage "inline" (timed time "inline" (fun () -> if debugInfo then mono else Opt.Inline.run kept (Opt.Inline.uncurry fixedNames mono))))
    // ZS_NO_SIMPLIFY=1: no simplification, to compare with the F# compiler's passes
    let simple = Option.isSome (Environment.getVariable "ZS_NO_SIMPLIFY") || debugInfo
    let simplified = check "simplify" (stage "simplify" (timed time "simplify" (fun () -> if simple then inlined else Opt.Simplify.run prog.types inlined)))
    let (types, lowered0) = timed time "effects" (fun () -> Opt.Evidence.run prog.types prog.effects simplified)
    let lowered = check "effects" lowered0
    // ZS_NO_DECIDE=1: matches as written, to compare with decision trees
    let decide = Option.isNone (Environment.getVariable "ZS_NO_DECIDE")
    let decided = check "decision trees" (stage "decide" (timed time "decision trees" (fun () -> if decide then Opt.Decide.run types (stage "effects" lowered) else stage "effects" lowered)))
    let lifted = check "lift closures" (stage "lift" (timed time "lift closures" (fun () -> Opt.Lift.run decided)))
    // a task's state machine owns its parameters: they live in its coroutine frame past the call
    // that starts it
    let machines = Set.ofList (List.map (fun (f: MFun) -> f.name) (List.filter (fun (f: MFun) -> waits f.body) lifted))
    let entries = Set.union fixedNames machines
    let rced = check "reference counting" (stage "rc" (timed time "reference counting" (fun () -> Opt.Rc.lower types (Opt.Rc.borrowing types entries lifted) lifted)))
    Ok(prog, types, rced)
  handle passes () with
  | Stops.stop e, _ -> Error e

/// counted, then what must not touch the heap checked (0012): the [<NoAlloc>] functions, the
/// interrupt handlers, Cpu.critical's bodies, and with noHeap (--no-heap) the whole program.
let lower (prog0: Program) (debugInfo: bool) (time: bool) (checkIr: bool) (noHeap: bool) (cant: Map<string, string * string>) : result<Map<string, TypeInfo> * list<MFun>, PassError> =
  match counted prog0 debugInfo time checkIr cant with
  | Error e -> Error e
  | Ok(prog, types, funs) ->
    let heapCheck () : result<Map<string, TypeInfo> * list<MFun>, PassError> / Stops =
      Opt.NoAlloc.check types funs (noAllocRoots prog funs noHeap)
      Ok(types, funs)
    handle heapCheck () with
    | Stops.stop e, _ -> Error e

// whether the program uses one of these primitives
let usesPrim (prims: Set<string>) (funs: list<MFun>) : bool =
  let rec uses (e: Core.Ir.CExpr) : bool =
    match e.k with
    | Core.Ir.CPrim(p, _) -> Set.contains p prims || List.exists uses (Core.Ir.children e.k)
    | k -> List.exists uses (Core.Ir.children k)
  List.exists (fun (f: MFun) -> uses f.body) funs

// --coverage: the functions of the covered files no entry reaches, by their lines, which the
// report then shows as never run (the reached ones count their own lines)
let coverageSeeds (defs: list<Core.Ir.FunDef>) (funs: list<MFun>) (root: string) : list<string * int> =
  let generated = Set.ofList (List.map (fun (f: MFun) -> Core.Ir.baseFunName f.name) funs)
  let seed (f: Core.Ir.FunDef) =
    if f.line > 0 && not (String.contains "$" f.name) && not (Set.contains f.name generated) && String.startsWith root (Path.getFullPath f.file) then Some(f.file, f.line) else None
  List.distinct (List.choose seed defs)

// the primitives of a program that has weak references or arenas (code generation's checkedHeap)
let heapPrims : Set<string> = Set.ofList [ "weak.new"; "arena.with" ]

// the primitives of a program that runs code on other threads: the thread pool, a task spawned or
// on Task.blocking's helper thread, values threads share
let private threadPrims : Set<string> = Set.ofList [ "par.fork"; "Loop.blocking"; "Loop.spawn"; "atomic.make"; "mutex.make"; "chan.make" ]

// whether C may call the C function's callback on any thread (a callback<share<F>> parameter)
let private anyThread (externs: Map<string, Core.Ir.ExternSig>) (n: string) : bool =
  let shareCallback (t: Ty) =
    match t with
    | TCon("callback", [ TCon("share", _) ]) -> true
    | _ -> false
  match Map.tryFind n externs with
  | Some s -> List.exists shareCallback s.pars
  | None -> false

// whether the program runs code on other threads (code generation's threaded)
let threaded (externs: Map<string, Core.Ir.ExternSig>) (funs: list<MFun>) : bool =
  let rec uses (e: Core.Ir.CExpr) : bool =
    match e.k with
    | Core.Ir.CPrim(p, _) when Set.contains p threadPrims -> true
    | Core.Ir.CExtern(n, _) when anyThread externs n -> true
    | k -> List.exists uses (Core.Ir.children k)
  List.exists (fun (f: MFun) -> uses f.body) funs

// whether a type has a SIMD vector anywhere in it: its arguments, its record's or union's fields
// (each type looked through once: a recursive one ends, and one many fields share isn't walked
// again for each)
let private hasVector (v: Types.Vars.Vars) (types: Map<string, TypeInfo>) (t0: Ty) : bool =
  let seen = ref Set.empty
  let rec go (t: Ty) : bool =
    if Set.contains t seen.Value then
      false
    else
      seen.Value <- Set.add t seen.Value
      match t with
      | TCon(n, _) when Option.isSome (vectorInfo n) -> true
      | TCon(n, args) ->
        let fields =
          match Map.tryFind n types with
          | Some { def = RecordDef fs } -> List.map snd fs
          | Some { def = CUnionDef fs } -> List.map snd fs
          | Some { def = UnionDef cs } -> List.collect snd cs
          | _ -> []
        List.exists go args || List.exists (fun ft -> go (Types.Norm.substGen v args ft)) fields
      | TTuple ts -> List.exists go ts
      | TFun(a, b, _) -> go a || go b
      | _ -> false
  go t0

// whether a value of the type, held as it is (in registers or on the stack, which LLVM aligns),
// puts a vector in a heap object (has: hasVector): a vector, a tuple, a record or a fixed array
// is a value whose parts are held as they are; a union may be a cell (a plain one too, when it's
// in one), and an array, list, ref, Buffer, option and the like hold their arguments in objects;
// a curried closure's stub keeps each argument but the last in a closure of its own
let rec private heapVector (v: Types.Vars.Vars) (types: Map<string, TypeInfo>) (has: Ty -> bool) (t: Ty) : bool =
  let inHeap = heapVector v types has
  match t with
  | TCon(n, []) when Option.isSome (vectorInfo n) -> false
  | TCon("fixed", [ el; _ ]) -> inHeap el
  | TCon(n, args) ->
    let value (fs: list<string * Ty>) = List.exists (fun (_, ft) -> inHeap (Types.Norm.substGen v args ft)) fs
    match Map.tryFind n types with
    | Some { def = RecordDef fs } -> value fs
    | Some { def = CUnionDef fs } -> value fs
    | _ -> has t
  | TTuple ts -> List.exists inHeap ts
  | TFun(a, b, _) ->
    let curried =
      match b with
      | TFun _ -> has a
      | _ -> false
    curried || inHeap a || inHeap b
  | _ -> false

/// Whether a program can put a SIMD vector in a heap object (code generation's wideVectors: its
/// objects come from zs_alloc_wide, 64-byte aligned, where the pool's are 8: LLVM loads a vector
/// field or element at its own alignment, 16 bytes or more). A vector that only lives in locals,
/// parameters and results doesn't count (Bytes.appendJsonString's U8x16 scan): the alignment
/// costs every allocation of the program the pool. Its objects: a value of a type that holds one
/// (heapVector), a closure capturing one or whose function keeps one between curried arguments,
/// and a dyn box (whose type doesn't show what it holds); a task's frame is always aligned.
let wideVectors (types: Map<string, TypeInfo>) (funs: list<MFun>) : bool =
  let v = Types.Vars.make ()
  // each type looked through once: the same few types are most expressions'
  let memo (f: Ty -> bool) : Ty -> bool =
    let seen = ref Map.empty
    fun (t: Ty) ->
      match Map.tryFind t seen.Value with
      | Some b -> b
      | None ->
        let b = f t
        seen.Value <- Map.add t b seen.Value
        b
  let has = memo (hasVector v types)
  let inHeap = memo (heapVector v types has)
  let byName = Map.ofList (List.map (fun (f: MFun) -> (f.name, f)) funs)
  // what a closure of f keeps: the values it captured, and its function's parameters but the last
  let kept (f: string) (args: list<Core.Ir.CExpr>) : list<Ty> =
    let pars =
      match Map.tryFind f byName with
      | Some fd -> List.map snd (List.take (max 0 (List.length fd.pars - 1)) fd.pars)
      | None -> []
    List.append (List.map (fun (a: Core.Ir.CExpr) -> a.ty) args) pars
  let rec inExpr (e: Core.Ir.CExpr) : bool =
    let here =
      match e.k with
      | Core.Ir.CMkClosure(f, args) -> List.exists has (kept f args)
      | Core.Ir.CPrim(op, x :: _) when String.startsWith "dyn.box:" op -> has x.ty
      | _ -> false
    here || inHeap e.ty || List.exists inExpr (Core.Ir.children e.k)
  List.exists (fun (f: MFun) -> inHeap f.ret || List.exists (fun (_, t) -> inHeap t) f.pars || inExpr f.body) funs

// whether a library gives C handles (Z# objects it holds: not strings, records or tuples, which
// cross as their bytes and fields), which a C host may use on any thread
let private exportsHandles (prog: Program) : bool =
  let v = Types.Vars.make ()
  let handleTy (t: Ty) : bool =
    if not (Types.Repr.needsRc v prog.types t) then
      false
    else
      match t with
      | TCon("string", _)
      | TTuple _ -> false
      | TCon(n, _) ->
        match Map.tryFind n prog.types with
        | Some { def = RecordDef _ } -> false
        | _ -> true
      | _ -> true
  List.exists (fun (e: Core.Ir.Export) -> handleTy e.ret || List.exists handleTy e.pars) prog.exports

// the processor --cpu names, as clang takes it: -march on x86-64, -mcpu elsewhere
let cpuFlags (o: Options.Options) : list<string> =
  let x86 = Options.arch o = "x86_64"
  match o.cpu with
  | Some c -> [ (if x86 then "-march=" else "-mcpu=") + c ]
  | None -> []

// what the link takes for the packages' [c] sections: their C flags (for the C sources among
// them), then the sources, libraries and files (a name is a library's)
let linkArgs (linked: Modules.Linked) : list<string> =
  List.append linked.cflags (List.map (fun (l: string) -> if String.startsWith "-" l || String.contains "/" l then l else "-l" + l) linked.links)

/// What stops a build after checking: a pass's error (at a line), or a tool's failure.
type Failure =
  | InPass of PassError
  | InTool of string

let private andThen (f: unit -> result<unit, string>) (r: result<unit, string>) : result<unit, string> =
  match r with
  | Ok () -> f ()
  | Error e -> Error e

let private readText (path: string) : string =
  match File.readAllText path with
  | Ok t -> t
  | Error _ -> ""

/// The program's LLVM IR after the passes (and, for --lib, its C header), with the program it's
/// of (a test build, zs test's, has the file's test entry for main) and whether it runs threads.
let generate (o: Options.Options) (prog0: Program) (testBuild: bool) : result<Program * string * string * bool, Failure> =
  let prog = if testBuild then { prog0 with funs = List.filter (fun (f: Core.Ir.FunDef) -> f.name <> "main") prog0.funs } else prog0
  match (if o.isLib then prog.values else []) with
  | (value, _) :: _ when String.contains ".$assert" value || String.startsWith "$assert" value ->
    Error(InPass { file = ""; line = 0; message = "a top-level assert whose condition isn't a constant is checked at startup, which a library doesn't have; assert on constants (sizeof<T> = 20), or check it in a function" })
  | (value, _) :: _ -> Error(InPass { file = ""; line = 0; message = $"top-level value '{value}' is computed at startup, which a library doesn't have; make it a constant or a function" })
  | [] ->
    let cant =
      match o.mcu with
      | Some m -> unrunnable m
      | None -> Map.empty
    // --coverage keeps the code as written, as -g does: every line of every reached function counts
    // -g at -O0 (its default) keeps the code as written, for stepping; with a level or --release
    // the optimizer runs and the lines stay (an inlined call's lines are its caller's frame's)
    match lower prog ((o.debugInfo && Options.optLevel o = "-O0") || o.coverage) o.time o.checkIr o.noHeap cant with
    | Error e -> Error(InPass e)
    | Ok(types, funs) ->
      // a library's handles may be used on any thread of its C host
      // an interrupt handler preempts the program as a thread does (0012)
      let threads = threaded prog.externs funs || (o.isLib && exportsHandles prog) || List.exists (fun (e: Core.Ir.Export) -> e.interrupt) prog.exports
      let level = Options.optLevel o
      let gopts : Gen.Emit.Options =
        { debugInfo = o.debugInfo
          coverageRoot = (if o.coverage then Path.getFullPath (Path.getDirectoryName (Path.getFullPath o.main)) else "")
          coverageSeeds = (if o.coverage then coverageSeeds prog.funs funs (Path.getFullPath (Path.getDirectoryName (Path.getFullPath o.main))) else [])
          optimized = level <> "-O0"
          optimizeSize = level = "-Os"
          target = o.target
          arch = Options.arch o
          checkedHeap = usesPrim heapPrims funs
          targets = prog.targets
          cpu = o.cpu
          wideVectors = wideVectors types funs
          threaded = threads }
      match timed o.time "LLVM IR" (fun () -> Gen.Module.compile gopts types prog.externs prog.exports prog.tests prog.values prog.clayouts prog.placements None funs) with
      | Error(line, msg) -> Error(InPass { file = ""; line = line; message = msg })
      | Ok(ir, header) -> Ok(prog, ir, header, threads)

/// The program built (one module): its LLVM IR (kept as out.ll with --emit-llvm), and clang with
/// the runtime, for the host, another target (zig cc links), a microcontroller, or as a library
/// with its C header.
let make (o: Options.Options) (prog0: Program) (linked: Modules.Linked) (testBuild: bool) : result<unit, Failure> =
  match generate o prog0 testBuild with
  | Error e -> Error e
  | Ok(prog, ir, header, threads) ->
    let level = Options.optLevel o
    let scratch = if o.emitLlvm then "" else Result.defaultValue "" (Directory.createTemp "zs-build-")
    let ll = if o.emitLlvm then Path.changeExtension o.out ".ll" else Path.combine scratch "program.ll"
    match File.writeAllText ll ir with
    | Error e -> Error(InTool e)
    | Ok () ->
      let rt = Options.runtimeDir ()
      let runtimeFile (name: string) = Path.combine rt name
      // ZS_NO_POOL: objects from malloc, one by one, for valgrind (a sanitized build has that too)
      let defines = List.append (if threads then [ "-DZS_THREADS" ] else []) (if Option.isSome (Environment.getVariable "ZS_NO_POOL") then [ "-DZS_NO_POOL" ] else [])
      let san =
        // zs fuzz: libFuzzer's coverage instrumentation and its runtime without a main (the test
        // binary's runner drives it), with the sanitizers; a panic aborts (ZS_FUZZ)
        if o.fuzz then [ "-fsanitize=address,undefined,fuzzer-no-link"; "-g"; "-DZS_NO_POOL"; "-DZS_FUZZ" ]
        else if not o.sanitize then []
        else if o.threadSanitizer then [ "-fsanitize=thread"; "-g"; "-DZS_NO_POOL" ]
        // AddressSanitizer sees each object
        else [ "-fsanitize=address,undefined"; "-g"; "-DZS_NO_POOL" ]
      // -g: unoptimized, so stepping follows the source
      let opt = if o.debugInfo then (if level = "-O0" then [ "-O0"; "-g" ] else List.concat [ [ level; "-g" ]; cpuFlags o ]) else level :: cpuFlags o
      let profile =
        if o.profileGenerate then [ "-fprofile-generate" ]
        else
          match o.profileUse with
          | Some file -> [ "-fprofile-use=" + Path.getFullPath file ]
          | None -> []
      // a cross build (--target): clang compiles the IR for the target, and zig cc compiles the
      // runtime and links against Zig's bundled libc (musl: a static binary, no sysroot needed)
      let cross = o.target <> ""
      let tclang = if cross then [ "--target=" + Options.clangTriple o ] else []
      // zig cc writes debug info unless told not to (clang doesn't): without -g, none, so the
      // binary doesn't carry its temporary files' paths and builds to the same bytes each time
      // (the C library's objects zig builds itself have it anyway, naming zig's cache: the link
      // drops it, -S to ld.lld and ld64.lld; on Windows -s, which writes no .pdb either)
      let nodebug = if o.debugInfo then [] else if String.contains "-windows" o.target then [ "-g0"; "-s" ] else [ "-g0"; "-Wl,-S" ]
      let cc (args: list<string>) = if cross then Tools.run "zig" (List.concat [ [ "cc"; "-target"; o.target ]; nodebug; args ]) else Tools.run "clang" args
      // zs fuzz: libFuzzer's runtime without its main (the runner drives it), which is C++
      let fuzzLink =
        if not o.fuzz then
          []
        else
          match Tools.runSplit "clang" [ "-print-file-name=libclang_rt.fuzzer_no_main.a" ] with
          | Ok r when String.contains "/" r.out -> [ String.trim r.out; "-lstdc++" ]
          | _ -> [ "-lstdc++" ]
      let built =
        match o.mcu with
        | Some m when o.isLib && (m.board <> "" || String.endsWith ".a" o.out) ->
          // a library a C program links (a chip's firmware, or one built for WebAssembly as an
          // archive): the program and the embedded runtime, a chip's with no startup (ZS_LIB),
          // archived, and the header; the C side has the vector table (or main) and the link
          let obj = Path.changeExtension ll ".o"
          let rto = Path.changeExtension ll ".rt.o"
          let flags = [ "-ffunction-sections"; "-fdata-sections" ]
          let r1 = timed o.time "clang" (fun () -> Tools.run "clang" (List.concat [ opt; [ "--target=" + m.triple ]; m.cflags; flags; [ "-c"; "-Wno-override-module"; ll; "-o"; obj ] ]))
          let r2 = andThen (fun () -> timed o.time "zig cc" (fun () -> Tools.run "zig" (List.concat [ [ "cc"; "-target"; m.zigTarget; "-mcpu=" + m.zigCpu ]; opt; flags; [ "-DZS_LIB"; $"-DZS_HEAP_SIZE={Option.defaultValue m.heap o.heap}"; $"-DZS_CLOCK_HZ={m.clock}"; "-c"; runtimeFile "rt-embedded.c"; "-o"; rto ] ]))) r1
          let archive () =
            File.delete o.out |> ignore
            Tools.run "llvm-ar" [ "rcs"; o.out; obj; rto ]
          let r3 = andThen archive r2
          File.writeAllText (Path.changeExtension o.out ".h") header |> ignore
          File.delete obj |> ignore
          File.delete rto |> ignore
          r3
        | Some m when m.board = "" ->
          // freestanding WebAssembly: the IR and the embedded runtime, linked with _start as the
          // entry (a library has none), and the C exports exported
          let obj = Path.changeExtension ll ".o"
          let entry = if o.isLib then [ "-Wl,--no-entry" ] else []
          let exports = List.map (fun (e: Core.Ir.Export) -> "-Wl,--export=" + e.cname) prog.exports
          let compiled = timed o.time "clang" (fun () -> Tools.run "clang" (List.concat [ opt; [ "--target=" + m.triple ]; Options.sectionFlags o; [ "-c"; "-Wno-override-module"; ll; "-o"; obj ] ]))
          let r = andThen (fun () -> timed o.time "zig cc" (fun () -> Tools.run "zig" (List.concat [ [ "cc"; "-target"; m.zigTarget ]; opt; Options.sectionFlags o; [ $"-DZS_HEAP_SIZE={Option.defaultValue m.heap o.heap}"; $"-DZS_CLOCK_HZ={m.clock}" ]; entry; exports; [ obj; runtimeFile "rt-embedded.c" ]; linkArgs linked; [ "-o"; o.out ] ]))) compiled
          File.delete obj |> ignore
          r
        | Some m ->
          // bare metal: the IR and the embedded runtime for the chip, linked for the board
          let obj = Path.changeExtension ll ".o"
          let flags = [ "-ffunction-sections"; "-fdata-sections" ]
          // the board's script with the shared Cortex-M layout spliced in (zig cc can't pass the
          // linker a search path for INCLUDE)
          let script = Path.changeExtension ll ".ld"
          let shared = readText (runtimeFile "boards/cortex-m.ld")
          File.writeAllText script (String.replace (readText (runtimeFile ("boards/" + m.board + ".ld"))) "INCLUDE cortex-m.ld" shared) |> ignore
          // the runtime as a separate object: as bitcode (measured in phase 9) it changes
          // nothing at -Os, and at -O2 costs flash for gains that aren't the runtime's
          let compiled = timed o.time "clang" (fun () -> Tools.run "clang" (List.concat [ opt; [ "--target=" + m.triple ]; m.cflags; flags; [ "-c"; "-Wno-override-module"; ll; "-o"; obj ] ]))
          // the vector table's device lines: the board's, in tens
          let lines =
            match Options.irqTable m with
            | Some(_, n, _) -> (n + 9) / 10 * 10
            | None -> 0
          // the image keeps its symbol table, which zig cc drops at -Os unless it writes debug
          // info (which isn't flashed): probe-rs finds the RTT block by its symbol, a debugger the
          // functions by theirs; and its entry, which a debugger's load jumps to
          let symbols = [ "-g"; "-Wl,--entry=Reset_Handler" ]
          let r = andThen (fun () -> timed o.time "zig cc" (fun () -> Tools.run "zig" (List.concat [ [ "cc"; "-target"; m.zigTarget; "-mcpu=" + m.zigCpu ]; opt; flags; symbols; [ $"-DZS_HEAP_SIZE={Option.defaultValue m.heap o.heap}"; $"-DZS_CLOCK_HZ={m.clock}"; $"-DZS_IRQ_COUNT={lines}"; (if o.noHeap then "-DZS_NO_HEAP" else "-DZS_HEAP"); (if m.rtt then "-DZS_RTT" else "-DZS_SEMIHOSTING"); "-T" + script; "-Wl,--gc-sections"; obj; runtimeFile "rt-embedded.c" ]; linkArgs linked; [ "-o"; o.out ] ]))) compiled
          File.delete obj |> ignore
          File.delete script |> ignore
          r
        | None ->
          if o.isLib then
            // objects for the program and the runtime, position-independent so they link into a
            // shared library too, archived (or, for a .so, linked as one), plus the header
            let obj = Path.changeExtension ll ".o"
            let rto = Path.changeExtension ll ".rt.o"
            let pic = [ "-fPIC" ]
            let r1 = Tools.run "clang" (List.concat [ opt; pic; tclang; [ "-c"; "-Wno-override-module" ]; san; [ ll; "-o"; obj ] ])
            let r2 = andThen (fun () -> cc (List.concat [ opt; pic; defines; [ "-c" ]; san; [ runtimeFile "rt.c"; "-o"; rto ] ])) r1
            let archive () =
              File.delete o.out |> ignore
              if String.endsWith ".so" o.out then cc (List.concat [ opt; [ "-shared" ]; san; [ obj; rto ]; linkArgs linked; [ "-o"; o.out; "-lm" ] ]) else Tools.run "llvm-ar" [ "rcs"; o.out; obj; rto ]
            let r3 = andThen archive r2
            File.writeAllText (Path.changeExtension o.out ".h") header |> ignore
            File.delete obj |> ignore
            File.delete rto |> ignore
            r3
          else if cross then
            let obj = Path.changeExtension ll ".o"
            let r1 = timed o.time "clang" (fun () -> Tools.run "clang" (List.concat [ opt; tclang; Options.sectionFlags o; [ "-c"; "-Wno-override-module" ]; san; [ ll; "-o"; obj ] ]))
            let r2 = andThen (fun () -> timed o.time "zig cc" (fun () -> cc (List.concat [ opt; defines; Options.sectionFlags o; Options.unusedLinkFlags o; [ obj; runtimeFile "rt.c" ]; linkArgs linked; [ "-o"; o.out; "-lm" ]; Options.systemLibs o; (if String.contains "-windows" o.target then [ runtimeFile "utf8.rc" ] else []) ]))) r1
            File.delete obj |> ignore
            r2
          else
            timed o.time "clang" (fun () -> Tools.run "clang" (List.concat [ opt; profile; defines; Options.sectionFlags o; Options.unusedLinkFlags o; [ "-Wno-override-module" ]; san; [ ll; runtimeFile "rt.c" ]; linkArgs linked; fuzzLink; [ "-o"; o.out; "-lm" ] ]))
      if not o.emitLlvm then
        File.delete ll |> ignore
        Directory.delete scratch |> ignore
      match built with
      | Ok () -> Ok ()
      | Error m -> Error(InTool m)
