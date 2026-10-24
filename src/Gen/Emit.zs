/// Writing LLVM IR text (the F# compiler's Codegen.Emitter and its tables): an emitter per
/// function, the options code generation takes, and how C values are passed.
open Types.Ty

/// Text built a piece at a time, as the F# compiler's code generator built it in .NET's
/// StringBuilder: each piece copied once, into storage that doubles when full, and the text once
/// more by `toString`. (The compiler's own: it builds against its stage 0's library, which has
/// none.)
type StringBuilder = { bytes: ref<Buffer<u8>>; length: ref<int> }

module StringBuilder =
  let create () : StringBuilder = { bytes = ref Buffer.empty; length = ref 0 }

  /// Appends `n` bytes of `s` from `start` (the code generator cuts its text at ASCII).
  let appendSub (s: string) (start: int) (n: int) (b: StringBuilder) =
    let at = b.length.Value
    let room = Buffer.length b.bytes.Value
    if at + n > room then
      let grown = Buffer.create (max (max 64 (2 * room)) (at + n)) (u8 0)
      Buffer.blit b.bytes.Value 0 grown 0 at
      b.bytes.Value <- grown
    Buffer.blit (String.bytes s) start b.bytes.Value at n
    b.length.Value <- at + n

  let append (s: string) (b: StringBuilder) = appendSub s 0 (String.length s) b

  let toString (b: StringBuilder) : string = String.ofBytes (Buffer.slice b.bytes.Value 0 b.length.Value)

/// LLVM IR being written for one function: its instructions, its allocas (which go first, in the
/// entry block), the counter its names are numbered by, the block being written, and the debug
/// location attached to each instruction ("" for none). One heap cell, so a closure holds a
/// pointer.
type Emitter =
  | Emitter of EmitterData

and EmitterData = { code: StringBuilder; allocas: StringBuilder; count: ref<int>; block: ref<string>; dbg: ref<string> }

/// An emitter for a new function, in its entry block.
let emitter () : Emitter = Emitter { code = StringBuilder.create (); allocas = StringBuilder.create (); count = ref 0; block = ref "entry"; dbg = ref "" }

/// The pieces of a buffer of text, joined.
let joined (b: Buffer<string>) : string = String.concat (Array.toList (Buffer.toArray b))

/// A fresh name: the prefix and the next number.
let fresh (em: Emitter) (prefix: string) : string =
  match em with
  | Emitter { count = n } ->
    n.Value <- n.Value + 1
    prefix + $"{n.Value}"

/// A fresh temporary (%tN).
let tmp (em: Emitter) : string = "%" + fresh em "t"

/// Appends an instruction, with the debug location when there is one.
let emit (em: Emitter) (s: string) =
  match em with
  | Emitter { code = c; dbg = d } ->
    StringBuilder.append "  " c
    StringBuilder.append s c
    if d.Value <> "" then
      StringBuilder.append ", !dbg " c
      StringBuilder.append d.Value c
    StringBuilder.append "\n" c

/// A line that isn't an instruction (a debug record).
let raw (em: Emitter) (s: string) =
  match em with
  | Emitter { code = c } ->
    StringBuilder.append "  " c
    StringBuilder.append s c
    StringBuilder.append "\n" c

/// An instruction with a result: its name.
let instr (em: Emitter) (s: string) : string =
  let r = tmp em
  emit em (r + " = " + s)
  r

/// Starts a block.
let enter (em: Emitter) (l: string) =
  match em with
  | Emitter { code = c; block = b } ->
    StringBuilder.append l c
    StringBuilder.append ":\n" c
    b.Value <- l

/// Continues in a fresh block that nothing jumps to (after ret / unreachable).
let dead (em: Emitter) = enter em (fresh em "dead")

/// An alloca, for the entry block.
let alloca (em: Emitter) (s: string) =
  match em with
  | Emitter { allocas = a } ->
    StringBuilder.append "  " a
    StringBuilder.append s a
    StringBuilder.append "\n" a

/// The block being written.
let current (em: Emitter) : string =
  match em with
  | Emitter { block = b } -> b.Value

/// The debug location attached to instructions ("" for none).
let dbgOf (em: Emitter) : string =
  match em with
  | Emitter { dbg = d } -> d.Value

let setDbg (em: Emitter) (loc: string) =
  match em with
  | Emitter { dbg = d } -> d.Value <- loc

/// The function's body: the entry block's allocas, then the code.
let bodyOf (em: Emitter) : string =
  match em with
  | Emitter { code = c; allocas = a } -> "entry:\n" + StringBuilder.toString a + StringBuilder.toString c

/// The instructions alone, for code that goes into another function's block.
let codeOf (em: Emitter) : string =
  match em with
  | Emitter { code = c } -> StringBuilder.toString c

/// A variable in the code: an SSA value, or a `let mutable`'s stack slot.
type Binding =
  | Ssa of string
  | Slot of string

/// How a C value is passed (x86-64 System V, AAPCS64).
type Abi =
  /// as its own LLVM type
  | Scalar
  /// a struct split into eightbytes: INTEGER (iN) or SSE (double, float, <2 x float>)
  | Pieces of list<string>
  /// a struct by pointer: byval for parameters, sret for results
  | Memory

/// What code generation is told about the build (the F# compiler's Codegen settings).
type Options =
  { /// DWARF debug info (zs build -g): line tables, functions, and the local variables gdb can show
    debugInfo: bool
    /// clang optimizes the module (not -O0): unoptimized, a call to itself in tail position must
    /// be a musttail call, for constant stack
    optimized: bool
    /// -Os: optsize on every function, and loop versioning only for small loops
    optimizeSize: bool
    /// the target triple (zs build --target), "" for the host
    target: string
    /// the architecture built for: the target's first part, or the host's (x86_64, aarch64,
    /// thumbv7em): it decides the C ABI and which intrinsics there are
    arch: string
    /// the program has weak references or arenas: its objects go through the runtime's checked
    /// allocation, and a cell Perceus reuses is reported
    checkedHeap: bool
    /// [<Target>] and [<Multiversion>] functions (Program.targets)
    targets: Map<string, list<string>>
    /// --cpu's name, for the check that an intrinsic's features are there
    cpu: option<string>
    /// the program has SIMD vectors of 32 or 64 bytes: its objects come from zs_alloc_wide
    wideVectors: bool
    /// the program runs code on more than one thread: shared objects' counts change atomically
    threaded: bool }

/// One of the LLVM modules a program is split into, compiled on its own: the functions it
/// defines, those of them the other modules call, whether it has the entry points (main, the
/// tests, C exports), and whether it holds copies of library functions and generic instances
/// (which other modules may define too: weak, the linker keeps one).
type Part = { defines: Set<string>; called: Set<string>; entry: bool; copies: bool; file: string }

/// + - * on integers.
let arith : Map<string, string> = Map.ofList [ ("+", "add"); ("-", "sub"); ("*", "mul") ]

let farith : Map<string, string> = Map.ofList [ ("+", "fadd"); ("-", "fsub"); ("*", "fmul"); ("/", "fdiv"); ("%", "frem") ]

let icmpS : Map<string, string> = Map.ofList [ ("=", "eq"); ("<>", "ne"); ("<", "slt"); (">", "sgt"); ("<=", "sle"); (">=", "sge") ]

let icmpU : Map<string, string> = Map.ofList [ ("=", "eq"); ("<>", "ne"); ("<", "ult"); (">", "ugt"); ("<=", "ule"); (">=", "uge") ]

let fcmp : Map<string, string> = Map.ofList [ ("=", "oeq"); ("<>", "une"); ("<", "olt"); (">", "ogt"); ("<=", "ole"); (">=", "oge") ]

/// The text with a function's definition (from its first line to its closing brace) replaced.
let replaceDef (text: string) (def: string) : string =
  let header = String.sub def 0 (Option.get (String.indexOf "\n" def))
  let start = Option.get (String.indexOf header text)
  let rest = String.sub text start (String.length text - start)
  let stop = start + Option.get (String.indexOf "\n}" rest) + 2
  String.sub text 0 start + def + String.sub text stop (String.length text - stop)

/// Primitives implemented by runtime functions: C name, result type, parameter types (unit
/// parameters omitted). Arguments are borrowed by the runtime and dropped after the call, except
/// those marked with !, whose reference the runtime keeps (the event loop's callbacks). A `bytes`
/// parameter (a Buffer, a span or a string) is passed as its data and its length.
let private runtimeList : list<string * (string * string * list<string>)> =
  [ ("Loop.post", ("zs_loop_post", "void", [ "ptr!" ]))
    ("Loop.wait", ("zs_loop_wait", "void", [ "i_W"; "i1 zeroext"; "ptr!" ]))
    ("Loop.unwait", ("zs_loop_unwait", "void", [ "i_W"; "i1 zeroext" ]))
    ("Loop.timer", ("zs_loop_timer", "i_W", [ "i_W"; "ptr!" ]))
    ("Loop.untimer", ("zs_loop_untimer", "void", [ "i_W" ]))
    ("Loop.step", ("zs_loop_step", "zeroext i1", []))
    ("Loop.jobs", ("zs_loop_jobs", "i_W", []))
    ("Loop.close", ("zs_loop_close", "void", []))
    ("Loop.enter", ("zs_loop_enter", "zeroext i1", []))
    ("Loop.leave", ("zs_loop_leave", "void", []))
    ("Loop.blocking", ("zs_loop_blocking", "void", [ "ptr!"; "ptr!" ]))
    ("Loop.spawn", ("zs_loop_spawn", "void", [ "ptr!" ]))
    ("Loop.expect", ("zs_loop_expect", "i_W", [ "ptr!" ]))
    ("Loop.fulfill", ("zs_loop_fulfill", "void", [ "i_W" ]))
    ("Tcp.listen", ("zs_tcp_listen", "i_W", [ "ptr"; "i_W" ]))
    ("Tcp.accept", ("zs_tcp_accept", "i_W", [ "i_W" ]))
    ("Tcp.connect", ("zs_tcp_connect", "i_W", [ "ptr"; "i_W" ]))
    ("Tcp.error", ("zs_socket_error", "i_W", [ "i_W" ]))
    ("Fd.read", ("zs_fd_read", "i_W", [ "i_W"; "bytes"; "i_W"; "i_W" ]))
    ("Fd.write", ("zs_fd_write", "i_W", [ "i_W"; "bytes"; "i_W"; "i_W" ]))
    ("String.slice", ("zs_str_slice", "ptr", [ "ptr"; "i_W"; "i_W" ]))
    ("String.ofBytes", ("zs_str_of_bytes", "ptr", [ "bytes" ]))
    ("Fd.close", ("zs_fd_close", "void", [ "i_W" ]))
    ("Errno.text", ("zs_error_text", "ptr", [ "i_W" ]))
    ("String.sub", ("zs_str_sub", "ptr", [ "ptr"; "i_W"; "i_W" ]))
    ("String.byte", ("zs_str_byte", "zeroext i8", [ "ptr"; "i_W" ]))
    ("String.ofByte", ("zs_str_of_byte", "ptr", [ "i8 zeroext" ]))
    ("String.indexOfFrom", ("zs_str_index_of", "i_W", [ "ptr"; "ptr"; "i_W" ]))
    ("String.trim", ("zs_str_trim", "ptr", [ "ptr" ]))
    ("String.toUpper", ("zs_str_upper", "ptr", [ "ptr" ]))
    ("String.toLower", ("zs_str_lower", "ptr", [ "ptr" ]))
    ("String.replace", ("zs_str_replace", "ptr", [ "ptr"; "ptr"; "ptr" ]))
    ("String.isFloat", ("zs_str_is_float", "zeroext i1", [ "ptr" ]))
    ("String.toFloat", ("zs_str_to_float", "double", [ "ptr" ]))
    ("Console.readLineRaw", ("zs_read_line", "ptr", []))
    ("Console.eof", ("zs_eof", "zeroext i1", []))
    ("eprintln", ("zs_eprintln", "void", [ "ptr" ]))
    ("Env.argc", ("zs_argc", "i_W", []))
    ("Clock.realtime", ("zs_clock_realtime", "i64", []))
    ("File.open", ("zs_file_open", "i_W", [ "ptr"; "i_W" ]))
    ("File.mtime", ("zs_file_mtime", "i64", [ "ptr" ]))
    ("File.size", ("zs_file_size", "i64", [ "ptr" ]))
    ("File.touch", ("zs_file_touch", "void", [ "ptr" ]))
    ("File.copy", ("zs_file_copy", "void", [ "ptr"; "ptr" ]))
    ("File.move", ("zs_file_move", "void", [ "ptr"; "ptr" ]))
    ("File.temp", ("zs_temp_file", "ptr", [ "ptr" ]))
    ("Dir.temp", ("zs_temp_dir", "ptr", [ "ptr" ]))
    ("Dir.delete", ("zs_dir_delete", "void", [ "ptr" ]))
    ("File.isSymlink", ("zs_is_symlink", "zeroext i1", [ "ptr" ]))
    ("Env.cwd", ("zs_current_dir", "ptr", []))
    ("Process.start", ("zs_process_start", "i_W", [ "ptr"; "ptr"; "ptr"; "i1 zeroext"; "ptr"; "i_W"; "i_W"; "i_W" ]))
    ("Process.pipe", ("zs_process_pipe", "i_W", [ "i_W" ]))
    ("Process.wait", ("zs_process_wait", "i_W", [ "i_W" ]))
    ("Process.kill", ("zs_process_kill", "i_W", [ "i_W" ]))
    ("Unix.listen", ("zs_unix_listen", "i_W", [ "ptr" ]))
    ("Unix.connect", ("zs_unix_connect", "i_W", [ "ptr" ]))
    ("Env.arg", ("zs_arg", "ptr", [ "i_W" ]))
    ("Env.has", ("zs_env_has", "zeroext i1", [ "ptr" ]))
    ("Env.get", ("zs_env_get", "ptr", [ "ptr" ]))
    ("Io.ok", ("zs_io_ok", "zeroext i1", []))
    ("Io.error", ("zs_io_error", "ptr", []))
    ("File.readRaw", ("zs_file_read", "ptr", [ "ptr" ]))
    ("File.writeRaw", ("zs_file_write", "void", [ "ptr"; "ptr" ]))
    ("File.appendRaw", ("zs_file_append", "void", [ "ptr"; "ptr" ]))
    ("File.exists", ("zs_file_exists", "zeroext i1", [ "ptr" ]))
    ("File.deleteRaw", ("zs_file_delete", "void", [ "ptr" ]))
    ("Dir.exists", ("zs_dir_exists", "zeroext i1", [ "ptr" ]))
    ("Dir.createRaw", ("zs_dir_create", "void", [ "ptr" ]))
    ("Dir.listRaw", ("zs_dir_list", "ptr", [ "ptr" ]))
    ("Process.runRaw", ("zs_process_run", "ptr", [ "ptr"; "ptr" ]))
    ("Process.code", ("zs_process_code", "i_W", [])) ]

let runtimePrims : Map<string, string * string * list<string>> = Map.ofList runtimeList

/// A float constant as LLVM writes it: its bits in hex (an f32's rounded to f32 first).
let floatConst (ty: string) (f: f64) : string =
  let x = if ty = "float" then f64 (f32 f) else f
  let bits = Float.toBits x
  $"0x{bits:X16}"
