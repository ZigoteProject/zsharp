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

/// A checked program's functions monomorphic, closure-converted and reference counted, with the
/// types the passes added (effects' frames); Error where a pass can't go on. A debug build keeps
/// every function whole (no inlining), so breakpoints on them hit.
let lower (prog0: Program) (debugInfo: bool) (time: bool) : result<Map<string, TypeInfo> * list<MFun>, PassError> =
  let prog = Opt.Mono.lowered prog0
  // functions called from outside keep their signatures (main, the tests, C exports)
  let fixedNames = Set.ofList ("main" :: List.append prog.tests (List.map (fun (e: Core.Ir.Export) -> e.fname) prog.exports))
  // [<Target>] and [<Multiversion>] functions stay whole: their code is for features their
  // callers may not have
  let kept (n: string) = Map.containsKey (Core.Ir.baseFunName n) prog.targets
  let passes () : result<Map<string, TypeInfo> * list<MFun>, PassError> / Stops =
    let mono = stage "mono" (timed time "monomorphize" (fun () -> Opt.Mono.fuse (Opt.Mono.checkShared prog (Opt.Mono.run prog))))
    let inlined = stage "inline" (timed time "inline" (fun () -> if debugInfo then mono else Opt.Inline.run kept (Opt.Inline.uncurry fixedNames mono)))
    // ZS_NO_SIMPLIFY=1: no simplification, to compare with the F# compiler's passes
    let simple = Option.isSome (Environment.getVariable "ZS_NO_SIMPLIFY") || debugInfo
    let simplified = stage "simplify" (timed time "simplify" (fun () -> if simple then inlined else Opt.Simplify.run prog.types inlined))
    let (types, lowered) = timed time "effects" (fun () -> Opt.Evidence.run prog.types prog.effects simplified)
    // ZS_NO_DECIDE=1: matches as written, to compare with decision trees
    let decide = Option.isNone (Environment.getVariable "ZS_NO_DECIDE")
    let decided = stage "decide" (timed time "decision trees" (fun () -> if decide then Opt.Decide.run types (stage "effects" lowered) else stage "effects" lowered))
    let lifted = stage "lift" (timed time "lift closures" (fun () -> Opt.Lift.run decided))
    // a task's state machine owns its parameters: they live in its coroutine frame past the call
    // that starts it
    let machines = Set.ofList (List.map (fun (f: MFun) -> f.name) (List.filter (fun (f: MFun) -> waits f.body) lifted))
    let entries = Set.union fixedNames machines
    let counted = stage "rc" (timed time "reference counting" (fun () -> Opt.Rc.lower types (Opt.Rc.borrowing types entries lifted) lifted))
    Ok(types, counted)
  handle passes () with
  | Stops.stop e, _ -> Error e

// whether the program uses one of these primitives
let usesPrim (prims: Set<string>) (funs: list<MFun>) : bool =
  let rec uses (e: Core.Ir.CExpr) : bool =
    match e.k with
    | Core.Ir.CPrim(p, _) -> Set.contains p prims || List.exists uses (Core.Ir.children e.k)
    | k -> List.exists uses (Core.Ir.children k)
  List.exists (fun (f: MFun) -> uses f.body) funs

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

// whether a type has a SIMD vector in it (code generation's wideVectors: objects 64-byte aligned)
let rec private wide (t: Ty) : bool =
  match t with
  | TCon(n, args) -> Option.isSome (vectorInfo n) || List.exists wide args
  | TTuple ts -> List.exists wide ts
  | TFun(a, b, _) -> wide a || wide b
  | _ -> false

let wideVectors (funs: list<MFun>) : bool =
  let rec inExpr (e: Core.Ir.CExpr) : bool = wide e.ty || List.exists inExpr (Core.Ir.children e.k)
  List.exists (fun (f: MFun) -> wide f.ret || List.exists (fun (_, t) -> wide t) f.pars || inExpr f.body) funs

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

/// The runtime's sources: $ZS_RUNTIME, else beside the compiler (an installed one), else the
/// runtime/ of the checkout the compiler was built in.
let runtimeDir () : string =
  match Environment.getVariable "ZS_RUNTIME" with
  | Some d -> d
  | None ->
    let dir = Path.getDirectoryName (Tools.selfPath ())
    if File.exists (Path.combine dir "rt.c") then
      dir
    else
      match Tools.findUp dir "runtime/rt.c" with
      | Some root -> Path.combine root "runtime"
      | None -> dir

// the processor --cpu names, as clang takes it: -march on x86-64, -mcpu elsewhere
let cpuFlags (o: Options.Options) : list<string> =
  let x86 = o.target = "" || String.startsWith "x86_64" o.target
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
  | (value, _) :: _ -> Error(InPass { file = ""; line = 0; message = $"top-level value '{value}' is computed at startup, which a library doesn't have; make it a constant or a function" })
  | [] ->
    match lower prog o.debugInfo o.time with
    | Error e -> Error(InPass e)
    | Ok(types, funs) ->
      // a library's handles may be used on any thread of its C host
      let threads = threaded prog.externs funs || (o.isLib && exportsHandles prog)
      let level = Options.optLevel o
      let gopts : Gen.Emit.Options =
        { debugInfo = o.debugInfo
          optimized = level <> "-O0"
          optimizeSize = level = "-Os"
          target = o.target
          checkedHeap = usesPrim heapPrims funs
          targets = prog.targets
          cpu = o.cpu
          wideVectors = wideVectors funs
          threaded = threads }
      match timed o.time "LLVM IR" (fun () -> Gen.Module.compile gopts types prog.externs prog.exports prog.tests prog.values prog.clayouts None funs) with
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
      let rt = runtimeDir ()
      let runtimeFile (name: string) = Path.combine rt name
      // ZS_NO_POOL: objects from malloc, one by one, for valgrind (a sanitized build has that too)
      let defines = List.append (if threads then [ "-DZS_THREADS" ] else []) (if Option.isSome (Environment.getVariable "ZS_NO_POOL") then [ "-DZS_NO_POOL" ] else [])
      let san =
        if not o.sanitize then []
        else if o.threadSanitizer then [ "-fsanitize=thread"; "-g" ]
        // AddressSanitizer sees each object
        else [ "-fsanitize=address,undefined"; "-g"; "-DZS_NO_POOL" ]
      // -g: unoptimized, so stepping follows the source
      let opt = if o.debugInfo then [ "-O0"; "-g" ] else level :: cpuFlags o
      let profile =
        if o.profileGenerate then [ "-fprofile-generate" ]
        else
          match o.profileUse with
          | Some file -> [ "-fprofile-use=" + Path.getFullPath file ]
          | None -> []
      // a cross build (--target): clang compiles the IR for the target, and zig cc compiles the
      // runtime and links against Zig's bundled libc (musl: a static binary, no sysroot needed)
      let cross = o.target <> ""
      let tclang = if cross then [ "--target=" + o.target ] else []
      let cc (args: list<string>) = if cross then Tools.run "zig" (List.append [ "cc"; "-target"; o.target ] args) else Tools.run "clang" args
      let built =
        match o.mcu with
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
          let r = andThen (fun () -> timed o.time "zig cc" (fun () -> Tools.run "zig" (List.concat [ [ "cc"; "-target"; m.zigTarget; "-mcpu=" + m.zigCpu ]; opt; flags; [ $"-DZS_HEAP_SIZE={m.heap}"; "-T" + script; "-Wl,--gc-sections"; obj; runtimeFile "rt-embedded.c"; "-o"; o.out ] ]))) compiled
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
            let r1 = timed o.time "clang" (fun () -> Tools.run "clang" (List.concat [ opt; tclang; [ "-c"; "-Wno-override-module" ]; san; [ ll; "-o"; obj ] ]))
            let r2 = andThen (fun () -> timed o.time "zig cc" (fun () -> cc (List.concat [ opt; defines; [ obj; runtimeFile "rt.c" ]; linkArgs linked; [ "-o"; o.out; "-lm" ] ]))) r1
            File.delete obj |> ignore
            r2
          else
            timed o.time "clang" (fun () -> Tools.run "clang" (List.concat [ opt; profile; defines; [ "-rdynamic"; "-Wno-override-module" ]; san; [ ll; runtimeFile "rt.c" ]; linkArgs linked; [ "-o"; o.out; "-lm" ] ]))
      if not o.emitLlvm then
        File.delete ll |> ignore
        Directory.delete scratch |> ignore
      match built with
      | Ok () -> Ok ()
      | Error m -> Error(InTool m)
