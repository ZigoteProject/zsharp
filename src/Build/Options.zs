/// What a build is asked for: zs build's flags (the F# compiler's Main and Driver settings).

/// A bare-metal target (zs build --target cortex-m4, wasm32): how clang and zig cc are told about
/// the chip, the QEMU board whose memory map the program is linked for ("" for WebAssembly), and
/// the heap size. The program uses runtime/rt-embedded.c instead of the OS runtime.
type Mcu = { triple: string; cflags: list<string>; zigTarget: string; zigCpu: string; board: string; heap: int }

/// The chips --target knows by name, and WebAssembly.
let mcus : list<string * Mcu> =
  [ ("cortex-m4", { triple = "thumbv7em-none-eabihf"; cflags = [ "-mcpu=cortex-m4"; "-mfpu=fpv4-sp-d16"; "-mfloat-abi=hard" ]; zigTarget = "thumb-freestanding-eabihf"; zigCpu = "cortex_m4+vfp4d16sp"; board = "mps2-an386"; heap = 64 * 1024 })
    ("cortex-m0plus", { triple = "thumbv6m-none-eabi"; cflags = [ "-mcpu=cortex-m0plus"; "-mfloat-abi=soft" ]; zigTarget = "thumb-freestanding-eabi"; zigCpu = "cortex_m0plus"; board = "microbit"; heap = 8 * 1024 })
    // freestanding WebAssembly: no OS, the host gives output and exit as imports
    ("wasm32", { triple = "wasm32-unknown-unknown"; cflags = []; zigTarget = "wasm32-freestanding"; zigCpu = "generic"; board = ""; heap = 1024 * 1024 }) ]

/// A build's options.
type Options =
  { /// the main file ("" for the project's)
    main: string
    /// what's made: the main file's name without .zs unless -o names it
    out: string
    /// the optimization level asked for (-O0 … -O3, -Os), if one was
    opt: option<string>
    /// --release: optimized (-O2 unless a level is asked for); profiles are for release builds
    release: bool
    /// -g: DWARF debug info, unoptimized
    debugInfo: bool
    /// --emit-llvm: the IR kept next to the output (out.ll)
    emitLlvm: bool
    /// --target: the triple ("" for the host); a chip's name sets mcu, and the chip's triple here
    target: string
    /// the microcontroller --target names, if it names one
    mcu: option<Mcu>
    /// --cpu: the processor
    cpu: option<string>
    /// --lib: a static library (or a .so), with a C header
    isLib: bool
    /// --strict: warnings fail the build
    strict: bool
    /// --sanitize (address and undefined behaviour), --sanitize=thread (data races)
    sanitize: bool
    threadSanitizer: bool
    /// --profile-generate: a program that writes a profile; --profile-use <file>: built with one
    profileGenerate: bool
    profileUse: option<string>
    /// --time: each phase's milliseconds
    time: bool
    /// built by the build server (--time says so)
    served: bool
    /// --check-ir: the IR checked after each pass (Core.Check), as ./test.sh does
    checkIr: bool
    /// a chip's heap in bytes, from the project's [target.<name>] (the chip's default when None)
    heap: option<int>
    /// the arguments after the file (zs run's, for the program)
    rest: list<string> }

let private levels : Set<string> = Set.ofList [ "-O0"; "-O1"; "-O2"; "-O3"; "-Os" ]

/// The options of no flags.
extern zs_host_arch : unit -> cstr

/// The machine the compiler runs on, as a triple's first part (x86_64, aarch64).
let hostArch () : string = String.ofCStr (zs_host_arch ())

/// What a build without --target is for: the host, except on Windows, where it's the platform's
/// mingw-w64 target, so it goes through the cross path (clang for the IR, zig cc with mingw-w64
/// for the runtime and the link): clang alone there targets MSVC, without the headers and the C
/// library the runtime is written against.
let nativeTarget () : string = if Tools.hostOs () = "windows" then hostArch () + "-windows-gnu" else ""

let defaults : Options =
  { main = ""
    out = ""
    opt = None
    release = false
    debugInfo = false
    emitLlvm = false
    target = ""
    mcu = None
    cpu = None
    isLib = false
    strict = false
    sanitize = false
    threadSanitizer = false
    profileGenerate = false
    profileUse = None
    time = false
    served = false
    checkIr = false
    heap = None
    rest = [] }

/// The options with --target's: a chip's name sets its triple and the chip, anything else is the
/// triple.
let withTarget (o: Options) (t: string) : Options =
  match List.tryFind (fun (n, _) -> n = t) mcus with
  | Some(_, m) -> { o with target = m.triple; mcu = Some m }
  | None -> { o with target = t }

/// The options a command's arguments ask for, and the arguments that aren't flags (in order);
/// Error names a flag that lacks its value.
let parse (args: list<string>) : result<Options * list<string>, string> =
  let rec go (o: Options) (others: list<string>) (rest: list<string>) : result<Options * list<string>, string> =
    match rest with
    | [] -> Ok(o, List.rev others)
    // what follows is the program's (zs run)
    | "--" :: more -> Ok({ o with rest = more }, List.rev others)
    | "-o" :: out :: more -> go { o with out = out } others more
    | "--release" :: more -> go { o with release = true } others more
    | "-g" :: more -> go { o with debugInfo = true } others more
    | "--emit-llvm" :: more -> go { o with emitLlvm = true } others more
    | "--target" :: t :: more -> go (withTarget o t) others more
    | "--cpu" :: c :: more -> go { o with cpu = Some c } others more
    | "--lib" :: more -> go { o with isLib = true } others more
    | "--strict" :: more -> go { o with strict = true } others more
    | "--sanitize" :: more -> go { o with sanitize = true } others more
    | "--sanitize=thread" :: more -> go { o with sanitize = true; threadSanitizer = true } others more
    | "--profile-generate" :: more -> go { o with profileGenerate = true; release = true } others more
    | "--profile-use" :: file :: more -> go { o with profileUse = Some file; release = true } others more
    | "--time" :: more -> go { o with time = true } others more
    | "--check-ir" :: more -> go { o with checkIr = true } others more
    | a :: more ->
      if Set.contains a levels then go { o with opt = Some a } others more
      else if String.startsWith "--cpu=" a then go { o with cpu = Some(String.sub a 6 (String.length a - 6)) } others more
      else if List.contains a [ "-o"; "--target"; "--cpu"; "--profile-use" ] then Error $"zs: {a} needs a value"
      else go o (a :: others) more
  go { defaults with target = nativeTarget () } [] args

/// The target's name in a project's [c.<name>] and [target.<name>] sections: host for this
/// machine, a chip's name for its triple (cortex-m4), else the triple --target gave.
let targetName (target: string) : string =
  if target = "" || target = nativeTarget () then "host"
  else
    match List.tryFind (fun (c: string * Mcu) -> (snd c).triple = target) mcus with
    | Some(n, _) -> n
    | None -> target

/// The architecture built for: the target triple's first part, or the host's (a native build).
let arch (o: Options) : string =
  if o.target = "" then hostArch () else List.head (String.split "-" o.target)

/// The target as clang names it: Zig's names (--target) are clang's but for Apple's vendor.
let clangTriple (o: Options) : string =
  match String.split "-" o.target with
  | [ a; "macos" ] -> a + "-apple-macos"
  | _ -> o.target

/// What the runtime links on the target beyond the C library: on Windows, Winsock (the loop,
/// sockets) and the API set with WaitOnAddress (Mutex).
let systemLibs (o: Options) : list<string> =
  if String.contains "-windows" o.target then [ "-lws2_32"; "-lapi-ms-win-core-synch-l1-2-0" ] else []

/// The optimization level for clang: what was asked, else -O2 for a release build or a chip and
/// -O0 for a debug build.
let optLevel (o: Options) : string =
  match o.opt with
  | Some l -> l
  | None -> if o.release || Option.isSome o.mcu then "-O2" else "-O0"

/// Whether the link drops the functions and data nothing reaches: an optimized build's (a hello
/// world is 17 KB, not 93, most of it the runtime's unused functions). A debug build keeps them
/// all, and exports them (-rdynamic) so a panic's backtrace names the runtime's frames.
let dropsUnused (o: Options) : bool = optLevel o <> "-O0" && not o.debugInfo

/// Compile flags for that: each function and datum in a section of its own.
let sectionFlags (o: Options) : list<string> = if dropsUnused o then [ "-ffunction-sections"; "-fdata-sections" ] else []

/// Link flags for that, by the target's linker (lld-link drops them by itself without -g); a
/// debug build's -rdynamic instead, on the host.
let unusedLinkFlags (o: Options) : list<string> =
  let os =
    if o.target = "" then Tools.hostOs ()
    else if String.contains "-macos" o.target then "macos"
    else if String.contains "-windows" o.target then "windows"
    else "linux"
  if not (dropsUnused o) then (if o.target = "" && os <> "windows" then [ "-rdynamic" ] else [])
  else if os = "macos" then [ "-Wl,-dead_strip" ]
  else if os = "windows" then []
  else [ "-Wl,--gc-sections" ]
