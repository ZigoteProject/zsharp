module Codegen

open System
open System.Collections.Generic
open System.IO
open System.Text
open Syntax
open Core
open Mono

// Representation (every heap object starts with a word-sized reference count; 0 = static, never
// freed). W is the machine word: i64, or i32 on a 32-bit chip (written i_W, resolved at the end):
//   int/usize W, i64/u64 i64, i32/u32 i32, i16/u16 i16, i8/u8 i8, f64 double, f32 float, bool i1,
//   unit {} (value: zeroinitializer), cstr ptr
//   string   ptr -> { W rc, W len, [len+1 x i8] }
//   array<T> ptr -> { W rc, W len, [len x T] }
//   ref<T>   ptr -> { W rc, T }
//   union    ptr -> { W rc, i32 tag, field... } for a case with fields (no tag when it's the only
//            such case); a case without fields is a static cell, told apart by its address. Two
//            cases, one without fields and one with a single pointer field (option<string>): the
//            field itself, or @zs.none
//   closure  ptr -> { W rc, ptr code, ptr info, env... }; code: (ptr self, arg) -> result;
//            info -> { ptr drop, i32 arity, ptr full }: the parameters it still takes, and code
//            taking all of them at once, full: (ptr self, args...) -> result
//   tuples and records: LLVM struct values; so are small non-recursive unions without heap
//   data (an i32 tag, or an i8 one for an enum, then every case's fields)

type private Binding =
    | Ssa of string
    | Slot of string // alloca'd mutable variable

type private Emitter() =
    let sb = StringBuilder()
    let allocas = StringBuilder()
    let mutable n = 0
    member val Block = "entry" with get, set

    member _.Fresh(prefix: string) =
        n <- n + 1
        sprintf "%s%d" prefix n

    member this.Tmp() = "%" + this.Fresh "t"
    /// The source location (!DILocation) attached to each instruction, when debug info is on.
    member val Dbg = "" with get, set
    member this.Emit(s: string) = sb.Append("  ").Append(s).AppendLine(if this.Dbg = "" then "" else ", !dbg " + this.Dbg) |> ignore
    /// A line that isn't an instruction (a debug record).
    member _.Raw(s: string) = sb.Append("  ").AppendLine(s) |> ignore

    member this.Instr(s: string) =
        let r = this.Tmp()
        this.Emit(r + " = " + s)
        r

    member this.Label(l: string) =
        sb.AppendLine(l + ":") |> ignore
        this.Block <- l

    /// Continues in a fresh block that nothing jumps to (after ret / unreachable).
    member this.Dead() = this.Label(this.Fresh "dead")
    member _.Alloca(s: string) = allocas.Append("  ").AppendLine(s) |> ignore
    member _.Body = "entry:\n" + allocas.ToString() + sb.ToString()
    /// The instructions alone, for code that goes into another function's block.
    member _.Code = sb.ToString()

/// How a C value is passed (x86-64 System V).
type private Abi =
    | Scalar // as its own LLVM type
    | Pieces of string list // a struct split into eightbytes: INTEGER (iN) or SSE (double, float, <2 x float>)
    | Memory // a struct by pointer: byval for parameters, sret for results

let private arith = dict [ "+", "add"; "-", "sub"; "*", "mul" ]
let private farith = dict [ "+", "fadd"; "-", "fsub"; "*", "fmul"; "/", "fdiv"; "%", "frem" ]
let private icmpS = dict [ "=", "eq"; "<>", "ne"; "<", "slt"; ">", "sgt"; "<=", "sle"; ">=", "sge" ]
let private icmpU = dict [ "=", "eq"; "<>", "ne"; "<", "ult"; ">", "ugt"; "<=", "ule"; ">=", "uge" ]
let private fcmp = dict [ "=", "oeq"; "<>", "une"; "<", "olt"; ">", "ogt"; "<=", "ole"; ">=", "oge" ]

let private prelude =
    """declare noalias ptr @zs_alloc(i_W) allockind("alloc,uninitialized") allocsize(0) "alloc-family"="zs"
declare void @zs_free(ptr allocptr) allockind("free") "alloc-family"="zs"
declare i_W @zs_allocations()
declare i_W @zs_mallocs()
declare ptr @zs_ptr_alloc(i_W, i_W)
declare void @zs_ptr_free(ptr)
declare i64 @zs_ticks()
declare void @zs_set_args(i32, ptr)
declare i_W @zs_test_index()
declare void @zs_exit(i_W) noreturn
declare void @llvm.memcpy.p0.p0.i_W(ptr, ptr, i_W, i1)
declare void @zs_panic(ptr) noreturn
declare void @zs_panic_c(ptr) noreturn
declare ptr @zs_str_of_lanes(ptr, i_W, i_W)
declare zeroext i1 @zs_cpu_supports(ptr)
declare void @zs_loop_spawn(ptr)
declare i_W @zs_loop_expect(ptr)
declare void @zs_loop_fulfill(i_W)
declare ptr @zs_par_fork(ptr, ptr, i_W)
declare ptr @zs_par_join(ptr)
declare void @zs_par_free(ptr)
declare i_W @zs_par_workers()
declare void @zs_lock(ptr)
declare void @zs_unlock(ptr)
declare ptr @zs_chan_new(i_W, i_W, ptr)
declare void @zs_chan_send(ptr, ptr)
declare zeroext i1 @zs_chan_recv(ptr, ptr)
declare void @zs_chan_close(ptr)
declare void @zs_chan_free(ptr)
declare ptr @zs_weak_new(ptr)
declare ptr @zs_weak_target(ptr)
declare void @zs_weak_free(ptr)
declare void @zs_arena_open()
declare void @zs_arena_close()
declare void @zs_reused(ptr)
declare ptr @zs_handle_new(ptr, ptr)
declare ptr @zs_handle_get(ptr)
declare void @zs_release(ptr)
declare ptr @zs_str_concat(ptr, ptr)
declare i_W @zs_str_cmp(ptr, ptr)
declare i_W @zs_str_hash(ptr)
declare ptr @zs_str_of_i64(i64)
declare ptr @zs_str_of_u64(i64)
declare ptr @zs_str_of_f64(double)
declare ptr @zs_str_of_f32(float)
declare ptr @zs_str_of_bool(i1 zeroext)
declare ptr @zs_str_of_char(i32)
declare void @zs_print(ptr)
declare void @zs_println(ptr)
declare ptr @zs_str_from_c(ptr)
declare ptr @zs_str_sub(ptr, i_W, i_W)
declare zeroext i8 @zs_str_byte(ptr, i_W)
declare ptr @zs_str_of_byte(i8 zeroext)
declare i_W @zs_str_index_of(ptr, ptr, i_W)
declare ptr @zs_str_trim(ptr)
declare ptr @zs_str_upper(ptr)
declare ptr @zs_str_lower(ptr)
declare ptr @zs_str_replace(ptr, ptr, ptr)
declare zeroext i1 @zs_str_is_float(ptr)
declare double @zs_str_to_float(ptr)
declare double @llvm.sqrt.f64(double)
declare float @llvm.sqrt.f32(float)
declare ptr @zs_read_line()
declare i_W @zs_argc()
declare ptr @zs_arg(i_W)
declare zeroext i1 @zs_env_has(ptr)
declare ptr @zs_env_get(ptr)
declare zeroext i1 @zs_io_ok()
declare ptr @zs_io_error()
declare ptr @zs_file_read(ptr)
declare void @zs_file_write(ptr, ptr)
declare void @zs_file_append(ptr, ptr)
declare zeroext i1 @zs_file_exists(ptr)
declare void @zs_file_delete(ptr)
declare zeroext i1 @zs_dir_exists(ptr)
declare void @zs_dir_create(ptr)
declare ptr @zs_dir_list(ptr)
declare ptr @zs_process_run(ptr, ptr)
declare i_W @zs_process_code()
declare zeroext i1 @zs_eof()
declare void @zs_eprintln(ptr)
declare void @zs_loop_post(ptr)
declare void @zs_loop_wait(i_W, i1 zeroext, ptr)
declare void @zs_loop_unwait(i_W, i1 zeroext)
declare i_W @zs_loop_timer(i_W, ptr)
declare void @zs_loop_untimer(i_W)
declare zeroext i1 @zs_loop_step()
declare void @zs_loop_close()
declare zeroext i1 @zs_loop_enter()
declare void @zs_loop_leave()
declare void @zs_loop_blocking(ptr, ptr)
declare i_W @zs_tcp_listen(ptr, i_W)
declare i_W @zs_tcp_accept(i_W)
declare i_W @zs_tcp_connect(ptr, i_W)
declare i_W @zs_socket_error(i_W)
declare i_W @zs_fd_read(i_W, ptr, i_W, i_W)
declare i_W @zs_fd_write(i_W, ptr, i_W, i_W)
declare void @zs_fd_close(i_W)
declare ptr @zs_error_text(i_W)

; a count above 0 is a thread-local object's, 0 a static one's (never freed), and below 0 a
; shared object's, -n for n references, counted atomically (DESIGN §7.1): a program with threads
; has threadedRc's versions of these two, which count it
define private void @zs.dup(ptr %p) alwaysinline {
entry:
  %rc = load i_W, ptr %p
  %local = icmp sgt i_W %rc, 0
  br i1 %local, label %inc, label %done
inc:
  %n = add i_W %rc, 1
  store i_W %n, ptr %p
  br label %done
done:
  ret void
}

; an option's empty case when the other one holds a pointer (option<string>): a static object
; (count 0, never freed), compared by its address
@zs.none = private constant { i_W } { i_W 0 }

; true when this was the last reference (the caller frees the object)
define private i1 @zs.release(ptr %p) alwaysinline {
entry:
  %rc = load i_W, ptr %p
  %last = icmp eq i_W %rc, 1
  br i1 %last, label %yes, label %no
yes:
  ret i1 true
no:
  %more = icmp sgt i_W %rc, 1
  br i1 %more, label %dec, label %keep
dec:
  %n = sub i_W %rc, 1
  store i_W %n, ptr %p
  br label %keep
keep:
  ret i1 false
}

define private void @zs.drop.str(ptr %p) {
entry:
  %last = call i1 @zs.release(ptr %p)
  br i1 %last, label %free, label %done
free:
  call void @zs_free(ptr %p)
  ret void
done:
  ret void
}

; a dyn Trait value: { count, vtable, the value }; the vtable's first entry frees it
define private void @zs.drop.dyn(ptr %p) {
entry:
  %last = call i1 @zs.release(ptr %p)
  br i1 %last, label %free, label %done
free:
  %vp = getelementptr { i_W, ptr }, ptr %p, i32 0, i32 1
  %vt = load ptr, ptr %vp
  %f = load ptr, ptr %vt
  call void %f(ptr %p)
  ret void
done:
  ret void
}

define private void @zs.drop.clo(ptr %p) {
entry:
  %last = call i1 @zs.release(ptr %p)
  br i1 %last, label %free, label %done
free:
  %ip = getelementptr { i_W, ptr, ptr }, ptr %p, i32 0, i32 2
  %info = load ptr, ptr %ip
  %f = load ptr, ptr %info
  call void %f(ptr %p)
  ret void
done:
  ret void
}

; the event loop's ways with the closures it owns (unit -> unit, runtime/rt.c): call one and give
; up the loop's reference, only call it (on Task.blocking's helper thread), only give it up
define weak_odr void @zs_clo_run(ptr %c) {
entry:
  %cp = getelementptr { i_W, ptr }, ptr %c, i32 0, i32 1
  %code = load ptr, ptr %cp
  call {} %code(ptr %c, {} zeroinitializer)
  call void @zs.drop.clo(ptr %c)
  ret void
}

define weak_odr void @zs_clo_call(ptr %c) {
entry:
  %cp = getelementptr { i_W, ptr }, ptr %c, i32 0, i32 1
  %code = load ptr, ptr %cp
  call {} %code(ptr %c, {} zeroinitializer)
  ret void
}

define weak_odr void @zs_clo_drop(ptr %c) {
entry:
  call void @zs.drop.clo(ptr %c)
  ret void
}
"""

/// zs.dup and zs.release in a program with threads, in place of the prelude's: a shared
/// object's count (negative) changes atomically, and its last reference frees it. The count is
/// read atomically, since another thread may be changing a shared one; a thread-local count
/// only this thread changes.
let private threadedDup =
    """define private void @zs.dup(ptr %p) alwaysinline {
entry:
  %rc = load atomic i_W, ptr %p monotonic, align HDR1
  %local = icmp sgt i_W %rc, 0
  br i1 %local, label %inc, label %other
inc:
  %n = add i_W %rc, 1
  store i_W %n, ptr %p
  br label %done
other:
  %shared = icmp slt i_W %rc, 0
  br i1 %shared, label %atomic, label %done
atomic:
  %old = atomicrmw sub ptr %p, i_W 1 monotonic
  br label %done
done:
  ret void
}"""

let private threadedRelease =
    """define private i1 @zs.release(ptr %p) alwaysinline {
entry:
  %rc = load atomic i_W, ptr %p monotonic, align HDR1
  %last = icmp eq i_W %rc, 1
  br i1 %last, label %yes, label %no
yes:
  ret i1 true
no:
  %more = icmp sgt i_W %rc, 1
  br i1 %more, label %dec, label %other
dec:
  %n = sub i_W %rc, 1
  store i_W %n, ptr %p
  ret i1 false
other:
  %shared = icmp slt i_W %rc, 0
  br i1 %shared, label %atomic, label %keep
atomic:
  %old = atomicrmw add ptr %p, i_W 1 acq_rel
  %gone = icmp eq i_W %old, -1
  ret i1 %gone
keep:
  ret i1 false
}"""

/// The text with a function's definition (from its first line to its closing brace) replaced.
let private replaceDef (text: string) (def: string) =
    let header = def.Substring(0, def.IndexOf '\n')
    let start = text.IndexOf header
    let stop = text.IndexOf("\n}", start) + 2
    text.Substring(0, start) + def + text.Substring stop

/// Primitives implemented by runtime functions: C name, result type, parameter types (unit
/// parameters omitted). Arguments are borrowed by the runtime and dropped after the call,
/// except those marked with !, whose reference the runtime keeps (the event loop's callbacks).
let private runtimePrims =
    dict
        [ "Loop.post", ("zs_loop_post", "void", [ "ptr!" ])
          "Loop.wait", ("zs_loop_wait", "void", [ "i_W"; "i1 zeroext"; "ptr!" ])
          "Loop.unwait", ("zs_loop_unwait", "void", [ "i_W"; "i1 zeroext" ])
          "Loop.timer", ("zs_loop_timer", "i_W", [ "i_W"; "ptr!" ])
          "Loop.untimer", ("zs_loop_untimer", "void", [ "i_W" ])
          "Loop.step", ("zs_loop_step", "zeroext i1", [])
          "Loop.close", ("zs_loop_close", "void", [])
          "Loop.enter", ("zs_loop_enter", "zeroext i1", [])
          "Loop.leave", ("zs_loop_leave", "void", [])
          "Loop.blocking", ("zs_loop_blocking", "void", [ "ptr!"; "ptr!" ])
          "Loop.spawn", ("zs_loop_spawn", "void", [ "ptr!" ])
          "Loop.expect", ("zs_loop_expect", "i_W", [ "ptr!" ])
          "Loop.fulfill", ("zs_loop_fulfill", "void", [ "i_W" ])
          "Tcp.listen", ("zs_tcp_listen", "i_W", [ "ptr"; "i_W" ])
          "Tcp.accept", ("zs_tcp_accept", "i_W", [ "i_W" ])
          "Tcp.connect", ("zs_tcp_connect", "i_W", [ "ptr"; "i_W" ])
          "Tcp.error", ("zs_socket_error", "i_W", [ "i_W" ])
          "Fd.read", ("zs_fd_read", "i_W", [ "i_W"; "ptr"; "i_W"; "i_W" ])
          "Fd.write", ("zs_fd_write", "i_W", [ "i_W"; "ptr"; "i_W"; "i_W" ])
          "Fd.close", ("zs_fd_close", "void", [ "i_W" ])
          "Errno.text", ("zs_error_text", "ptr", [ "i_W" ])
          "String.sub", ("zs_str_sub", "ptr", [ "ptr"; "i_W"; "i_W" ])
          "String.byte", ("zs_str_byte", "zeroext i8", [ "ptr"; "i_W" ])
          "String.ofByte", ("zs_str_of_byte", "ptr", [ "i8 zeroext" ])
          "String.indexOfFrom", ("zs_str_index_of", "i_W", [ "ptr"; "ptr"; "i_W" ])
          "String.trim", ("zs_str_trim", "ptr", [ "ptr" ])
          "String.toUpper", ("zs_str_upper", "ptr", [ "ptr" ])
          "String.toLower", ("zs_str_lower", "ptr", [ "ptr" ])
          "String.replace", ("zs_str_replace", "ptr", [ "ptr"; "ptr"; "ptr" ])
          "String.isFloat", ("zs_str_is_float", "zeroext i1", [ "ptr" ])
          "String.toFloat", ("zs_str_to_float", "double", [ "ptr" ])
          "Console.readLineRaw", ("zs_read_line", "ptr", [])
          "Console.eof", ("zs_eof", "zeroext i1", [])
          "eprintln", ("zs_eprintln", "void", [ "ptr" ])
          "Env.argc", ("zs_argc", "i_W", [])
          "Env.arg", ("zs_arg", "ptr", [ "i_W" ])
          "Env.has", ("zs_env_has", "zeroext i1", [ "ptr" ])
          "Env.get", ("zs_env_get", "ptr", [ "ptr" ])
          "Io.ok", ("zs_io_ok", "zeroext i1", [])
          "Io.error", ("zs_io_error", "ptr", [])
          "File.readRaw", ("zs_file_read", "ptr", [ "ptr" ])
          "File.writeRaw", ("zs_file_write", "void", [ "ptr"; "ptr" ])
          "File.appendRaw", ("zs_file_append", "void", [ "ptr"; "ptr" ])
          "File.exists", ("zs_file_exists", "zeroext i1", [ "ptr" ])
          "File.deleteRaw", ("zs_file_delete", "void", [ "ptr" ])
          "Dir.exists", ("zs_dir_exists", "zeroext i1", [ "ptr" ])
          "Dir.createRaw", ("zs_dir_create", "void", [ "ptr" ])
          "Dir.listRaw", ("zs_dir_list", "ptr", [ "ptr" ])
          "Process.runRaw", ("zs_process_run", "ptr", [ "ptr"; "ptr" ])
          "Process.code", ("zs_process_code", "i_W", []) ]

let private floatConst (ty: string) (f: float) =
    let v = if ty = "float" then float (float32 f) else f
    sprintf "0x%016X" (BitConverter.DoubleToInt64Bits v)

/// Emit DWARF debug info (zs build -g): line tables, functions, and local variables of
/// number and bool types.
let mutable debugInfo = false

/// Optimizing for size (zs build -Os): optsize functions, and loop versioning only for small loops.
let mutable optimizeSize = false

/// The target triple (zs build --target), "" for the host (x86-64 Linux). It decides the C ABI.
let mutable target = ""

/// The program has weak references or arenas: its objects are allocated and freed through the
/// runtime's checked functions (an arena's objects aren't malloc's; a dying object empties its
/// weak cell), and a cell Perceus reuses is reported. Other programs pay for none of it.
let mutable checkedHeap = false

/// [<Target>] and [<Multiversion>] functions (Program.targets), set by the driver.
let mutable targets = Dictionary<string, string list>()

/// --cpu's name (the driver sets it), for the check that an intrinsic's features are there.
let mutable cpu: string option = None

/// The program has SIMD vectors of 32 or 64 bytes, which need that alignment in memory: its
/// objects come from zs_alloc_wide, aligned to 64 bytes.
let mutable wideVectors = false

/// The program runs code on more than one thread (Parallel, Task.blocking): a value crossing to
/// another thread has its objects marked shared, whose counts change atomically (DESIGN §7.1).
/// Programs without threads have the plain counts.
let mutable threaded = false

// ponytail: a bare-metal target (cortex-m4, cortex-m0plus) passes C structs by value with the
// x86-64 rules, which are wrong for 32-bit ARM AAPCS; scalars and pointers are right

let private isArm64 () = target.StartsWith "aarch64"

/// The machine word (int, usize, reference counts, lengths): 32 bits on a Cortex-M, else 64.
let private is32 () = target.StartsWith "thumb"

let private pointerBytes () = if is32 () then 4 else 8

let private wordTy () = if is32 () then "i32" else "i64"

/// The module text with the word placeholders resolved (i_W, and the header sizes HDR1 = one
/// word, HDR2 = two). String constants (c"...") are left as written.
let private resolveWord (ir: string) =
    let w, h1, h2 = (if is32 () then "i32", "4", "8" else "i64", "8", "16")

    // -Os: optsize on every function definition. LLVM's unroller and vectorizer go by this
    // attribute (clang adds it to C functions), not by the -Os flag alone
    let sized (line: string) =
        if optimizeSize && line.StartsWith "define " && line.EndsWith "{" then
            match line.IndexOf " !dbg " with
            | i when i > 0 -> line.Substring(0, i) + " optsize" + line.Substring i
            | _ -> line.Substring(0, line.Length - 1) + "optsize {"
        else
            line

    ir.Split('\n')
    |> Array.map (fun line ->
        let line = sized line
        let cut = line.IndexOf " c\""
        let head, tail = if cut < 0 then line, "" else line.Substring(0, cut), line.Substring cut
        let head = if wideVectors then head.Replace("@zs_alloc(", "@zs_alloc_wide(") else head
        let head = if checkedHeap then head.Replace("@zs_alloc(", "@zs_alloc_checked(").Replace("@zs_free(", "@zs_free_checked(") else head
        head.Replace("i_W", w).Replace("HDR2", h2).Replace("HDR1", h1) + tail)
    |> String.concat "\n"

/// One of the LLVM modules a program is split into, compiled on its own (in parallel, and
/// taken from the cache when unchanged): the functions it defines, those of them the other
/// modules call, and whether it has the entry points (main, the tests, C exports).
type Part =
    { defines: HashSet<string>
      called: HashSet<string>
      entry: bool }

/// Compiles closure-converted, RC-annotated functions to textual LLVM IR, plus a C header for
/// the exported functions. With a part, only that part's functions are defined; the others it
/// calls are declared, and what must have one address in the program (top-level values, the
/// static cells of cases without fields) is defined in every part for the linker to merge.
let compile
    (types: Dictionary<string, TypeInfo>)
    (externs: Dictionary<string, ExternSig>)
    (exports: Export list)
    (tests: string list)
    (values: (string * string) list)
    (clayouts: HashSet<string>)
    (part: Part option)
    (funs: MFun list)
    : string * string =
    let shared = if part.IsSome then "linkonce_odr hidden" else "private" // one address in the whole program
    let prelude = if threaded then replaceDef (replaceDef prelude threadedDup) threadedRelease else prelude
    let top = StringBuilder(prelude.Replace("@zs.none = private constant", sprintf "@zs.none = %s constant" shared))
    let helpers = StringBuilder()
    let funcs = StringBuilder()
    let generated = HashSet<string>()
    let strings = Dictionary<string, string>()
    let fnTable = funs |> List.map (fun f -> f.name, f) |> dict
    let heap t = needsRc types t
    let defined (f: string) = part |> Option.forall (fun p -> p.defines.Contains f)
    let entry = part |> Option.forall (fun p -> p.entry)
    let referenced = HashSet<string>() // functions this module calls or makes closures of

    let sym (f: string) =
        referenced.Add f |> ignore
        "@\"zs." + f + "\""

    // a plain union's tag: a byte for an enum (no case has fields, so the tag is all there is,
    // and an array of them is a byte per element), else an i32: next to fields a byte saves no
    // space, and on a 32-bit chip it costs an extension at each test
    let tagTy (cases: (string * Ty list) list) =
        if cases.Length <= 256 && cases |> List.forall (fun (_, fs) -> fs.IsEmpty) then "i8" else "i32"

    let rec llty (t: Ty) =
        match prune t with
        | TCon(("int" | "usize"), []) -> wordTy () // the machine word
        | TCon(("i64" | "u64"), []) -> "i64"
        | TCon(("i32" | "u32" | "char"), []) -> "i32"
        | TCon(("i16" | "u16"), []) -> "i16"
        | TCon(("i8" | "u8"), []) -> "i8"
        | TCon("f64", []) -> "double"
        | TCon("f32", []) -> "float"
        | TCon("bool", []) -> "i1"
        | TCon("unit", []) -> "{}"
        | TCon(n, []) when isVectorName n ->
            let e, k = vectorInfo[n]
            sprintf "<%d x %s>" k (llty (tcon e))
        | TCon(n, []) when isMaskName n -> sprintf "<%d x i1>" maskLanes[n]
        | TCon(("cstr" | "cptr" | "string" | "array" | "ref" | "weak" | "ptr" | "fnptr" | "Atomic" | "Mutex" | "Channel"), _)
        | TFun _ -> "ptr"
        | TCon(n, _) when isDynName n -> "ptr"
        | TCon(n, args) ->
            match types[n].def with
            | RecordDef fs -> structTy (fs |> List.map (fun (_, ft) -> substGen args ft))
            | UnionDef cs when plainUnion types t ->
                // a plain union: the tag, then every case's fields in order (cases don't overlap)
                "{ " + tagTy cs + (cs |> List.collect snd |> List.map (fun ft -> ", " + llty (substGen args ft)) |> String.concat "") + " }"
            | UnionDef _ -> "ptr"
        | TTuple ts -> structTy ts
        | t -> failwithf "llty: unresolved type %s" (show t)

    and structTy ts =
        "{ " + (ts |> List.map llty |> String.concat ", ") + " }"

    let tyName t =
        match prune t with
        | TCon(n, []) -> n
        | _ -> ""

    let isFloat t = floats.Contains(tyName t)
    let isUnsigned t = unsigned.Contains(tyName t)

    /// A Z# object C holds as an opaque handle (Typer.isHandle): reference counted, a pointer,
    /// not a string.
    let isHandle (t: Ty) = heap t && llty t = "ptr" && tyName t <> "string"

    let union (t: Ty) =
        match prune t with
        | TCon(u, args) ->
            match types[u].def with
            | UnionDef cs -> u, cs |> List.map (fun (n, fs) -> n, List.map (substGen args) fs)
            | RecordDef _ -> failwith "not a union"
        | _ -> failwith "not a union"

    /// Where case `tag`'s field j sits in a plain union's struct: after the tag and the earlier cases' fields.
    let plainField (t: Ty) (tag: int) (j: int) =
        let _, cs = union t
        1 + (cs |> List.take tag |> List.sumBy (fun (_, fs) -> fs.Length)) + j

    let reps = Dictionary<string, UnionRep>()

    let repOf (t: Ty) =
        let key = showFull t

        match reps.TryGetValue key with
        | true, r -> r
        | _ ->
            let r = unionRep types t
            reps[key] <- r
            r

    /// A union type's representation; None for other types.
    let repOf' (t: Ty) =
        match prune t with
        | TCon(n, _) when (match types.TryGetValue n with
                           | true, { def = UnionDef _ } -> true
                           | _ -> false) -> Some(repOf t)
        | _ -> None

    let tagged (t: Ty) = repOf' t = Some(Boxed true)

    /// The cell of a boxed union's case: the count, the tag when the union has several cases
    /// with fields, then the fields.
    let cellTy (t: Ty) (tag: int) =
        let fields = snd (List.item tag (snd (union t)))
        "{ i_W" + (if tagged t then ", i32" else "") + (fields |> List.map (fun f -> ", " + llty f) |> String.concat "") + " }"

    /// Field j's index in a case's cell.
    let cellField (t: Ty) (j: int) = j + (if tagged t then 2 else 1)

    /// A case without fields of a boxed union: a static cell (count 0, so never freed) with the
    /// tag when the union's cells have one. A match tells it apart by its address.
    let nullary (t: Ty) (tag: int) =
        let u, _ = union t
        let g = sprintf "@\"ctor.%s.%d\"" u tag

        if generated.Add g then
            // not unnamed_addr: the address is what's compared
            if tagged t then
                top.AppendLine(sprintf "%s = %s constant { i_W, i32 } { i_W 0, i32 %d }" g shared tag) |> ignore
            else
                top.AppendLine(sprintf "%s = %s constant { i_W } { i_W 0 }" g shared) |> ignore

        g

    let cloTy (env: Ty list) =
        "{ i_W, ptr, ptr" + (env |> List.map (fun f -> ", " + llty f) |> String.concat "") + " }"

    // ------------------------------------------------------------ C ABI (x86-64 System V, AAPCS64)

    /// Size, alignment and scalar fields (offset, LLVM type) of a C-representable type.
    let rec cLayout (t: Ty) : int * int * (int * string) list =
        match llty t with
        | "i1"
        | "i8" -> 1, 1, [ 0, "i8" ]
        | "i16" -> 2, 2, [ 0, "i16" ]
        | "i32" -> 4, 4, [ 0, "i32" ]
        | "float" -> 4, 4, [ 0, "float" ]
        | "i64"
        | "double" as lt -> 8, 8, [ 0, lt ]
        | "ptr" -> pointerBytes (), pointerBytes (), [ 0, "ptr" ]
        | _ ->
            let fs =
                match prune t with
                | TCon(n, _) ->
                    match types[n].def with
                    | RecordDef fs -> List.map snd fs
                    | UnionDef _ -> []
                | _ -> []

            let mutable off = 0
            let mutable al = 1
            let scalars = ResizeArray()

            for ft in fs do
                let sz, a, sc = cLayout ft
                off <- (off + a - 1) / a * a

                for o, st in sc do
                    scalars.Add(off + o, st)

                off <- off + sz
                al <- max al a

            (off + al - 1) / al * al, al, List.ofSeq scalars

    /// AAPCS64 (aarch64): an HFA (1-4 fields, all float or all double) goes in float registers as
    /// an array; up to 16 bytes in one or two integer registers; anything bigger by reference.
    let abiArm64 (t: Ty) (isResult: bool) : Abi =
        let size, _, scalars = cLayout t
        let kinds = scalars |> List.map snd |> List.distinct

        match kinds with
        | [ ("float" | "double") as k ] when scalars.Length <= 4 -> Pieces [ sprintf "[%d x %s]" scalars.Length k ]
        | _ when size > 16 -> Memory
        | _ when size > 8 -> Pieces [ "[2 x i64]" ]
        | _ when isResult -> Pieces [ sprintf "i%d" (8 * size) ]
        | _ -> Pieces [ "i64" ]

    let abiFor (t: Ty) (isResult: bool) : Abi =
        match llty t with
        | lt when not (lt.StartsWith "{") -> Scalar
        | _ when isArm64 () -> abiArm64 t isResult
        | _ ->
            let size, _, scalars = cLayout t

            if size > 16 then
                Memory
            else
                Pieces
                    [ for k in 0 .. (size - 1) / 8 ->
                          let here = scalars |> List.filter (fun (o, _) -> o >= 8 * k && o < 8 * k + 8) |> List.map snd

                          if here |> List.forall (fun s -> s = "float" || s = "double") then
                              match here with
                              | [ "double" ] -> "double"
                              | [ "float"; "float" ] -> "<2 x float>"
                              | _ -> "float"
                          else
                              sprintf "i%d" (8 * min 8 (size - 8 * k)) ]

    let abiOf (t: Ty) = abiFor t false
    let cParam (t: Ty) = if llty t = "i1" then "i1 zeroext" else llty t

    /// How each parameter of a C function is passed. x86-64 System V: a struct goes in
    /// registers only when all its eightbytes fit in the ones left (6 for integers, less one
    /// for an sret pointer, and 8 for floating point); otherwise it goes on the stack whole, as
    /// a struct in memory does. A scalar past the registers goes on the stack by itself, which
    /// LLVM does. AAPCS64's rules for the arrays it is given are LLVM's own.
    let cModes (pars: Ty list) (sret: bool) : Abi list =
        let mutable ints = if sret then 5 else 6
        let mutable sses = 8

        pars
        |> List.map (fun t ->
            match prune t with
            | TCon("callback", _) ->
                ints <- ints - 2
                Scalar
            | TCon("unit", []) -> Scalar
            | _ ->
                match abiOf t with
                | Scalar ->
                    if llty t = "double" || llty t = "float" then sses <- sses - 1 else ints <- ints - 1
                    Scalar
                | Pieces ps when isArm64 () -> Pieces ps
                | Pieces ps ->
                    let ni = ps |> List.filter (fun p -> p.StartsWith "i") |> List.length
                    let ns = ps.Length - ni

                    if ni <= ints && ns <= sses then
                        ints <- ints - ni
                        sses <- sses - ns
                        Pieces ps
                    else
                        Memory
                | Memory -> Memory)

    /// A struct passed in memory: x86-64 copies it onto the stack (byval); AAPCS64 passes a
    /// pointer to a copy the caller made.
    let byval (t: Ty) =
        let _, a, _ = cLayout t
        if isArm64 () then "ptr" else sprintf "ptr byval(%s) align %d" (llty t) a

    /// LLVM return type for a C result, and whether it is returned through an sret pointer.
    let cRet (t: Ty) : string * bool =
        match prune t with
        | TCon("unit", []) -> "void", false
        | _ ->
            match abiFor t true with
            | Scalar -> (if llty t = "i1" then "zeroext i1" else llty t), false
            | Pieces [ p ] -> p, false
            | Pieces ps -> "{ " + String.concat ", " ps + " }", false
            | Memory -> "void", true

    /// A struct in memory, read or written as its eightbytes (padded: a piece may be read
    /// whole past a struct's last byte, such as an i_W for a 4-byte struct).
    let slotFor (em: Emitter) (t: Ty) =
        let slot = "%" + em.Fresh "abi"
        em.Alloca(sprintf "%s = alloca { %s, [16 x i8] }, align 8" slot (llty t))
        slot

    let toPieces (em: Emitter) (t: Ty) (v: string) (pieces: string list) =
        let slot = slotFor em t
        em.Emit(sprintf "store %s %s, ptr %s" (llty t) v slot)

        pieces
        |> List.mapi (fun k pt ->
            let p = em.Instr(sprintf "getelementptr i8, ptr %s, i_W %d" slot (8 * k))
            pt, em.Instr(sprintf "load %s, ptr %s" pt p))

    let fromPieces (em: Emitter) (t: Ty) (pieces: (string * string) list) =
        let slot = slotFor em t

        pieces
        |> List.iteri (fun k (pt, pv) ->
            let p = em.Instr(sprintf "getelementptr i8, ptr %s, i_W %d" slot (8 * k))
            em.Emit(sprintf "store %s %s, ptr %s" pt pv p))

        em.Instr(sprintf "load %s, ptr %s" (llty t) slot)

    /// The LLVM parameter types (with attributes) a C parameter of this type becomes, passed so.
    let cParamsAs (t: Ty) (mode: Abi) : string list =
        match prune t with
        | TCon("callback", _) -> [ "ptr"; "ptr" ]
        | TCon("unit", []) -> []
        | _ ->
            match mode with
            | Scalar -> [ cParam t ]
            | Pieces ps -> ps
            | Memory -> [ byval t ]

    /// The LLVM parameters of a C function taking these (after an sret pointer, if it has one).
    let cParamList (pars: Ty list) (sret: bool) = List.map2 cParamsAs pars (cModes pars sret) |> List.concat

    let sizeOf (em: Emitter) (ty: string) =
        let p = em.Instr(sprintf "getelementptr %s, ptr null, i32 1" ty)
        em.Instr(sprintf "ptrtoint ptr %s to i_W" p)

    let strGlobal (s: string) =
        match strings.TryGetValue s with
        | true, g -> g
        | _ ->
            let bytes = Encoding.UTF8.GetBytes s

            let enc =
                bytes
                |> Array.map (fun b ->
                    if b >= 32uy && b < 127uy && b <> '"'B && b <> '\\'B then
                        string (char b)
                    else
                        sprintf "\\%02X" b)
                |> String.concat ""

            let g = sprintf "@.str.%d" strings.Count

            top.AppendLine(
                sprintf
                    "%s = private unnamed_addr constant { i_W, i_W, [%d x i8] } { i_W 0, i_W %d, [%d x i8] c\"%s\\00\" }"
                    g
                    (bytes.Length + 1)
                    bytes.Length
                    (bytes.Length + 1)
                    enc
            )
            |> ignore

            strings[s] <- g
            g

    /// The bytes of a string literal, as a C string.
    let cstrConst (s: string) =
        sprintf
            "getelementptr inbounds ({ i_W, i_W, [%d x i8] }, ptr %s, i32 0, i32 2)"
            (Encoding.UTF8.GetByteCount s + 1)
            (strGlobal s)

    let panicWith (em: Emitter) (msg: string) =
        em.Emit(sprintf "call void @zs_panic_c(ptr %s)" (cstrConst msg))
        em.Emit "unreachable"

    /// Branches to a panic unless cond holds.
    let check (em: Emitter) (cond: string) (msg: string) =
        let ok, bad = em.Fresh "ok", em.Fresh "fail"
        em.Emit(sprintf "br i1 %s, label %%%s, label %%%s" cond ok bad)
        em.Label bad
        panicWith em msg
        em.Label ok

    /// A 64-bit value as a word-sized hash: itself, or on a 32-bit chip its halves xor'ed.
    let foldWord (em: Emitter) (v: string) =
        if is32 () then
            let hi = em.Instr(sprintf "lshr i64 %s, 32" v)
            em.Instr(sprintf "trunc i64 %s to i32" (em.Instr(sprintf "xor i64 %s, %s" v hi)))
        else
            v

    /// A call to an LLVM intrinsic, declared the first time: name (llvm.sqrt.v4f32), result type,
    /// typed arguments.
    let intrinsic (em: Emitter) (name: string) (ret: string) (args: (string * string) list) (flags: string) =
        let decl = sprintf "declare %s @%s(%s)" ret name (args |> List.map fst |> String.concat ", ")

        if generated.Add decl then
            helpers.Append(decl + "\n") |> ignore

        em.Instr(sprintf "call %s%s @%s(%s)" flags ret name (args |> List.map (fun (t, v) -> t + " " + v) |> String.concat ", "))

    /// A SIMD type's lanes and their LLVM type (a mask's are i1), and LLVM's name for it in an
    /// intrinsic's (v4f32).
    let simdShape (t: Ty) =
        let n = tyName t

        let e, k =
            match vectorInfo.TryGetValue n with
            | true, (e, k) -> e, k
            | _ -> "bool", maskLanes[n]

        let et = llty (tcon e)
        let suffix = match et with
                     | "float" -> "f32"
                     | "double" -> "f64"
                     | t -> t
        e, k, et, sprintf "v%d%s" k suffix

    /// x in every lane of a <k x et>.
    let splat (em: Emitter) (k: int) (et: string) (x: string) =
        let one = em.Instr(sprintf "insertelement <%d x %s> poison, %s %s, i32 0" k et et x)
        em.Instr(sprintf "shufflevector <%d x %s> %s, <%d x %s> poison, <%d x i32> zeroinitializer" k et one k et k)

    /// Whether any lane of a <k x i1> is true.
    let anyLane (em: Emitter) (k: int) (m: string) =
        intrinsic em (sprintf "llvm.vector.reduce.or.v%di1" k) "i1" [ sprintf "<%d x i1>" k, m ] ""

    /// + - * / % on SIMD vectors, lane by lane (integers wrap, as SIMD instructions do, and
    /// integer division checks every lane's divisor), bitwise operators on integer vectors and
    /// masks (a shift's amount, an int, for every lane), and = <> on whole vectors.
    let simdBin (em: Emitter) (op: string) (t: Ty) (a: string) (b: string) (fast: bool) =
        let e, k, et, _ = simdShape t
        let lt = llty t
        let isF = floats.Contains e
        let uns = unsigned.Contains e
        let op = if op.StartsWith "wrap" then op.Substring 4 else op

        match op with
        | "="
        | "<>" ->
            let c = em.Instr(sprintf "%s %s %s, %s" (if isF then "fcmp oeq" else "icmp eq") lt a b)
            let all = intrinsic em (sprintf "llvm.vector.reduce.and.v%di1" k) "i1" [ sprintf "<%d x i1>" k, c ] ""
            if op = "=" then all else em.Instr(sprintf "xor i1 %s, true" all)
        | "&&&" -> em.Instr(sprintf "and %s %s, %s" lt a b)
        | "|||" -> em.Instr(sprintf "or %s %s, %s" lt a b)
        | "^^^" -> em.Instr(sprintf "xor %s %s, %s" lt a b)
        | "<<<"
        | ">>>" ->
            // modulo the lane's width, as for one integer
            let bits = int (et.Substring 1)
            let w = llty tInt
            let wbits = int (w.Substring 1)

            let amount =
                if wbits = bits then b
                elif wbits > bits then em.Instr(sprintf "trunc %s %s to %s" w b et)
                else em.Instr(sprintf "sext %s %s to %s" w b et)

            let amount = em.Instr(sprintf "and %s %s, %d" et amount (bits - 1))
            let instr = if op = "<<<" then "shl" elif uns then "lshr" else "ashr"
            em.Instr(sprintf "%s %s %s, %s" instr lt a (splat em k et amount))
        | _ when isF -> em.Instr(sprintf "%s%s %s %s, %s" farith[op] (if fast then " fast" else "") lt a b)
        | "+"
        | "-"
        | "*" -> em.Instr(sprintf "%s %s %s, %s" arith[op] lt a b)
        | _ ->
            // / and %: no lane divides by zero, nor MIN by -1 (which doesn't fit)
            let zero = em.Instr(sprintf "icmp eq %s %s, zeroinitializer" lt b)
            check em (em.Instr(sprintf "xor i1 %s, true" (anyLane em k zero))) "division by zero"

            if not uns then
                let bits = int (et.Substring 1)
                let minv = if bits = 64 then string System.Int64.MinValue else string (-(1L <<< (bits - 1)))
                let isMin = em.Instr(sprintf "icmp eq %s %s, %s" lt a (splat em k et minv))
                let isNeg1 = em.Instr(sprintf "icmp eq %s %s, %s" lt b (splat em k et "-1"))
                let bad = em.Instr(sprintf "and <%d x i1> %s, %s" k isMin isNeg1)
                check em (em.Instr(sprintf "xor i1 %s, true" (anyLane em k bad))) "integer overflow"

            let instr = (if uns then "u" else "s") + (if op = "/" then "div" else "rem")
            em.Instr(sprintf "%s %s %s, %s" instr lt a b)

    /// Integer + - * that panics on overflow (llvm.*.with.overflow), in every build.
    let checkedArith (em: Emitter) (op: string) (unsigned: bool) (lt: string) (a: string) (b: string) =
        let name = sprintf "llvm.%s%s.with.overflow.%s" (if unsigned then "u" else "s") arith[op] lt
        let decl = sprintf "declare { %s, i1 } @%s(%s, %s)" lt name lt lt

        if generated.Add decl then
            helpers.Append(decl + "\n") |> ignore

        let r = em.Instr(sprintf "call { %s, i1 } @%s(%s %s, %s %s)" lt name lt a lt b)
        let over = em.Instr(sprintf "extractvalue { %s, i1 } %s, 1" lt r)
        check em (em.Instr(sprintf "xor i1 %s, true" over)) "integer overflow"
        em.Instr(sprintf "extractvalue { %s, i1 } %s, 0" lt r)

    // ------------------------------------------------------------ reference counting helpers

    let rec dupValue (em: Emitter) (t: Ty) (v: string) =
        if heap t then
            match llty t with
            | "ptr" -> em.Emit(sprintf "call void @zs.dup(ptr %s)" v)
            | lt -> em.Emit(sprintf "call void %s(%s %s)" (structHelper "dup" t) lt v)

    and dropValue (em: Emitter) (t: Ty) (v: string) =
        if heap t then
            em.Emit(sprintf "call void %s(%s %s)" (dropFn t) (llty t) v)

    /// dup/drop for a struct value: applies to each field that holds a reference.
    and structHelper (kind: string) (t: Ty) =
        let name = sprintf "@\"%s.%s\"" kind (showFull t)

        if generated.Add name then
            let fields =
                match prune t with
                | TTuple ts -> ts
                | TCon(n, args) ->
                    match types[n].def with
                    | RecordDef fs -> fs |> List.map (fun (_, ft) -> substGen args ft)
                    | UnionDef _ -> []
                | _ -> []

            let em = Emitter()

            fields
            |> List.iteri (fun i ft ->
                if heap ft then
                    let f = em.Instr(sprintf "extractvalue %s %%v, %d" (llty t) i)

                    match kind with
                    | "dup" -> dupValue em ft f
                    | "share" -> shareValue em ft f
                    | _ -> dropValue em ft f)

            em.Emit "ret void"
            helpers.Append(sprintf "define private void %s(%s %%v) {\n%s}\n\n" name (llty t) em.Body) |> ignore

        name

    /// Marks a value's objects shared before it crosses to another thread (DESIGN §7.1): a
    /// thread-local count n becomes -n, which every thread then changes atomically. The walk
    /// stops at static objects and at shared ones, whose objects are shared already.
    and shareValue (em: Emitter) (t: Ty) (v: string) =
        if heap t then
            match llty t with
            | "ptr" -> em.Emit(sprintf "call void %s(ptr %s)" (shareFn t) v)
            | lt -> em.Emit(sprintf "call void %s(%s %s)" (structHelper "share" t) lt v)

    and shareFn (t: Ty) : string =
        let name = sprintf "@\"share.%s\"" (showFull t)

        if generated.Add name then
            let em = Emitter()

            match repOf' t with
            | Some(Niche(_, payload)) ->
                // the payload itself, or the static @zs.none
                em.Emit(sprintf "musttail call void %s(ptr %%p)" (shareFn payload))
                em.Emit "ret void"
            | _ ->
                let rc = em.Instr "load atomic i_W, ptr %p monotonic, align HDR1"
                em.Emit(sprintf "br i1 %s, label %%mark, label %%done" (em.Instr(sprintf "icmp sgt i_W %s, 0" rc)))
                em.Label "mark"
                em.Emit(sprintf "store i_W %s, ptr %%p" (em.Instr(sprintf "sub i_W 0, %s" rc)))

                match prune t with
                | TFun _ ->
                    // what the closure captured: its description's share function
                    let info = em.Instr(sprintf "load ptr, ptr %s" (em.Instr "getelementptr { i_W, ptr, ptr }, ptr %p, i32 0, i32 2"))
                    let f = em.Instr(sprintf "load ptr, ptr %s" (em.Instr(sprintf "getelementptr { ptr, i32, ptr, ptr }, ptr %s, i32 0, i32 3" info)))
                    em.Emit(sprintf "musttail call void %s(ptr %%p)" f)
                    em.Emit "ret void"
                | TCon("array", [ el ]) when heap el ->
                    let len = em.Instr(sprintf "load i_W, ptr %s" (em.Instr "getelementptr { i_W, i_W }, ptr %p, i32 0, i32 1"))
                    em.Emit "br label %loop"
                    em.Label "loop"
                    let i = em.Tmp()
                    em.Emit(sprintf "%s = phi i_W [ 0, %%mark ], [ %%next, %%body ]" i)
                    em.Emit(sprintf "br i1 %s, label %%body, label %%done" (em.Instr(sprintf "icmp slt i_W %s, %s" i len)))
                    em.Label "body"
                    let ep = em.Instr(sprintf "getelementptr { i_W, i_W, [0 x %s] }, ptr %%p, i32 0, i32 2, i_W %s" (llty el) i)
                    shareValue em el (em.Instr(sprintf "load %s, ptr %s" (llty el) ep))
                    em.Emit(sprintf "%%next = add i_W %s, 1" i)
                    em.Emit "br label %loop"
                | TCon(n, _) when (match types.TryGetValue n with
                                   | true, { def = UnionDef _ } -> true
                                   | _ -> false) ->
                    // the case's fields; the last pointer field by a tail call, so a long list
                    // is walked in a loop
                    let _, cases = union t
                    let withRefs = cases |> List.indexed |> List.filter (fun (_, (_, fs)) -> List.exists heap fs)

                    if tagged t then
                        let tag = em.Instr(sprintf "load i32, ptr %s" (em.Instr "getelementptr { i_W, i32 }, ptr %p, i32 0, i32 1"))
                        em.Emit(sprintf "switch i32 %s, label %%done [ %s ]" tag (withRefs |> List.map (fun (i, _) -> sprintf "i32 %d, label %%case%d" i i) |> String.concat " "))
                    else
                        match withRefs with
                        | (i, _) :: _ -> em.Emit(sprintf "br label %%case%d" i)
                        | [] -> em.Emit "br label %done"

                    for i, (_, fs) in withRefs do
                        em.Label(sprintf "case%d" i)
                        let cell = cellTy t i

                        let refs =
                            fs
                            |> List.indexed
                            |> List.filter (snd >> heap)
                            |> List.map (fun (j, ft) -> ft, em.Instr(sprintf "load %s, ptr %s" (llty ft) (em.Instr(sprintf "getelementptr %s, ptr %%p, i32 0, i32 %d" cell (cellField t j)))))

                        let init, (lt, lv) = List.splitAt (refs.Length - 1) refs |> fun (a, b) -> a, b.Head

                        for ft, v in init do
                            shareValue em ft v

                        if llty lt = "ptr" then
                            em.Emit(sprintf "musttail call void %s(ptr %s)" (shareFn lt) lv)
                            em.Emit "ret void"
                        else
                            shareValue em lt lv
                            em.Emit "br label %done"
                | _ -> em.Emit "br label %done" // a string; an Atomic, a Mutex or a Channel, whose contents are shared already

            em.Label "done"
            em.Emit "ret void"
            helpers.Append(sprintf "define private void %s(ptr %%p) {\n%s}\n\n" name em.Body) |> ignore

        name

    /// @"unique.array<T>"(a): `a` when it holds the only reference, else a copy of it (with
    /// `a`'s reference given up). Copy-on-write for arrays.
    and uniqueFn (t: Ty) (always: bool) : string =
        let el =
            match prune t with
            | TCon("array", [ el ]) -> el
            | _ -> failwith "not an array"

        let name = sprintf "@\"%s.%s\"" (if always then "copy" else "unique") (showFull t)

        if not always && generated.Add name then
            // inlined at every write: a count test, and the copy (out of line, cold) only if shared
            let copy = uniqueFn t true
            let em = Emitter()
            let rc = em.Instr(if threaded then "load atomic i_W, ptr %p monotonic, align HDR1" else "load i_W, ptr %p")
            em.Emit(sprintf "br i1 %s, label %%same, label %%copy, !prof !{!\"branch_weights\", i32 2000, i32 1}" (em.Instr(sprintf "icmp eq i_W %s, 1" rc)))
            em.Label "same"
            em.Emit "ret ptr %p"
            em.Label "copy"
            em.Emit(sprintf "%%c = call ptr %s(ptr %%p)" copy)
            em.Emit "ret ptr %c"
            helpers.Append(sprintf "define private ptr %s(ptr %%p) alwaysinline {\n%s}\n\n" name em.Body) |> ignore
        elif always && generated.Add name then
            let em = Emitter()
            let at = sprintf "{ i_W, i_W, [0 x %s] }" (llty el)

            let len = em.Instr(sprintf "load i_W, ptr %s" (em.Instr "getelementptr { i_W, i_W }, ptr %p, i32 0, i32 1"))
            let es = sizeOf em (llty el)
            let bytes = em.Instr(sprintf "add i_W HDR2, %s" (em.Instr(sprintf "mul i_W %s, %s" len es)))
            let b = em.Instr(sprintf "call ptr @zs_alloc(i_W %s)" bytes)
            // the length and elements: the count is the copy's own (and another thread may be
            // changing the original's)
            let dst = em.Instr(sprintf "getelementptr i8, ptr %s, i_W HDR1" b)
            let src = em.Instr "getelementptr i8, ptr %p, i_W HDR1"
            em.Emit(sprintf "call void @llvm.memcpy.p0.p0.i_W(ptr %s, ptr %s, i_W %s, i1 false)" dst src (em.Instr(sprintf "sub i_W %s, HDR1" bytes)))
            em.Emit(sprintf "store i_W 1, ptr %s" b)

            if heap el then
                // the copy holds its own reference to every element
                em.Emit "br label %loop"
                em.Label "loop"
                let i = em.Tmp()
                em.Emit(sprintf "%s = phi i_W [ 0, %%entry ], [ %%next, %%body ]" i)
                em.Emit(sprintf "br i1 %s, label %%body, label %%end" (em.Instr(sprintf "icmp slt i_W %s, %s" i len)))
                em.Label "body"
                let ep = em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 2, i_W %s" at b i)
                dupValue em el (em.Instr(sprintf "load %s, ptr %s" (llty el) ep))
                em.Emit(sprintf "%%next = add i_W %s, 1" i)
                em.Emit "br label %loop"
                em.Label "end"

            dropValue em t "%p"
            em.Emit(sprintf "ret ptr %s" b)
            helpers.Append(sprintf "define private ptr %s(ptr %%p) noinline cold {\n%s}\n\n" name em.Body) |> ignore

        name

    and dropFn (t: Ty) : string =
        match prune t with
        | TFun _ -> "@zs.drop.clo"
        | TCon(n, _) when isDynName n -> "@zs.drop.dyn"
        | TCon("weak", _) ->
            // a weak reference's cell: the runtime frees it (and forgets its object)
            if generated.Add "@zs.drop.weak" then
                helpers.Append "define private void @zs.drop.weak(ptr %p) {\nentry:\n  %last = call i1 @zs.release(ptr %p)\n  br i1 %last, label %free, label %done\nfree:\n  call void @zs_weak_free(ptr %p)\n  ret void\ndone:\n  ret void\n}\n\n" |> ignore

            "@zs.drop.weak"
        | TCon("string", _) -> "@zs.drop.str"
        | TTuple _ -> structHelper "drop" t
        | TCon(n, _) when (match types.TryGetValue n with
                           | true, { def = RecordDef _ } -> true
                           | _ -> false) -> structHelper "drop" t
        | pt ->
            let name = sprintf "@\"drop.%s\"" (showFull pt)

            if generated.Add name then
                let em = Emitter()

                match repOf' pt with
                | Some(Niche(_, payload)) ->
                    // the payload itself, or @zs.none (static: its count is never changed)
                    em.Emit(sprintf "musttail call void %s(ptr %%p)" (dropFn payload))
                    em.Emit "ret void"
                | _ ->
                    let last = em.Instr "call i1 @zs.release(ptr %p)"
                    em.Emit(sprintf "br i1 %s, label %%free, label %%done" last)
                    em.Label "free"

                    match pt with
                    | TCon("array", [ el ]) ->
                        if heap el then
                            let lenp = em.Instr "getelementptr { i_W, i_W }, ptr %p, i32 0, i32 1"
                            let len = em.Instr(sprintf "load i_W, ptr %s" lenp)
                            em.Emit "br label %loop"
                            em.Label "loop"
                            let i = em.Tmp()
                            let next = em.Tmp()
                            let back = em.Fresh "next"
                            em.Emit(sprintf "%s = phi i_W [ 0, %%free ], [ %s, %%%s ]" i next back)
                            let c = em.Instr(sprintf "icmp slt i_W %s, %s" i len)
                            em.Emit(sprintf "br i1 %s, label %%body, label %%end" c)
                            em.Label "body"
                            let ep = em.Instr(sprintf "getelementptr { i_W, i_W, [0 x %s] }, ptr %%p, i32 0, i32 2, i_W %s" (llty el) i)
                            dropValue em el (em.Instr(sprintf "load %s, ptr %s" (llty el) ep))
                            em.Emit(sprintf "br label %%%s" back)
                            em.Label back
                            em.Emit(sprintf "%s = add i_W %s, 1" next i)
                            em.Emit "br label %loop"
                            em.Label "end"

                        em.Emit "call void @zs_free(ptr %p)"
                        em.Emit "ret void"
                    | TCon("ref", [ v ]) ->
                        let vp = em.Instr(sprintf "getelementptr { i_W, %s }, ptr %%p, i32 0, i32 1" (llty v))
                        let x = em.Instr(sprintf "load %s, ptr %s" (llty v) vp)
                        em.Emit "call void @zs_free(ptr %p)"
                        dropValue em v x
                        em.Emit "ret void"
                    | TCon("Atomic", _) ->
                        em.Emit "call void @zs_free(ptr %p)"
                        em.Emit "ret void"
                    | TCon("Mutex", [ v ]) ->
                        let vp = em.Instr(sprintf "getelementptr { i_W, i32, %s }, ptr %%p, i32 0, i32 2" (llty v))
                        let x = em.Instr(sprintf "load %s, ptr %s" (llty v) vp)
                        em.Emit "call void @zs_free(ptr %p)"
                        dropValue em v x
                        em.Emit "ret void"
                    | TCon("Channel", _) ->
                        // the runtime's: what's still in it goes with the drop function it was made with
                        em.Emit "call void @zs_chan_free(ptr %p)"
                        em.Emit "ret void"
                    | _ ->
                        let _, cases = union pt
                        let withRefs = cases |> List.indexed |> List.filter (fun (_, (_, fs)) -> List.exists heap fs)

                        if tagged pt then
                            let tagp = em.Instr "getelementptr { i_W, i32 }, ptr %p, i32 0, i32 1"
                            let tag = em.Instr(sprintf "load i32, ptr %s" tagp)

                            let targets =
                                withRefs |> List.map (fun (i, _) -> sprintf "i32 %d, label %%case%d" i i) |> String.concat " "

                            em.Emit(sprintf "switch i32 %s, label %%plain [ %s ]" tag targets)
                        else
                            // the one case with fields
                            match withRefs with
                            | (i, _) :: _ -> em.Emit(sprintf "br label %%case%d" i)
                            | [] -> em.Emit "br label %plain"

                        for i, (_, fs) in withRefs do
                            em.Label(sprintf "case%d" i)
                            let cell = cellTy pt i

                            let refs =
                                fs
                                |> List.indexed
                                |> List.filter (snd >> heap)
                                |> List.map (fun (j, ft) ->
                                    let fp = em.Instr(sprintf "getelementptr %s, ptr %%p, i32 0, i32 %d" cell (cellField pt j))
                                    ft, em.Instr(sprintf "load %s, ptr %s" (llty ft) fp))

                            em.Emit "call void @zs_free(ptr %p)"
                            let init, (lt, lv) = List.splitAt (refs.Length - 1) refs |> fun (a, b) -> a, b.Head

                            for ft, v in init do
                                dropValue em ft v

                            // the last field is dropped by a tail call, so long lists free iteratively
                            if llty lt = "ptr" then
                                em.Emit(sprintf "musttail call void %s(ptr %s)" (dropFn lt) lv)
                            else
                                dropValue em lt lv

                            em.Emit "ret void"

                        em.Label "plain"
                        em.Emit "call void @zs_free(ptr %p)"
                        em.Emit "ret void"

                em.Label "done"
                em.Emit "ret void"
                helpers.Append(sprintf "define private void %s(ptr %%p) {\n%s}\n\n" name em.Body) |> ignore

            name

    // ------------------------------------------------------------ closures

    /// Allocates a closure for stage k of f holding the given environment values (moved in).
    let rec allocClosure (em: Emitter) (f: string) (env: (Ty * string) list) =
        let k = env.Length
        let cell = cloTy (List.map fst env)
        let c = em.Instr(sprintf "call ptr @zs_alloc(i_W %s)" (sizeOf em cell))
        em.Emit(sprintf "store i_W 1, ptr %s" c)
        let cp = em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 1" cell c)
        em.Emit(sprintf "store ptr %s, ptr %s" (stub f k) cp)
        let ip = em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 2" cell c)
        em.Emit(sprintf "store ptr %s, ptr %s" (info f k) ip)

        env
        |> List.iteri (fun i (t, v) ->
            let fp = em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 %d" cell c (i + 3))
            em.Emit(sprintf "store %s %s, ptr %s" (llty t) v fp))

        c

    /// Loads a closure's environment (borrowed).
    and loadEnv (em: Emitter) (tys: Ty list) =
        let cell = cloTy tys

        tys
        |> List.mapi (fun i t ->
            let fp = em.Instr(sprintf "getelementptr %s, ptr %%clo, i32 0, i32 %d" cell (i + 3))
            t, em.Instr(sprintf "load %s, ptr %s" (llty t) fp))

    /// Code for a closure of f that already holds its first k parameters: takes parameter k.
    and stub (f: string) (k: int) : string =
        let name = sprintf "@\"clo.%s.%d\"" f k

        if generated.Add name then
            let fd = fnTable[f]
            let ps = fd.pars |> List.map snd
            let argTy = List.item k ps
            let last = k + 1 = ps.Length
            let retTy = if last then llty fd.ret else "ptr"
            let em = Emitter()
            let env = loadEnv em (List.take k ps)

            for t, v in env do
                dupValue em t v

            let args = env @ [ argTy, "%arg" ]

            if last then
                let argv = args |> List.map (fun (t, v) -> sprintf "%s %s" (llty t) v) |> String.concat ", "
                let r = em.Instr(sprintf "tail call %s %s(%s)" retTy (sym f) argv)
                em.Emit(sprintf "ret %s %s" retTy r)
            else
                em.Emit(sprintf "ret ptr %s" (allocClosure em f args))

            helpers.Append(sprintf "define private %s %s(ptr %%clo, %s %%arg) {\n%s}\n\n" retTy name (llty argTy) em.Body)
            |> ignore

        name

    /// What a closure of f holding k parameters is, for its users: its drop function, the
    /// number of parameters it still takes, and code taking all of them at once.
    and info (f: string) (k: int) : string =
        let name = sprintf "@\"cloinfo.%s.%d\"" f k

        if generated.Add name then
            let n = fnTable[f].pars.Length
            let share = if threaded then shareStub f k else "null"
            let line = sprintf "%s = private unnamed_addr constant { ptr, i32, ptr, ptr } { ptr %s, i32 %d, ptr %s, ptr %s }" name (dropStub f k) (n - k) (full f k) share
            top.AppendLine line |> ignore

        name

    /// The objects a closure of f holding k parameters captured, marked shared (shareFn of a
    /// closure has marked the closure itself).
    and shareStub (f: string) (k: int) : string =
        let name = sprintf "@\"closhare.%s.%d\"" f k

        if generated.Add name then
            let em = Emitter()

            for t, v in loadEnv em (fnTable[f].pars |> List.map snd |> List.take k) do
                shareValue em t v

            em.Emit "ret void"
            helpers.Append(sprintf "define private void %s(ptr %%clo) {\n%s}\n\n" name em.Body) |> ignore

        name

    /// Code for a closure of f holding its first k parameters that takes all the others at once.
    and full (f: string) (k: int) : string =
        let fd = fnTable[f]

        if k + 1 = fd.pars.Length then
            stub f k
        else
            let name = sprintf "@\"cloN.%s.%d\"" f k

            if generated.Add name then
                let ps = fd.pars |> List.map snd
                let em = Emitter()
                let env = loadEnv em (List.take k ps)

                for t, v in env do
                    dupValue em t v

                let rest = ps |> List.skip k |> List.mapi (fun i t -> t, sprintf "%%a%d" i)
                let argv = env @ rest |> List.map (fun (t, v) -> sprintf "%s %s" (llty t) v) |> String.concat ", "
                let rt = llty fd.ret
                let r = em.Instr(sprintf "tail call %s %s(%s)" rt (sym f) argv)
                em.Emit(sprintf "ret %s %s" rt r)
                let pars = rest |> List.map (fun (t, v) -> sprintf "%s %s" (llty t) v) |> String.concat ", "
                helpers.Append(sprintf "define private %s %s(ptr %%clo, %s) {\n%s}\n\n" rt name pars em.Body) |> ignore

            name

    and dropStub (f: string) (k: int) : string =
        let name = sprintf "@\"clodrop.%s.%d\"" f k

        if generated.Add name then
            let em = Emitter()
            let env = loadEnv em (fnTable[f].pars |> List.map snd |> List.take k)
            em.Emit "call void @zs_free(ptr %clo)"

            for t, v in env do
                dropValue em t v

            em.Emit "ret void"
            helpers.Append(sprintf "define private void %s(ptr %%clo) {\n%s}\n\n" name em.Body) |> ignore

        name

    /// The vtable of a dyn Trait over type t: a function freeing the dyn (and dropping the value
    /// it holds), then the trait's methods for t.
    let vtable (tr: string) (t: Ty) (entries: string list) =
        let name = sprintf "@\"vt.%s.%s\"" tr (showFull t)

        if generated.Add name then
            let drop = sprintf "@\"dyndrop.%s\"" (showFull t)

            if generated.Add drop then
                let em = Emitter()
                let v = em.Instr(sprintf "load %s, ptr %s" (llty t) (em.Instr(sprintf "getelementptr { i_W, ptr, %s }, ptr %%p, i32 0, i32 2" (llty t))))
                em.Emit "call void @zs_free(ptr %p)"
                dropValue em t v
                em.Emit "ret void"
                helpers.Append(sprintf "define private void %s(ptr %%p) {\n%s}\n\n" drop em.Body) |> ignore

            let slots = ("ptr " + drop) :: (entries |> List.map (fun f -> "ptr " + sym f))
            top.AppendLine(sprintf "%s = private unnamed_addr constant { %s } { %s }" name (slots |> List.map (fun _ -> "ptr") |> String.concat ", ") (String.concat ", " slots)) |> ignore

        name

    /// The thread pool's runner for a job whose closure gives a T (runtime/rt.c, zs_par_fork):
    /// calls it, stores its result where the job keeps it, and gives up the closure.
    let parRunner (rt: Ty) =
        let name = sprintf "@\"parrun.%s\"" (showFull rt)

        if generated.Add name then
            let em = Emitter()
            let code = em.Instr(sprintf "load ptr, ptr %s" (em.Instr "getelementptr { i_W, ptr }, ptr %clo, i32 0, i32 1"))
            let r = em.Instr(sprintf "call %s %s(ptr %%clo, {} zeroinitializer)" (llty rt) code)
            em.Emit(sprintf "store %s %s, ptr %%out" (llty rt) r)
            em.Emit "call void @zs.drop.clo(ptr %clo)"
            em.Emit "ret void"
            helpers.Append(sprintf "define private void %s(ptr %%clo, ptr %%out) {\n%s}\n\n" name em.Body) |> ignore

        name

    /// A function dropping the T a channel's slot holds (what's left in one when it's freed),
    /// or null when a T holds no reference counts.
    let slotDrop (t: Ty) =
        if not (heap t) then
            "null"
        else
            let name = sprintf "@\"slotdrop.%s\"" (showFull t)

            if generated.Add name then
                let em = Emitter()
                dropValue em t (em.Instr(sprintf "load %s, ptr %%slot" (llty t)))
                em.Emit "ret void"
                helpers.Append(sprintf "define private void %s(ptr %%slot) {\n%s}\n\n" name em.Body) |> ignore

            name

    let staticClosure (f: string) =
        let name = sprintf "@\"cloS.%s\"" f

        if generated.Add name then
            top.AppendLine(sprintf "%s = private unnamed_addr constant { i_W, ptr, ptr } { i_W 0, ptr %s, ptr %s }" name (stub f 0) (info f 0))
            |> ignore

        name

    /// C entry point for a callback<A -> R>: R thunk(void* user, A) calls the closure `user`.
    let thunk (f: Ty) : string =
        let a, r =
            match prune f with
            | TFun(a, r) -> a, r
            | _ -> failwith "callback type"

        let name = sprintf "@\"cb.%s\"" (showFull f)

        if generated.Add name then
            let em = Emitter()
            let unitArg = prune a = tUnit
            let cp = em.Instr "getelementptr { i_W, ptr }, ptr %user, i32 0, i32 1"
            let code = em.Instr(sprintf "load ptr, ptr %s" cp)
            let av = if unitArg then "zeroinitializer" else "%x"
            let res = em.Instr(sprintf "call %s %s(ptr %%user, %s %s)" (llty r) code (llty a) av)
            let rt, _ = cRet r
            em.Emit(if rt = "void" then "ret void" else sprintf "ret %s %s" (llty r) res)
            let ps = "ptr %user" + (if unitArg then "" else sprintf ", %s %%x" (cParam a))
            helpers.Append(sprintf "define private %s %s(%s) {\n%s}\n\n" rt name ps em.Body) |> ignore

        name

    // ------------------------------------------------------------ functions

    let proto (f: MFun) = f.pars |> List.map (snd >> llty), llty f.ret

    // ---- debug info metadata (!N = ...), emitted after the functions
    let md = StringBuilder()
    let mutable mdCount = 0

    let meta (s: string) =
        mdCount <- mdCount + 1
        let id = sprintf "!%d" mdCount
        md.AppendLine(sprintf "%s = %s" id s) |> ignore
        id

    let diFiles = Dictionary<string, string>()

    /// !range for array and string lengths: no array can be as long as the address space, so a
    /// length is below 2^31 on a 32-bit chip and 2^47 on a 64-bit machine. Knowing that lets LLVM
    /// drop overflow checks and bounds checks that can't fail (an index from a loop up to the length).
    let lenRange =
        lazy (meta (if target.StartsWith "thumb" then "!{i_W 0, i_W 2147483648}" else "!{i_W 0, i_W 140737488355328}"))

    let loadLen (em: Emitter) (p: string) = em.Instr(sprintf "load i_W, ptr %s, !range %s" p lenRange.Value)

    let diFile (file: string) =
        match diFiles.TryGetValue file with
        | true, id -> id
        | _ ->
            let full = Path.GetFullPath file

            let id = meta (sprintf "!DIFile(filename: \"%s\", directory: \"%s\")" (Path.GetFileName full) (Path.GetDirectoryName full))
            diFiles[file] <- id
            id

    let compileUnit =
        lazy
            (let file = funs |> List.tryFind (fun f -> f.name = "main") |> Option.map (fun f -> f.file) |> Option.defaultValue "main.zs"
             meta (sprintf "distinct !DICompileUnit(language: DW_LANG_C11, file: %s, producer: \"zs\", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug)" (diFile file)))

    let noTypes = lazy (meta "!DISubroutineType(types: !{})")
    let locs = Dictionary<int * string, string>()

    let diLoc (line: int) (scope: string) =
        match locs.TryGetValue((line, scope)) with
        | true, id -> id
        | _ ->
            let id = meta (sprintf "!DILocation(line: %d, column: 1, scope: %s)" line scope)
            locs[(line, scope)] <- id
            id

    let diTypes = Dictionary<string, string>()

    /// The field types of a value that is an LLVM struct: a tuple's or a record's, or a plain
    /// union's tag and then every case's fields.
    let structFields (t: Ty) : Ty list =
        match prune t with
        | TTuple ts -> ts
        | TCon(n, args) ->
            match types[n].def with
            | RecordDef fs -> fs |> List.map (snd >> substGen args)
            | UnionDef cs -> tcon (if tagTy cs = "i8" then "u8" else "i32") :: (cs |> List.collect snd |> List.map (substGen args))
        | _ -> []

    /// Size and alignment in bytes, as LLVM (and C) lays the value out.
    let rec sizeAlign (t: Ty) : int * int =
        match llty t with
        | "i1"
        | "i8" -> 1, 1
        | "i16" -> 2, 2
        | "i32"
        | "float" -> 4, 4
        | "i64"
        | "double" -> 8, 8
        | "ptr" -> pointerBytes (), pointerBytes ()
        | "{}" -> 0, 1
        | _ ->
            let size, align, _ = layout (structFields t)
            size, align

    /// A struct's size and alignment, and each field's offset.
    and layout (ts: Ty list) : int * int * int list =
        let mutable off = 0
        let mutable align = 1

        let offsets =
            [ for t in ts do
                  let s, a = sizeAlign t
                  off <- (off + a - 1) / a * a
                  yield off
                  off <- off + s
                  align <- max align a ]

        (off + align - 1) / align * align, align, offsets

    /// The DWARF type of a variable, for the types gdb can show as values: numbers, bool, char,
    /// strings (as their text), and tuples, records and plain unions of those. With field, the
    /// type of a struct's field: a string there is a pointer to its object (print *p for it).
    let rec diType' (field: bool) (t: Ty) : string option =
        let named (key: string) (make: unit -> string) =
            match diTypes.TryGetValue key with
            | true, id -> Some id
            | _ ->
                let id = make ()
                diTypes[key] <- id
                Some id

        let basic name bits enc =
            named name (fun () -> meta (sprintf "!DIBasicType(name: \"%s\", size: %d, encoding: %s)" name bits enc))

        let pointer (key: string) (target: string) =
            named key (fun () -> meta (sprintf "!DIDerivedType(tag: DW_TAG_pointer_type, baseType: %s, size: %d)" target (8 * pointerBytes ())))

        /// A struct: its members, named, at their offsets (members gdb can't show are left out).
        let structOf (name: string) (fields: (string * Ty) list) =
            named ("struct " + showFull t) (fun () ->
                let size, _, offsets = layout (List.map snd fields)

                let members =
                    List.zip fields offsets
                    |> List.choose (fun ((f, ft), off) ->
                        diType' true ft
                        |> Option.map (fun dt ->
                            let bits, _ = sizeAlign ft
                            meta (sprintf "!DIDerivedType(tag: DW_TAG_member, name: \"%s\", baseType: %s, size: %d, offset: %d)" f dt (8 * bits) (8 * off))))

                meta (sprintf "!DICompositeType(tag: DW_TAG_structure_type, name: \"%s\", size: %d, elements: !{%s})" name (8 * size) (String.concat ", " members)))

        match prune t with
        | TCon("int", []) -> basic "int" (8 * pointerBytes ()) "DW_ATE_signed"
        | TCon(("i8" | "i16" | "i32" | "i64") as n, []) -> basic n (int (n.Substring 1)) "DW_ATE_signed"
        | TCon(("u8" | "u16" | "u32" | "u64") as n, []) -> basic n (int (n.Substring 1)) "DW_ATE_unsigned"
        | TCon("usize", []) -> basic "usize" (8 * pointerBytes ()) "DW_ATE_unsigned"
        | TCon("f64", []) -> basic "f64" 64 "DW_ATE_float"
        | TCon("f32", []) -> basic "f32" 32 "DW_ATE_float"
        | TCon("bool", []) -> basic "bool" 8 "DW_ATE_boolean"
        | TCon("char", []) -> basic "char" 32 "DW_ATE_UTF"
        | TCon("string", []) when field ->
            // the object: { count, length, bytes }
            let bytes = basic "u8" 8 "DW_ATE_unsigned_char" |> Option.get
            let word = basic "int" (8 * pointerBytes ()) "DW_ATE_signed" |> Option.get

            named "string object" (fun () ->
                let w = 8 * pointerBytes ()
                let arr = meta (sprintf "!DICompositeType(tag: DW_TAG_array_type, baseType: %s, elements: !{!DISubrange(count: -1)})" bytes)
                let m name ty off = meta (sprintf "!DIDerivedType(tag: DW_TAG_member, name: \"%s\", baseType: %s, size: %d, offset: %d)" name ty w off)
                meta (sprintf "!DICompositeType(tag: DW_TAG_structure_type, name: \"string\", size: %d, elements: !{%s, %s, %s})" (2 * w) (m "count" word 0) (m "length" word w) (m "bytes" arr (2 * w)))) |> Option.bind (pointer "string*")
        | TCon("string", []) ->
            // a variable: a pointer to its bytes (the declaration adds the offset), so gdb prints the text
            basic "char" 8 "DW_ATE_signed_char" |> Option.bind (pointer "char*")
        | TTuple ts -> structOf (show t) (ts |> List.mapi (fun i ft -> sprintf "Item%d" (i + 1), ft))
        | TCon(n, args) when (match types.TryGetValue n with
                              | true, { def = RecordDef _ } -> true
                              | _ -> false) ->
            match types[n].def with
            | RecordDef fs -> structOf (show t) (fs |> List.map (fun (f, ft) -> f, substGen args ft))
            | UnionDef _ -> None
        | TCon(n, args) when (match types.TryGetValue n with
                              | true, { def = UnionDef _ } -> plainUnion types t
                              | _ -> false) ->
            // the tag as an enumeration of the cases; then each case's fields, named after it
            let _, cases = union t
            let tagBits = if tagTy cases = "i8" then 8 else 32

            let enum =
                named ("enum " + showFull t) (fun () ->
                    let items = cases |> List.mapi (fun i (c, _) -> sprintf "!DIEnumerator(name: \"%s\", value: %d)" (shortName c) i)
                    meta (sprintf "!DICompositeType(tag: DW_TAG_enumeration_type, name: \"%s\", size: %d, elements: !{%s})" (show t) tagBits (String.concat ", " items)))

            if cases |> List.forall (fun (_, fs) -> fs.IsEmpty) then
                enum // an enum: its value is the tag
            else
                let fields =
                    cases
                    |> List.collect (fun (c, fs) ->
                        let c = shortName c
                        fs |> List.mapi (fun j ft -> (if fs.Length = 1 then c else sprintf "%s.%d" c j), ft))

                named ("struct " + showFull t) (fun () ->
                    let size, _, offsets = layout (structFields t)
                    let tagMember = meta (sprintf "!DIDerivedType(tag: DW_TAG_member, name: \"case\", baseType: %s, size: %d, offset: 0)" enum.Value tagBits)

                    let members =
                        List.zip fields (List.tail offsets)
                        |> List.choose (fun ((f, ft), off) ->
                            diType' true ft
                            |> Option.map (fun dt ->
                                let bits, _ = sizeAlign ft
                                meta (sprintf "!DIDerivedType(tag: DW_TAG_member, name: \"%s\", baseType: %s, size: %d, offset: %d)" f dt (8 * bits) (8 * off))))

                    meta (sprintf "!DICompositeType(tag: DW_TAG_structure_type, name: \"%s\", size: %d, elements: !{%s})" (show t) (8 * size) (String.concat ", " (tagMember :: members))))
        | _ -> None

    let diType = diType' false

    /// The name a variable has in the source (unique names are x.12; temporaries start with $).
    let sourceName (x: string) =
        if x.StartsWith "$" then None
        else
            match x.LastIndexOf '.' with
            | i when i > 0 && Seq.forall Char.IsDigit (x.Substring(i + 1)) -> Some(x.Substring(0, i))
            | _ -> Some x

    // ---- top-level values computed at startup: a global each. Declarations are in order, so
    // nothing can read a value before its initializer has run (as in F#)
    let valueSym (v: string) = sprintf "@\"zsv.%s\"" v
    let valueTypes = values |> List.map (fun (v, init) -> v, fnTable[init].ret) |> dict

    for v, _ in values do
        let linkage = if part.IsSome then "linkonce_odr hidden" else "internal"
        top.AppendLine(sprintf "%s = %s global %s zeroinitializer" (valueSym v) linkage (llty valueTypes[v])) |> ignore

    /// f's definition, named name, compiled for the CPU features (LLVM's target-features: avx2,fma
    /// becomes +avx2,+fma; "" for the baseline).
    let genFunAs (f: MFun) (name: string) (features: string) =
        let em = Emitter()
        let featureList = if features = "" then [] else features.Split ',' |> Array.map (fun f -> f.Trim()) |> List.ofArray

        // this function's debug scope, and the line being generated
        let sp =
            if debugInfo then
                let file = diFile f.file

                meta (
                    sprintf
                        "distinct !DISubprogram(name: \"%s\", scope: %s, file: %s, line: %d, type: %s, scopeLine: %d, spFlags: DISPFlagDefinition, unit: %s)"
                        f.name
                        file
                        file
                        f.line
                        noTypes.Value
                        f.line
                        compileUnit.Value
                )
            else
                ""

        let mutable line = f.line
        let mutable lastLine = f.line // the latest statement line seen (the return's location)

        if debugInfo then
            em.Dbg <- diLoc (max 1 f.line) sp

        /// In a debug build, a variable gdb can show: v kept in a stack slot described by
        /// #dbg_declare (or, with slot given, the existing slot).
        let declareVar (x: string) (t: Ty) (v: string) (slot: string option) (arg: int) =
            if debugInfo then
                match sourceName x, diType t with
                | Some name, Some dt ->
                    let loc = em.Dbg

                    let p =
                        match slot with
                        | Some p -> p
                        | None ->
                            let p = "%dbg." + em.Fresh(name.Replace('.', '_'))
                            em.Alloca(sprintf "%s = alloca %s" p (llty t))
                            // a parameter's store has no line, as in C: it is prologue, so a
                            // breakpoint on the function stops after it
                            if arg > 0 then em.Dbg <- ""
                            em.Emit(sprintf "store %s %s, ptr %s" (llty t) v p)
                            em.Dbg <- loc
                            p

                    let argPart = if arg > 0 then sprintf ", arg: %d" arg else ""
                    let var = meta (sprintf "!DILocalVariable(name: \"%s\"%s, scope: %s, file: %s, line: %d, type: %s)" name argPart sp (diFile f.file) (max 1 line) dt)

                    match prune t with
                    | TCon("string", []) ->
                        // its value is the address of its bytes: the object's, past the count and length
                        em.Raw(sprintf "#dbg_value(ptr %s, %s, !DIExpression(DW_OP_deref, DW_OP_plus_uconst, %d, DW_OP_stack_value), %s)" p var (2 * pointerBytes ()) loc)
                    | _ -> em.Raw(sprintf "#dbg_declare(ptr %s, %s, !DIExpression(), %s)" p var loc)
                | _ -> ()
        let selfProto = proto f
        let selfName = f.name

        /// Emits the test of pattern p against v (of type t); returns env extended with its bindings.
        /// known: p's constructor is the only one v can have, so only its fields are tested.
        let rec testIn (known: bool) (p: CPat) (t: Ty) (v: string) failL (env: Map<string, Binding>) =
            let test p t v failL env = testIn false p t v failL env

            let guardOr cond =
                let ok = em.Fresh "ok"
                em.Emit(sprintf "br i1 %s, label %%%s, label %%%s" cond ok failL)
                em.Label ok

            match p with
            | CPWild -> env
            | CPVar(x, _) -> env.Add(x, Ssa v)
            | CPAs(p, x, _) -> (test p t v failL env).Add(x, Ssa v)
            | CPInt k ->
                guardOr (em.Instr(sprintf "icmp eq %s %s, %d" (llty t) v k))
                env
            | CPStr s ->
                let c = em.Instr(sprintf "call i_W @zs_str_cmp(ptr %s, ptr %s)" v (strGlobal s))
                guardOr (em.Instr(sprintf "icmp eq i_W %s, 0" c))
                env
            | CPBool b ->
                guardOr (em.Instr(sprintf "icmp eq i1 %s, %b" v b))
                env
            | CPTuple ps ->
                let ts =
                    match prune t with
                    | TTuple ts -> ts
                    | _ -> failwith "tuple pattern on non-tuple"

                List.zip ps ts
                |> List.indexed
                |> List.fold (fun env (i, (p, et)) -> test p et (em.Instr(sprintf "extractvalue %s %s, %d" (llty t) v i)) failL env) env
            | CPRecord(_, fs) ->
                // a record is a struct of its fields in declaration order, like a tuple
                let ts =
                    match prune t with
                    | TCon(n, args) ->
                        match types[n].def with
                        | RecordDef rfs -> rfs |> List.map (fun (_, ft) -> substGen args ft)
                        | UnionDef _ -> failwith "record pattern on a union"
                    | _ -> failwith "record pattern on a non-record"

                List.zip fs ts
                |> List.indexed
                |> List.fold
                    (fun env (i, ((_, p), ft)) ->
                        match p with
                        | CPWild -> env
                        | _ -> test p ft (em.Instr(sprintf "extractvalue %s %s, %d" (llty t) v i)) failL env)
                    env
            | CPCtor(_, tag, ps) when plainUnion types t ->
                let cases = snd (union t)
                let fields = snd (List.item tag cases)

                if not known then
                    guardOr (em.Instr(sprintf "icmp eq %s %s, %d" (tagTy cases) (em.Instr(sprintf "extractvalue %s %s, 0" (llty t) v)) tag))

                List.zip ps fields
                |> List.indexed
                |> List.fold
                    (fun env (i, (p, ft)) ->
                        match p with
                        | CPWild -> env
                        | _ -> test p ft (em.Instr(sprintf "extractvalue %s %s, %d" (llty t) v (plainField t tag i))) failL env)
                    env
            | CPCtor(_, tag, ps) ->
                let cases = snd (union t)
                let fields = snd (List.item tag cases)

                match repOf t, ps with
                | Niche(noneTag, _), _ when tag = noneTag ->
                    if not known then
                        guardOr (em.Instr(sprintf "icmp eq ptr %s, @zs.none" v))

                    env
                | Niche(_, payload), [ p ] ->
                    // the value is the field
                    if not known then
                        guardOr (em.Instr(sprintf "icmp ne ptr %s, @zs.none" v))

                    test p payload v failL env
                | _ when fields.IsEmpty ->
                    if not known then
                        guardOr (em.Instr(sprintf "icmp eq ptr %s, %s" v (nullary t tag)))

                    env
                | _ ->
                    if not known then
                        if not (tagged t) then
                            // the only case with fields: the value isn't one of the static cells
                            for k, (_, fs) in List.indexed cases do
                                if fs.IsEmpty then
                                    guardOr (em.Instr(sprintf "icmp ne ptr %s, %s" v (nullary t k)))
                        else
                            let tagp = em.Instr(sprintf "getelementptr { i_W, i32 }, ptr %s, i32 0, i32 1" v)
                            let tv = em.Instr(sprintf "load i32, ptr %s, !range !{i32 0, i32 %d}" tagp cases.Length)
                            guardOr (em.Instr(sprintf "icmp eq i32 %s, %d" tv tag))

                    let cell = cellTy t tag

                    List.zip ps fields
                    |> List.indexed
                    |> List.fold
                        (fun env (i, (p, ft)) ->
                            match p with
                            | CPWild -> env
                            | _ ->
                                let fp = em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 %d" cell v (cellField t i))
                                test p ft (em.Instr(sprintf "load %s, ptr %s" (llty ft) fp)) failL env)
                        env
            | CPOr(a, b) ->
                // both sides bind the same variables; merge them with phis
                let altL, okL = em.Fresh "alt", em.Fresh "or"
                let vars = patVars a
                let envA = test a t v altL env
                let fromA = vars |> List.map (fun (x, _) -> envA[x]), em.Block
                em.Emit(sprintf "br label %%%s" okL)
                em.Label altL
                let envB = test b t v failL env
                let fromB = vars |> List.map (fun (x, _) -> envB[x]), em.Block
                em.Emit(sprintf "br label %%%s" okL)
                em.Label okL

                let ssa b =
                    match b with
                    | Ssa s -> s
                    | Slot _ -> failwith "pattern variable in a slot"

                vars
                |> List.indexed
                |> List.fold
                    (fun (env: Map<_, _>) (i, (x, xt)) ->
                        let va, vb = ssa (List.item i (fst fromA)), ssa (List.item i (fst fromB))
                        env.Add(x, Ssa(em.Instr(sprintf "phi %s [ %s, %%%s ], [ %s, %%%s ]" (llty xt) va (snd fromA) vb (snd fromB)))))
                    env

        let phi ty (incoming: (string * string) list) =
            incoming
            |> List.map (fun (v, b) -> sprintf "[ %s, %%%s ]" v b)
            |> String.concat ", "
            |> sprintf "phi %s %s" ty
            |> em.Instr

        // join points being generated: their block, and each jump's argument values and block
        let joinBlocks = Dictionary<string, string * ResizeArray<string list * string>>()

        /// let mutable arrays a loop writes, kept unique for the whole loop: inside it they are
        /// only borrowed (a.[i], Array.length a) or written, never shared or reassigned. Each is
        /// made unique once before the loop, and the writes in it skip the reference-count check.
        let uniqueSlots = HashSet<string>()

        let hoisted = HashSet<CExpr>(HashIdentity.Reference)
        let versioning = HashSet<CExpr>(HashIdentity.Reference) // for loops being generated as versions
        let uncheckedReads = HashSet<CExpr>(HashIdentity.Reference) // a.[i] proved in bounds

        /// The array reads of a for loop's body that versioning can prove in bounds: a.[i] and
        /// SIMD loads from a (F32x8.load a i, which read lanes elements), where i is x plus or minus
        /// constants and variables bound outside the loop (c - x too), with a and those variables
        /// not assigned in the loop. Returns the read nodes with (array, coefficient of x, the other
        /// terms with their signs, lanes).
        let affineReads (env: Map<string, Binding>) (x: string) (body: CExpr) =
            let assigned = HashSet<string>()

            let rec scan (e: CExpr) =
                match e.k with
                | CAssign(y, _) -> assigned.Add y |> ignore
                | _ -> ()

                children e.k |> List.iter scan

            scan body

            let invariant (c: CExpr) =
                match c.k with
                | CInt _ -> true
                | CLocal y -> y <> x && env.ContainsKey y && not (assigned.Contains y)
                | _ -> false

            // i as coef * x + the sum of the signed terms, each invariant; None if it isn't
            let rec linear (sign: int) (idx: CExpr) : (int * (int * CExpr) list) option =
                match idx.k with
                | CLocal y when y = x -> Some(sign, [])
                | _ when invariant idx -> Some(0, [ sign, idx ])
                | CBin(("+" | "-") as op, a, b) ->
                    match linear sign a, linear (if op = "+" then sign else -sign) b with
                    | Some(ca, ta), Some(cb, tb) -> Some(ca + cb, ta @ tb)
                    | _ -> None
                | CLine(_, e) -> linear sign e
                | _ -> None

            let affine (idx: CExpr) =
                match linear 1 idx with
                | Some((1 | -1) as coef, terms) -> Some(coef, terms)
                | _ -> None

            // an array the loop doesn't assign: a variable, or a field of one
            let rec stable (a: CExpr) =
                match a.k with
                | CLocal arr -> arr <> x && env.ContainsKey arr && not (assigned.Contains arr)
                | CField(r, _) -> stable r
                | _ -> false

            let found = ResizeArray<CExpr * (CExpr * int * (int * CExpr) list * int)>()

            let rec walk (e: CExpr) =
                match e.k with
                | CPrim(("array.get#b" | "vec.load#b") as op, [ a; idx ]) when stable a ->
                    let lanes = if op = "vec.load#b" then snd vectorInfo[tyName e.ty] else 1

                    match affine idx with
                    | Some(coef, terms) -> found.Add(e, (a, coef, terms, lanes))
                    | None -> ()

                    walk idx
                | CLam _ -> () // a closure body doesn't run in the loop
                | _ -> children e.k |> List.iter walk

            walk body
            List.ofSeq found

        /// Only innermost loops without calls are versioned: that's where bounds checks cost, and duplicating
        /// an outer loop's body (with its inner loops) costs more code than it saves time.
        let rec hasLoop (e: CExpr) =
            match e.k with
            | CWhile _
            | CFor _
            | CCallDirect _
            | CApplyClo _ -> true // nor loops that call: the call costs more, and duplicating it blocks inlining
            | CLam _ -> false
            | k -> children k |> List.exists hasLoop

        let rec nodes (e: CExpr) = 1 + (children e.k |> List.sumBy nodes)

        let debugVersioning (x: string) (step: CExpr) (body: CExpr) (env: Map<string, Binding>) =
            if not (isNull (System.Environment.GetEnvironmentVariable "ZS_DBGV")) then
                eprintfn "CFor %s step=%A hasLoop=%b affine=%d" x step.k (hasLoop body) (affineReads env x body).Length

            false

        // a for loop's step that's a constant above 0 (as written: for x in a .. 8 .. b)
        let rec positiveStep (s: CExpr) =
            match s.k with
            | CInt n -> n >= 1L
            | CLine(_, s) -> positiveStep s
            | _ -> false

        // at -Os only small bodies: duplicating them costs a few dozen bytes
        let versionedReads env x body =
            if hasLoop body || (optimizeSize && nodes body > 40) then [] else affineReads env x body |> List.map snd
        let versionedNodes env x body = affineReads env x body |> List.map fst

        let loopUniques (env: Map<string, Binding>) (loop: CExpr) =
            let written = Dictionary<string, Ty>()
            let shared = HashSet<string>()

            let rec walk (e: CExpr) =
                match e.k with
                | CArraySet(x, i, v) ->
                    written[x] <- TCon("array", [ v.ty ])
                    walk i
                    walk v
                | CPrim(op, { k = CLocal _ } :: rest) when op.EndsWith "#b" -> List.iter walk rest
                | CLocal x
                | CDup(x, _, _)
                | CDrop(x, _, _)
                | CAssign(x, _) ->
                    shared.Add x |> ignore
                    children e.k |> List.iter walk
                | _ -> children e.k |> List.iter walk

            walk loop

            [ for KeyValue(x, t) in written do
                  match env.TryFind x with
                  | Some(Slot p) when not (shared.Contains x) && not (uniqueSlots.Contains x) -> yield x, p, t
                  | _ -> () ]

        /// A call of a C function (an extern, or a function pointer's value) with the values of
        /// the arguments:  strings as their bytes, closures for callback<F> parameters as callback and
        /// user data, Z# objects as handles, structs by the C ABI's rules.
        let cCall (callee: string) (s: ExternSig) (args: CExpr list) (vs: string list) =
            let ret, sret = cRet s.ret
            let modes = cModes s.pars sret
            let handles = ResizeArray<string>() // handles made for the call, released after it

            let argv =
                List.zip args vs
                |> List.mapi (fun i (a, v) ->
                    let fixedC = i < s.pars.Length

                    match tyName a.ty with
                    | "string" -> "ptr " + em.Instr(sprintf "getelementptr inbounds i8, ptr %s, i_W HDR2" v)
                    | _ when fixedC ->
                        let pt = List.item i s.pars

                        match prune pt with
                        | TCon("callback", [ f ]) -> sprintf "ptr %s, ptr %s" (thunk f) v // the closure is the user data
                        | TCon("unit", []) -> ""
                        | _ when isHandle pt ->
                            // the value's reference goes into a handle C borrows for the call
                            let h = em.Instr(sprintf "call ptr @zs_handle_new(ptr %s, ptr %s)" v (dropFn pt))
                            handles.Add h
                            "ptr " + h
                        | _ ->
                            match List.item i modes with
                            | Scalar -> sprintf "%s %s" (cParam pt) v
                            | Pieces ps -> toPieces em pt v ps |> List.map (fun (t, x) -> t + " " + x) |> String.concat ", "
                            | Memory ->
                                let slot = slotFor em pt
                                em.Emit(sprintf "store %s %s, ptr %s" (llty pt) v slot)
                                sprintf "%s %s" (byval pt) slot
                    // C default argument promotions for variadic arguments
                    | "bool" -> "i32 " + em.Instr(sprintf "zext i1 %s to i32" v)
                    | "i8"
                    | "i16" -> "i32 " + em.Instr(sprintf "sext %s %s to i32" (llty a.ty) v)
                    | "u8"
                    | "u16" -> "i32 " + em.Instr(sprintf "zext %s %s to i32" (llty a.ty) v)
                    | "f32" -> "double " + em.Instr(sprintf "fpext float %s to double" v)
                    | n when prims.Contains n && n <> "unit" -> sprintf "%s %s" (llty a.ty) v
                    | _ -> fail 0 (sprintf "a %s cannot be passed to a C variadic function" (show a.ty)))
                |> List.filter ((<>) "")

            let retSlot = if sret then Some(slotFor em s.ret) else None
            let sretP = retSlot |> Option.map (fun p -> sprintf "ptr sret(%s) %s" (llty s.ret) p) |> Option.toList
            let argv = sretP @ argv |> String.concat ", "

            let fnTy =
                if s.variadic then
                    let sretT = if sret then [ sprintf "ptr sret(%s)" (llty s.ret) ] else []
                    sprintf "%s (%s)" ret (sretT @ cParamList s.pars sret @ [ "..." ] |> String.concat ", ")
                else
                    ret

            let call = sprintf "call %s %s(%s)" fnTy callee argv

            let r =
                if ret = "void" then
                    em.Emit call

                    match retSlot with
                    | Some p -> em.Instr(sprintf "load %s, ptr %s" (llty s.ret) p)
                    | None -> "zeroinitializer"
                else
                    let c = em.Instr call

                    match abiFor s.ret true with
                    | _ when isHandle s.ret ->
                        // C gave a handle: the object, with a reference of its own; the handle goes
                        let o = em.Instr(sprintf "call ptr @zs_handle_get(ptr %s)" c)
                        em.Emit(sprintf "call void @zs_release(ptr %s)" c)
                        o
                    | Scalar -> c
                    | Pieces [ p ] -> fromPieces em s.ret [ p, c ]
                    | Pieces ps -> fromPieces em s.ret (ps |> List.mapi (fun k p -> p, em.Instr(sprintf "extractvalue %s %s, %d" ret c k)))
                    | Memory -> failwith "unreachable"

            for h in handles do
                em.Emit(sprintf "call void @zs_release(ptr %s)" h)

            List.zip args vs
            |> List.iteri (fun i (a, v) ->
                let callback =
                    i < s.pars.Length
                    && (match prune (List.item i s.pars) with
                        | TCon("callback", _) -> true
                        | _ -> false)

                // the string's bytes / the callback's closure were borrowed
                if tyName a.ty = "string" || callback then
                    dropValue em a.ty v)

            r

        let lookup (env: Map<string, Binding>) x t =
            match (match env.TryFind x with
                   | Some b -> b
                   | None -> failwithf "Codegen: %s isn't bound in %s" x f.name) with
            | Ssa v -> v
            | Slot p -> em.Instr(sprintf "load %s, ptr %s" (llty t) p)

        let rec gen (env: Map<string, Binding>) (tail: bool) (e: CExpr) : string =
            match e.k with
            | CLine(ln, e) ->
                let saved, savedLine = em.Dbg, line

                if debugInfo && ln > 0 then
                    line <- ln
                    lastLine <- max lastLine ln
                    em.Dbg <- diLoc ln sp

                try
                    try
                        gen env tail e
                    with CompileError(0, msg) ->
                        fail ln msg
                finally
                    em.Dbg <- saved
                    line <- savedLine
            | CInt k -> if isFloat e.ty then floatConst (llty e.ty) (float k) else string k
            | CFloat x -> floatConst (llty e.ty) x
            | CBool b -> if b then "true" else "false"
            | CUnit -> "zeroinitializer"
            | CStr s -> if tyName e.ty = "cstr" then cstrConst s else strGlobal s
            | CLocal x -> lookup env x e.ty
            | CGlobalVal v -> em.Instr(sprintf "load %s, ptr %s" (llty e.ty) (valueSym v))
            | CLet(x, v, body) ->
                let vv = gen env false v
                declareVar x v.ty vv None 0
                gen (env.Add(x, Ssa vv)) tail body
            | CLetMut(x, v, body) ->
                let vv = gen env false v
                let slot = "%slot." + x + "." + em.Fresh "" // unique: a loop body may be generated twice
                em.Alloca(sprintf "%s = alloca %s" slot (llty v.ty))
                em.Emit(sprintf "store %s %s, ptr %s" (llty v.ty) vv slot)
                declareVar x v.ty vv (Some slot) 0
                let needsDrop = heap v.ty
                let r = gen (env.Add(x, Slot slot)) (tail && not needsDrop) body

                if needsDrop then
                    dropValue em v.ty (em.Instr(sprintf "load %s, ptr %s" (llty v.ty) slot))

                r
            | CAssign(x, { k = CPrim("slot.moved", [ v ]) }) ->
                // the old value was moved into the call that computed the new one
                let vv = gen env false v

                match env[x] with
                | Slot p ->
                    em.Emit(sprintf "store %s %s, ptr %s" (llty v.ty) vv p)
                    "zeroinitializer"
                | Ssa _ -> failwith "assignment to an immutable variable"
            | CAssign(x, v) ->
                let vv = gen env false v

                match env[x] with
                | Slot p ->
                    let old = if heap v.ty then Some(em.Instr(sprintf "load %s, ptr %s" (llty v.ty) p)) else None
                    em.Emit(sprintf "store %s %s, ptr %s" (llty v.ty) vv p)
                    old |> Option.iter (dropValue em v.ty)
                    "zeroinitializer"
                | Ssa _ -> failwith "assignment to an immutable variable"
            | CArraySet(x, i, v) ->
                let vi = gen env false i
                let vv = gen env false v
                let at = (refs e |> List.head |> snd)
                let el =
                    match prune at with
                    | TCon("array", [ el ]) -> el
                    | _ -> failwith "array set"

                match env[x] with
                | Slot p when uniqueSlots.Contains x ->
                    // made unique before the enclosing loop, and not shared inside it
                    let u = em.Instr(sprintf "load ptr, ptr %s" p)
                    let len = loadLen em (em.Instr(sprintf "getelementptr { i_W, i_W }, ptr %s, i32 0, i32 1" u))
                    check em (em.Instr(sprintf "icmp ult i_W %s, %s" vi len)) "index out of bounds"
                    let ep = em.Instr(sprintf "getelementptr inbounds nuw { i_W, i_W, [0 x %s] }, ptr %s, i32 0, i32 2, i_W %s" (llty el) u vi)
                    let old = em.Instr(sprintf "load %s, ptr %s" (llty el) ep)
                    em.Emit(sprintf "store %s %s, ptr %s" (llty el) vv ep)
                    dropValue em el old
                    "zeroinitializer"
                | Slot p ->
                    let a = em.Instr(sprintf "load ptr, ptr %s" p)
                    let u = em.Instr(sprintf "call ptr %s(ptr %s)" (uniqueFn at false) a)
                    em.Emit(sprintf "store ptr %s, ptr %s" u p)
                    let len = loadLen em (em.Instr(sprintf "getelementptr { i_W, i_W }, ptr %s, i32 0, i32 1" u))
                    check em (em.Instr(sprintf "icmp ult i_W %s, %s" vi len)) "index out of bounds"
                    let ep = em.Instr(sprintf "getelementptr inbounds nuw { i_W, i_W, [0 x %s] }, ptr %s, i32 0, i32 2, i_W %s" (llty el) u vi)
                    let old = em.Instr(sprintf "load %s, ptr %s" (llty el) ep)
                    em.Emit(sprintf "store %s %s, ptr %s" (llty el) vv ep)
                    dropValue em el old
                    "zeroinitializer"
                | Ssa _ -> failwith "array assignment to an immutable variable"
            | CSeq(a, b) ->
                gen env false a |> ignore
                gen env tail b
            | CDup(x, t, rest) ->
                dupValue em t (lookup env x t)
                gen env tail rest
            | CDrop(x, t, rest) ->
                dropValue em t (lookup env x t)
                gen env tail rest
            | CDropFields(x, xt, tag, keep, tok, rest) when (match repOf xt with
                                                              | Niche _ -> true
                                                              | _ -> false) ->
                // the value is the field: it keeps the reference, or is dropped
                let v = lookup env x xt

                if not (keep.Contains 0) then
                    match repOf xt with
                    | Niche(_, payload) -> dropValue em payload v
                    | _ -> ()

                let env =
                    match tok with
                    | Some t -> env.Add(t, Ssa "null")
                    | None -> env

                gen env tail rest
            | CDropFields(x, xt, tag, keep, tok, rest) ->
                let v = lookup env x xt
                let fields = snd (List.item tag (snd (union xt)))
                let cell = cellTy xt tag

                let load i ft =
                    let fp = em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 %d" cell v (cellField xt i))
                    em.Instr(sprintf "load %s, ptr %s" (llty ft) fp)

                let uniq, shared, join = em.Fresh "unique", em.Fresh "shared", em.Fresh "dropped"

                // with threads, a cell that isn't unique may be another thread's too: its kept
                // fields are dup'd before its reference goes (after, that thread may free it)
                let unique =
                    if threaded then
                        em.Instr(sprintf "icmp eq i_W %s, 1" (em.Instr(sprintf "load atomic i_W, ptr %s monotonic, align HDR1" v)))
                    else
                        em.Instr(sprintf "call i1 @zs.release(ptr %s)" v)

                em.Emit(sprintf "br i1 %s, label %%%s, label %%%s" unique uniq shared)
                em.Label uniq

                // the cell is reused: the object it held has died (its weak references see that)
                if checkedHeap && tok.IsSome then
                    em.Emit(sprintf "call void @zs_reused(ptr %s)" v)

                fields
                |> List.iteri (fun i ft ->
                    if heap ft && not (keep.Contains i) then
                        dropValue em ft (load i ft))

                if tok.IsNone then
                    em.Emit(sprintf "call void @zs_free(ptr %s)" v)

                let fromUniq = em.Block
                em.Emit(sprintf "br label %%%s" join)
                em.Label shared

                fields
                |> List.iteri (fun i ft ->
                    if heap ft && keep.Contains i then
                        dupValue em ft (load i ft))

                if threaded then
                    dropValue em xt v

                let fromShared = em.Block
                em.Emit(sprintf "br label %%%s" join)
                em.Label join

                let env =
                    match tok with
                    | Some t -> env.Add(t, Ssa(em.Instr(sprintf "phi ptr [ %s, %%%s ], [ null, %%%s ]" v fromUniq fromShared)))
                    | None -> env

                gen env tail rest
            | CFreeToken(tok, rest) ->
                let t = lookup env tok tUnit
                let yes, no = em.Fresh "freetok", em.Fresh "notok"
                em.Emit(sprintf "br i1 %s, label %%%s, label %%%s" (em.Instr(sprintf "icmp ne ptr %s, null" t)) yes no)
                em.Label yes
                em.Emit(sprintf "call void @zs_free(ptr %s)" t)
                em.Emit(sprintf "br label %%%s" no)
                em.Label no
                gen env tail rest
            | CCtorAt(tok, _, tag, args) ->
                let vs = args |> List.map (gen env false)
                let cell = cellTy e.ty tag
                let t = lookup env tok tUnit
                let fresh, reuse, join = em.Fresh "alloc", em.Fresh "reuse", em.Fresh "built"
                em.Emit(sprintf "br i1 %s, label %%%s, label %%%s" (em.Instr(sprintf "icmp eq ptr %s, null" t)) fresh reuse)
                em.Label fresh
                let a = em.Instr(sprintf "call ptr @zs_alloc(i_W %s)" (sizeOf em cell))
                let fromAlloc = em.Block
                em.Emit(sprintf "br label %%%s" join)
                em.Label reuse
                em.Emit(sprintf "br label %%%s" join)
                em.Label join
                let c = em.Instr(sprintf "phi ptr [ %s, %%%s ], [ %s, %%%s ]" a fromAlloc t reuse)
                em.Emit(sprintf "store i_W 1, ptr %s" c)

                if tagged e.ty then
                    let tp = em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 1" cell c)
                    em.Emit(sprintf "store i32 %d, ptr %s" tag tp)

                List.zip args vs
                |> List.iteri (fun i (a, v) ->
                    let fp = em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 %d" cell c (cellField e.ty i))
                    em.Emit(sprintf "store %s %s, ptr %s" (llty a.ty) v fp))

                c
            | CJoin(j, ps, body, rest) ->
                // a block that rest's jumps branch to, its parameters as phis
                let label, joined = em.Fresh "join", em.Fresh "joined"
                let incoming = ResizeArray<string list * string>()
                joinBlocks[j] <- (label, incoming)
                let vr = gen env tail rest
                let fromRest = em.Block
                em.Emit(sprintf "br label %%%s" joined)

                if incoming.Count = 0 then
                    em.Label joined
                    vr
                else
                    em.Label label

                    let env' =
                        ps
                        |> List.indexed
                        |> List.fold (fun (m: Map<string, Binding>) (i, (x, t)) -> m.Add(x, Ssa(phi (llty t) [ for args, b in incoming -> List.item i args, b ]))) env

                    let vb = gen env' tail body
                    let fromBody = em.Block
                    em.Emit(sprintf "br label %%%s" joined)
                    em.Label joined
                    phi (llty e.ty) [ vr, fromRest; vb, fromBody ]
            | CJump(j, args) ->
                let vs = args |> List.map (gen env false)
                let label, incoming = joinBlocks[j]
                incoming.Add(vs, em.Block)
                em.Emit(sprintf "br label %%%s" label)
                em.Dead()
                "poison"
            | CIf(c, t, f) ->
                let vc = gen env false c
                let lt, lf, lend = em.Fresh "then", em.Fresh "else", em.Fresh "endif"
                em.Emit(sprintf "br i1 %s, label %%%s, label %%%s" vc lt lf)
                em.Label lt
                let vt = gen env tail t
                let bt = em.Block
                em.Emit(sprintf "br label %%%s" lend)
                em.Label lf
                let vf = gen env tail f
                let bf = em.Block
                em.Emit(sprintf "br label %%%s" lend)
                em.Label lend
                phi (llty e.ty) [ vt, bt; vf, bf ]
            | CMatch(s, cases) ->
                // clauses are tested one after another: Decide has already turned the matches whose
                // patterns nest into decision trees, except where the tree would grow too large
                let v = gen env false s
                let endL = em.Fresh "mend"
                let mutable next = em.Fresh "case"
                let results = ResizeArray()
                em.Emit(sprintf "br label %%%s" next)

                // the cases of a union no earlier clause has taken whole: a clause for the last of
                // them needs no test of the case
                let caseCount = repOf' s.ty |> Option.map (fun _ -> (snd (union s.ty)).Length)
                let mutable taken = Set.empty

                let rec irrefutable (p: CPat) =
                    match p with
                    | CPWild
                    | CPVar _ -> true
                    | CPAs(q, _, _) -> irrefutable q
                    | CPTuple ps -> List.forall irrefutable ps
                    | CPRecord(_, fs) -> fs |> List.forall (snd >> irrefutable)
                    | _ -> false

                for p, guard, body in cases do
                    em.Label next
                    let failL = em.Fresh "case"

                    let known =
                        match p, caseCount with
                        | CPCtor(_, tag, _), Some n -> not (taken.Contains tag) && taken.Count = n - 1
                        | _ -> false

                    let env = testIn known p s.ty v failL env

                    match p with
                    | CPCtor(_, tag, ps) when guard.IsNone && List.forall irrefutable ps -> taken <- taken.Add tag
                    | _ -> ()

                    if guard.IsSome then
                        let ok = em.Fresh "guard"
                        em.Emit(sprintf "br i1 %s, label %%%s, label %%%s" (gen env false guard.Value) ok failL)
                        em.Label ok

                    results.Add(gen env tail body, em.Block)
                    em.Emit(sprintf "br label %%%s" endL)
                    next <- failL

                em.Label next
                panicWith em "match failure" // unreachable: the type checker proved exhaustiveness
                em.Label endL
                phi (llty e.ty) (List.ofSeq results)
            | CTuple xs ->
                let ty = llty e.ty
                let vs = xs |> List.map (gen env false)

                List.zip xs vs
                |> List.indexed
                |> List.fold (fun agg (i, (x, v)) -> em.Instr(sprintf "insertvalue %s %s, %s %s, %d" ty agg (llty x.ty) v i)) "poison"
            | CField(r, i) -> em.Instr(sprintf "extractvalue %s %s, %d" (llty r.ty) (gen env false r) i)
            | CCtor(_, tag, args) when plainUnion types e.ty ->
                // a value: the tag and this case's fields, the other cases' fields zero
                let vs = args |> List.map (gen env false)
                let lt = llty e.ty
                let withTag = em.Instr(sprintf "insertvalue %s zeroinitializer, %s %d, 0" lt (tagTy (snd (union e.ty))) tag)

                List.zip args vs
                |> List.indexed
                |> List.fold (fun agg (i, (a, v)) -> em.Instr(sprintf "insertvalue %s %s, %s %s, %d" lt agg (llty a.ty) v (plainField e.ty tag i))) withTag
            | CCtor(_, tag, args) when (match repOf e.ty with
                                         | Niche _ -> true
                                         | _ -> false) ->
                // a niche: the field itself, or @zs.none
                match args with
                | [ a ] -> gen env false a
                | _ -> "@zs.none"
            | CCtor(_, tag, []) -> nullary e.ty tag
            | CCtor(_, tag, args) ->
                let vs = args |> List.map (gen env false)
                let cell = cellTy e.ty tag
                let c = em.Instr(sprintf "call ptr @zs_alloc(i_W %s)" (sizeOf em cell))
                em.Emit(sprintf "store i_W 1, ptr %s" c)

                if tagged e.ty then
                    let tp = em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 1" cell c)
                    em.Emit(sprintf "store i32 %d, ptr %s" tag tp)

                List.zip args vs
                |> List.iteri (fun i (a, v) ->
                    let fp = em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 %d" cell c (cellField e.ty i))
                    em.Emit(sprintf "store %s %s, ptr %s" (llty a.ty) v fp))

                c
            | CBin(op, a, b) ->
                let va = gen env false a
                let vb = gen env false b
                let t = a.ty
                let lt = llty t
                // a [<FastMath>] function's float + - * /: LLVM's fast ones
                let fast = op.StartsWith "fast"
                let op = if fast then op.Substring 4 else op
                // a [<Wrapping>] function's + - *: wrapping on integers, the usual ones otherwise
                let op = if op.StartsWith "wrap" && not (ints.Contains(tyName t)) then op.Substring 4 else op

                match tyName t with
                | n when isVectorName n || isMaskName n -> simdBin em op t va vb fast
                | "string" ->
                    let r =
                        if op = "+" then
                            em.Instr(sprintf "call ptr @zs_str_concat(ptr %s, ptr %s)" va vb)
                        else
                            let c = em.Instr(sprintf "call i_W @zs_str_cmp(ptr %s, ptr %s)" va vb)
                            em.Instr(sprintf "icmp %s i_W %s, 0" (icmpS[op]) c)

                    dropValue em t va
                    dropValue em t vb
                    r
                | "unit" -> if op = "=" then "true" else "false"
                | _ when isFloat t ->
                    if farith.ContainsKey op then
                        em.Instr(sprintf "%s%s %s %s, %s" (farith[op]) (if fast then " fast" else "") lt va vb)
                    else
                        em.Instr(sprintf "fcmp %s %s %s, %s" (fcmp[op]) lt va vb)
                | _ when op = "&&&" -> em.Instr(sprintf "and %s %s, %s" lt va vb)
                | _ when op = "|||" -> em.Instr(sprintf "or %s %s, %s" lt va vb)
                | _ when op = "^^^" -> em.Instr(sprintf "xor %s %s, %s" lt va vb)
                | _ when op = "<<<" || op = ">>>" ->
                    // the shift amount is taken modulo the width, as in F# (LLVM leaves larger ones undefined)
                    let bits = int (lt.Substring 1)
                    let amount = em.Instr(sprintf "and %s %s, %d" lt vb (bits - 1))
                    let instr = if op = "<<<" then "shl" elif isUnsigned t then "lshr" else "ashr"
                    em.Instr(sprintf "%s %s %s, %s" instr lt va amount)
                | _ when op.StartsWith "wrap" -> em.Instr(sprintf "%s %s %s, %s" arith[op.Substring 4] lt va vb)
                | _ when arith.ContainsKey op -> checkedArith em op (isUnsigned t) lt va vb
                | _ when op = "/" || op = "%" ->
                    check em (em.Instr(sprintf "icmp ne %s %s, 0" lt vb)) "division by zero"

                    if not (isUnsigned t) then
                        // MIN / -1 doesn't fit (and is undefined behaviour in LLVM)
                        let bits = int (lt.Substring 1)
                        let minv = if bits = 64 then string System.Int64.MinValue else string (-(1L <<< (bits - 1)))
                        let isMin = em.Instr(sprintf "icmp eq %s %s, %s" lt va minv)
                        let isNeg1 = em.Instr(sprintf "icmp eq %s %s, -1" lt vb)
                        let bad = em.Instr(sprintf "and i1 %s, %s" isMin isNeg1)
                        check em (em.Instr(sprintf "xor i1 %s, true" bad)) "integer overflow"

                    let instr = (if isUnsigned t then "u" else "s") + (if op = "/" then "div" else "rem")
                    em.Instr(sprintf "%s %s %s, %s" instr lt va vb)
                | _ ->
                    let table = if isUnsigned t then icmpU else icmpS
                    em.Instr(sprintf "icmp %s %s %s, %s" (table[op]) lt va vb)
            | CNeg a ->
                let va = gen env false a

                if isFloat a.ty || (isVectorName (tyName a.ty) && floats.Contains(fst vectorInfo[tyName a.ty])) then
                    em.Instr(sprintf "fneg %s %s" (llty a.ty) va)
                elif isVectorName (tyName a.ty) then
                    em.Instr(sprintf "sub %s zeroinitializer, %s" (llty a.ty) va) // wrapping, lane by lane
                else
                    checkedArith em "-" (isUnsigned a.ty) (llty a.ty) "0" va
            | CNot a -> em.Instr(sprintf "xor i1 %s, true" (gen env false a))
            | CCallDirect(f, args) ->
                let fd = fnTable[f]
                let vs = args |> List.map (gen env false)
                let argv = List.zip args vs |> List.map (fun (a, v) -> sprintf "%s %s" (llty a.ty) v) |> String.concat ", "
                let rt = llty fd.ret

                if tail && proto fd = selfProto then
                    // a call to itself is left to LLVM to make a loop (which can then be inlined into
                    // callers); other tail calls, and all at -O0, must be tail calls (constant stack)
                    let kind = if f = selfName && not debugInfo then "tail" else "musttail"
                    let r = em.Instr(sprintf "%s call %s %s(%s)" kind rt (sym f) argv)
                    em.Emit(sprintf "ret %s %s" rt r)
                    em.Dead()
                    "poison"
                else
                    em.Instr(sprintf "%scall %s %s(%s)" (if tail then "tail " else "") rt (sym f) argv)
            | CExtern(name, args) -> cCall ("@" + name) externs[name] args (args |> List.map (gen env false))
            | CMkClosure(f, []) -> staticClosure f
            | CMkClosure(f, args) ->
                let vs = args |> List.map (gen env false)
                allocClosure em f (List.zip (args |> List.map (fun a -> a.ty)) vs)
            | CApplyClo(c, args) ->
                let vc = gen env false c
                let vs = List.zip args (args |> List.map (gen env false))

                // one argument at a time: each call but the last gives a closure holding more
                let curried (vc: string) =
                    vs
                    |> List.indexed
                    |> List.fold
                        (fun (cur: string) (i, (a: CExpr, v)) ->
                            let cp = em.Instr(sprintf "getelementptr { i_W, ptr }, ptr %s, i32 0, i32 1" cur)
                            let code = em.Instr(sprintf "load ptr, ptr %s" cp)
                            let rt = if i = vs.Length - 1 then llty e.ty else "ptr"
                            let r = em.Instr(sprintf "call %s %s(ptr %s, %s %s)" rt code cur (llty a.ty) v)

                            if i > 0 then
                                em.Emit(sprintf "call void @zs.drop.clo(ptr %s)" cur) // a closure made on the way

                            r)
                        vc

                if vs.Length = 1 then
                    curried vc
                else
                    // all at once when the closure takes exactly that many
                    let ip = em.Instr(sprintf "getelementptr { i_W, ptr, ptr }, ptr %s, i32 0, i32 2" vc)
                    let inf = em.Instr(sprintf "load ptr, ptr %s" ip)
                    let ap = em.Instr(sprintf "getelementptr { ptr, i32, ptr }, ptr %s, i32 0, i32 1" inf)
                    let arity = em.Instr(sprintf "load i32, ptr %s" ap)
                    let fullL, oneL, doneL = em.Fresh "full", em.Fresh "curried", em.Fresh "applied"
                    em.Emit(sprintf "br i1 %s, label %%%s, label %%%s" (em.Instr(sprintf "icmp eq i32 %s, %d" arity vs.Length)) fullL oneL)
                    em.Label fullL
                    let fp = em.Instr(sprintf "getelementptr { ptr, i32, ptr }, ptr %s, i32 0, i32 2" inf)
                    let code = em.Instr(sprintf "load ptr, ptr %s" fp)
                    let argv = vs |> List.map (fun (a, v) -> sprintf "%s %s" (llty a.ty) v) |> String.concat ", "
                    let r1 = em.Instr(sprintf "call %s %s(ptr %s, %s)" (llty e.ty) code vc argv)
                    let fromFull = em.Block
                    em.Emit(sprintf "br label %%%s" doneL)
                    em.Label oneL
                    let r2 = curried vc
                    let fromOne = em.Block
                    em.Emit(sprintf "br label %%%s" doneL)
                    em.Label doneL
                    phi (llty e.ty) [ r1, fromFull; r2, fromOne ]
            | CWhile _
            | CFor _ when not (hoisted.Contains e) && not (loopUniques env e).IsEmpty ->
                let arrays = loopUniques env e

                for _, p, t in arrays do
                    let a = em.Instr(sprintf "load ptr, ptr %s" p)
                    em.Emit(sprintf "store ptr %s, ptr %s" (em.Instr(sprintf "call ptr %s(ptr %s)" (uniqueFn t false) a)) p)

                for x, _, _ in arrays do
                    uniqueSlots.Add x |> ignore

                hoisted.Add e |> ignore
                let r = gen env tail e
                hoisted.Remove e |> ignore

                for x, _, _ in arrays do
                    uniqueSlots.Remove x |> ignore

                r
            | CFor(x, a, step, b, body) when (debugVersioning x step body env) -> "dbg"
            | CFor(x, a, step, b, body) when positiveStep step && not (versioning.Contains e) && not (versionedReads env x body).IsEmpty ->
                // loop versioning: if every a.[x ± c] (and SIMD load) the loop reads is in bounds
                // for the whole range, run a copy of the loop without those bounds checks; otherwise
                // the checked one
                let reads = versionedReads env x body
                let lt = llty a.ty
                let va = gen env false a
                let vb = gen env false b
                let value (c: CExpr) = gen env false c

                let ovf (op: string) (p: string) (q: string) (bad: string) =
                    let name = sprintf "llvm.s%s.with.overflow.%s" op lt
                    let decl = sprintf "declare { %s, i1 } @%s(%s, %s)" lt name lt lt

                    if generated.Add decl then
                        helpers.Append(decl + "\n") |> ignore

                    let r = em.Instr(sprintf "call { %s, i1 } @%s(%s %s, %s %s)" lt name lt p lt q)
                    em.Instr(sprintf "extractvalue { %s, i1 } %s, 0" lt r), em.Instr(sprintf "or i1 %s, %s" bad (em.Instr(sprintf "extractvalue { %s, i1 } %s, 1" lt r)))

                let ok =
                    reads
                    |> List.fold
                        (fun ok (arr: CExpr, coef, terms, lanes) ->
                            // the index's other terms summed (any overflow fails the test)
                            let cv, bad =
                                terms
                                |> List.fold
                                    (fun (acc, bad) (sign, t) -> ovf (if sign > 0 then "add" else "sub") acc (value t) bad)
                                    ("0", "false")

                            let lo, hi, bad =
                                if coef > 0 then
                                    let lo, bad = ovf "add" va cv bad
                                    let hi, bad = ovf "add" vb cv bad
                                    lo, hi, bad
                                else
                                    let lo, bad = ovf "sub" cv vb bad
                                    let hi, bad = ovf "sub" cv va bad
                                    lo, hi, bad

                            // a SIMD load reads lanes elements from its index
                            let hi, bad = if lanes > 1 then ovf "add" hi (string (lanes - 1)) bad else hi, bad

                            let len = loadLen em (em.Instr(sprintf "getelementptr { i_W, i_W }, ptr %s, i32 0, i32 1" (value arr)))
                            let inRange = em.Instr(sprintf "and i1 %s, %s" (em.Instr(sprintf "icmp sge %s %s, 0" lt lo)) (em.Instr(sprintf "icmp slt %s %s, %s" lt hi len)))
                            em.Instr(sprintf "and i1 %s, %s" ok (em.Instr(sprintf "and i1 %s, %s" inRange (em.Instr(sprintf "xor i1 %s, true" bad))))))
                        "true"

                let fast, slow, join = em.Fresh "vfast", em.Fresh "vslow", em.Fresh "vjoin"
                em.Emit(sprintf "br i1 %s, label %%%s, label %%%s" ok fast slow)
                versioning.Add e |> ignore
                em.Label fast

                for node in versionedNodes env x body do
                    uncheckedReads.Add node |> ignore

                gen env false e |> ignore

                for node in versionedNodes env x body do
                    uncheckedReads.Remove node |> ignore

                em.Emit(sprintf "br label %%%s" join)
                em.Label slow
                gen env false e |> ignore
                em.Emit(sprintf "br label %%%s" join)
                em.Label join
                versioning.Remove e |> ignore
                "zeroinitializer"
            | CWhile(c, b) ->
                let lc, lb, lend = em.Fresh "wcond", em.Fresh "wbody", em.Fresh "wend"
                em.Emit(sprintf "br label %%%s" lc)
                em.Label lc
                em.Emit(sprintf "br i1 %s, label %%%s, label %%%s" (gen env false c) lb lend)
                em.Label lb
                gen env false b |> ignore
                em.Emit(sprintf "br label %%%s" lc)
                em.Label lend
                "zeroinitializer"
            | CFor(x, a, step, b, body) ->
                let lt = llty a.ty
                let va = gen env false a
                let vs = gen env false step
                let vb = gen env false b
                let slot = "%slot." + x + "." + em.Fresh "" // unique: a loop body may be generated twice
                em.Alloca(sprintf "%s = alloca %s" slot lt)
                em.Emit(sprintf "store %s %s, ptr %s" lt va slot)
                declareVar x a.ty va (Some slot) 0
                let lc, lb, lend = em.Fresh "fcond", em.Fresh "fbody", em.Fresh "fend"
                em.Emit(sprintf "br label %%%s" lc)
                em.Label lc
                let i = em.Instr(sprintf "load %s, ptr %s" lt slot)

                let down =
                    match step.k with
                    | CInt k -> k < 0L
                    | CNeg _ -> true
                    | _ -> false

                let cmp = if down then (if isUnsigned a.ty then "uge" else "sge") else (if isUnsigned a.ty then "ule" else "sle")
                em.Emit(sprintf "br i1 %s, label %%%s, label %%%s" (em.Instr(sprintf "icmp %s %s %s, %s" cmp lt i vb)) lb lend)
                em.Label lb
                gen (env.Add(x, Ssa i)) false body |> ignore
                em.Emit(sprintf "store %s %s, ptr %s" lt (em.Instr(sprintf "add %s %s, %s" lt i vs)) slot)
                em.Emit(sprintf "br label %%%s" lc)
                em.Label lend
                "zeroinitializer"
            | CPrim(op, args) -> prim env (if uncheckedReads.Contains e then op + "!" else op) args e.ty
            | CGlobal _
            | CApp _
            | CLam _
            | CLetFun _
            | CLetRec _ -> failwithf "Codegen: unexpected node %A" e.k

        and prim env op (args: CExpr list) (ty: Ty) : string =
            // op!: a read a versioned loop proved in bounds; op#b: the first argument is borrowed
            // (the Rc pass keeps it alive), so it isn't dropped
            let unchecked = op.EndsWith "!"
            let op = if unchecked then op.Substring(0, op.Length - 1) else op
            let borrowed0 = op.EndsWith "#b"
            let op = if borrowed0 then op.Substring(0, op.Length - 2) else op
            let vs = args |> List.map (gen env false)
            let arg i = List.item i vs
            let argTy i = (List.item i args).ty

            let arrTy (t: Ty) =
                match prune t with
                | TCon("array", [ el ]) -> el, sprintf "{ i_W, i_W, [0 x %s] }" (llty el)
                | _ -> failwith "not an array"

            let elemPtr a i =
                let el, at = arrTy (argTy 0)
                // after the bounds check the index is non-negative: nuw tells LLVM an element never
                // overlaps the header, so a reference-count check can move out of a loop
                el, em.Instr(sprintf "getelementptr inbounds nuw %s, ptr %s, i32 0, i32 2, i_W %s" at a i)

            let bounds a i =
                let lenp = em.Instr(sprintf "getelementptr { i_W, i_W }, ptr %s, i32 0, i32 1" a)
                let len = loadLen em lenp
                check em (em.Instr(sprintf "icmp ult i_W %s, %s" i len)) "index out of bounds"

            // SIMD vectors and masks (DESIGN §8): their functions, a module per type (F32x8.load)
            let simdPrim (op: string) (args: CExpr list) (vs: string list) (argTy: int -> Ty) (ty: Ty) (borrowed0: bool) (unchecked: bool) =
                let arg i = List.item i vs
                // the vector type the function is about: its result's, store's third argument's, or
                // the first argument's
                let vt =
                    if List.contains op [ "vec.splat"; "vec.load"; "vec.init"; "vec.convert"; "vec.select"; "vec.shuffle"; "vec.set" ] then ty
                    elif op = "vec.store" then argTy 2
                    else argTy 0
                let e, k, et, sfx = simdShape vt
                let lt = llty vt
                let isF = floats.Contains e
                let uns = unsigned.Contains e
                let mask = sprintf "<%d x i1>" k
                let un (name: string) = intrinsic em (sprintf "llvm.%s.%s" name sfx) lt [ lt, arg 0 ] ""
                let bin (name: string) = intrinsic em (sprintf "llvm.%s.%s" name sfx) lt [ lt, arg 0; lt, arg 1 ] ""
                let lane (i: string) = check em (em.Instr(sprintf "icmp ult i_W %s, %d" i k)) "lane out of range"

                // the k elements of array arg 0 from index i: all of them in it, or a panic
                let inArray (a: string) (i: string) =
                    let len = loadLen em (em.Instr(sprintf "getelementptr { i_W, i_W }, ptr %s, i32 0, i32 1" a))
                    let ok1 = em.Instr(sprintf "icmp ult i_W %s, %s" i len)
                    let ok2 = em.Instr(sprintf "icmp ule i_W %d, %s" k (em.Instr(sprintf "sub i_W %s, %s" len i)))
                    check em (em.Instr(sprintf "and i1 %s, %s" ok1 ok2)) "index out of bounds"
                    em.Instr(sprintf "getelementptr inbounds nuw { i_W, i_W, [0 x %s] }, ptr %s, i32 0, i32 2, i_W %s" et a i)

                let align =
                    match et with
                    | "i8" -> "1"
                    | "i16" -> "2"
                    | "i32"
                    | "float" -> "4"
                    | _ -> "8"

                match op with
                | "vec.splat" -> splat em k et (arg 0)
                | "vec.load" ->
                    // unchecked: a versioned loop proved it in bounds
                    let p =
                        if unchecked then
                            em.Instr(sprintf "getelementptr inbounds nuw { i_W, i_W, [0 x %s] }, ptr %s, i32 0, i32 2, i_W %s" et (arg 0) (arg 1))
                        else
                            inArray (arg 0) (arg 1)

                    let v = em.Instr(sprintf "load %s, ptr %s, align %s" lt p align)
                    if not borrowed0 then dropValue em (argTy 0) (arg 0)
                    v
                | "vec.store" ->
                    // the array with the lanes written from index i (in place when it was unique)
                    let u = em.Instr(sprintf "call ptr %s(ptr %s)" (uniqueFn (argTy 0) false) (arg 0))
                    let p = inArray u (arg 1)
                    em.Emit(sprintf "store %s %s, ptr %s, align %s" lt (arg 2) p align)
                    u
                | "vec.get" ->
                    lane (arg 1)
                    em.Instr(sprintf "extractelement %s %s, i_W %s" lt (arg 0) (arg 1))
                | "vec.set" ->
                    lane (arg 1)
                    em.Instr(sprintf "insertelement %s %s, %s %s, i_W %s" lt (arg 0) et (arg 2) (arg 1))
                | "vec.init" ->
                    // f 0, …, f (k - 1), in order
                    let code = em.Instr(sprintf "load ptr, ptr %s" (em.Instr(sprintf "getelementptr { i_W, ptr }, ptr %s, i32 0, i32 1" (arg 0))))

                    let v =
                        [ 0 .. k - 1 ]
                        |> List.fold
                            (fun acc i ->
                                let x = em.Instr(sprintf "call %s %s(ptr %s, i_W %d)" et code (arg 0) i)
                                em.Instr(sprintf "insertelement %s %s, %s %s, i32 %d" lt acc et x i))
                            "poison"

                    dropValue em (argTy 0) (arg 0)
                    v
                | "vec.sum" ->
                    // in no particular order (floats: a tree, as SIMD code adds them)
                    if isF then
                        intrinsic em (sprintf "llvm.vector.reduce.fadd.%s" sfx) et [ et, "-0.0"; lt, arg 0 ] "reassoc "
                    else
                        intrinsic em (sprintf "llvm.vector.reduce.add.%s" sfx) et [ lt, arg 0 ] ""
                | "vec.min" -> bin (if isF then "minnum" elif uns then "umin" else "smin")
                | "vec.max" -> bin (if isF then "maxnum" elif uns then "umax" else "smax")
                | "vec.reduceMin"
                | "vec.reduceMax" ->
                    let which = if op = "vec.reduceMin" then "min" else "max"
                    let name = if isF then "f" + which elif uns then "u" + which else "s" + which
                    intrinsic em (sprintf "llvm.vector.reduce.%s.%s" name sfx) et [ lt, arg 0 ] ""
                | "vec.abs" ->
                    if isF then un "fabs"
                    elif uns then arg 0
                    else intrinsic em (sprintf "llvm.abs.%s" sfx) lt [ lt, arg 0; "i1", "false" ] ""
                | "vec.equal"
                | "vec.notEqual"
                | "vec.lessThan"
                | "vec.lessOrEqual"
                | "vec.greaterThan"
                | "vec.greaterOrEqual" ->
                    let rel =
                        match op.Substring 4 with
                        | "equal" -> "eq"
                        | "notEqual" -> "ne"
                        | "lessThan" -> "lt"
                        | "lessOrEqual" -> "le"
                        | "greaterThan" -> "gt"
                        | _ -> "ge"

                    if isF then
                        em.Instr(sprintf "fcmp %s %s %s, %s" (if rel = "ne" then "une" else "o" + rel) lt (arg 0) (arg 1))
                    else
                        let pred = if rel = "eq" || rel = "ne" then rel elif uns then "u" + rel else "s" + rel
                        em.Instr(sprintf "icmp %s %s %s, %s" pred lt (arg 0) (arg 1))
                | "vec.select" ->
                    let vt = argTy 1
                    em.Instr(sprintf "select %s %s, %s %s, %s %s" (llty (argTy 0)) (arg 0) (llty vt) (arg 1) (llty vt) (arg 2))
                | "vec.shuffle" ->
                    // the lanes the indices pick from a's then b's: constants
                    let rec literal (c: CExpr) =
                        match c.k with
                        | CLine(_, c) -> literal c
                        | CPrim("array.lit", xs) when xs |> List.forall (fun x -> match x.k with CInt _ -> true | _ -> false) ->
                            Some(xs |> List.map (fun x -> match x.k with CInt n -> n | _ -> 0L))
                        | _ -> None

                    match literal (List.item 2 args) with
                    | Some ix when ix.Length = k && ix |> List.forall (fun i -> i >= 0L && i < int64 (2 * k)) ->
                        dropValue em (argTy 2) (arg 2)
                        let m = ix |> List.map (sprintf "i32 %d") |> String.concat ", "
                        em.Instr(sprintf "shufflevector %s %s, %s %s, <%d x i32> <%s>" lt (arg 0) lt (arg 1) k m)
                    | _ -> fail 0 (sprintf "%s.shuffle's indices must be an array literal of %d numbers from 0 to %d" (simdModule (tyName vt)) k (2 * k - 1))
                | "vec.sqrt" -> un "sqrt"
                | "vec.floor" -> un "floor"
                | "vec.ceil" -> un "ceil"
                | "vec.round" -> un "roundeven"
                | "vec.mulAdd" -> intrinsic em (sprintf "llvm.fma.%s" sfx) lt [ lt, arg 0; lt, arg 1; lt, arg 2 ] ""
                | "vec.convert" ->
                    // lane by lane, from the argument's type: floats saturate into integers
                    let e1, _, et1, sfx1 = simdShape (argTy 0)
                    let lt1 = llty (argTy 0)
                    let bits (t: string) = if t = "float" then 32 elif t = "double" then 64 else int (t.Substring 1)

                    match floats.Contains e1, isF with
                    | true, true ->
                        if bits et1 = bits et then arg 0
                        else em.Instr(sprintf "%s %s %s to %s" (if bits et1 < bits et then "fpext" else "fptrunc") lt1 (arg 0) lt)
                    | false, true -> em.Instr(sprintf "%s %s %s to %s" (if unsigned.Contains e1 then "uitofp" else "sitofp") lt1 (arg 0) lt)
                    | true, false -> intrinsic em (sprintf "llvm.%s.sat.%s.%s" (if uns then "fptoui" else "fptosi") sfx sfx1) lt [ lt1, arg 0 ] ""
                    | false, false ->
                        if bits et1 = bits et then arg 0
                        elif bits et1 > bits et then em.Instr(sprintf "trunc %s %s to %s" lt1 (arg 0) lt)
                        else em.Instr(sprintf "%s %s %s to %s" (if unsigned.Contains e1 then "zext" else "sext") lt1 (arg 0) lt)
                | "mask.any" -> anyLane em k (arg 0)
                | "mask.all" -> intrinsic em (sprintf "llvm.vector.reduce.and.v%di1" k) "i1" [ mask, arg 0 ] ""
                | "mask.count" ->
                    let bitsN = em.Instr(sprintf "bitcast %s %s to i%d" mask (arg 0) k)
                    let n = intrinsic em (sprintf "llvm.ctpop.i%d" k) (sprintf "i%d" k) [ sprintf "i%d" k, bitsN ] ""
                    let w = llty tInt
                    let wbits = int (w.Substring 1)
                    if wbits = k then n elif wbits > k then em.Instr(sprintf "zext i%d %s to %s" k n w) else em.Instr(sprintf "trunc i%d %s to %s" k n w)
                | "mask.not" ->
                    let ones = List.replicate k "i1 true" |> String.concat ", "
                    em.Instr(sprintf "xor %s %s, <%s>" mask (arg 0) ones)
                | "mask.get" ->
                    lane (arg 1)
                    em.Instr(sprintf "extractelement %s %s, i_W %s" mask (arg 0) (arg 1))
                | _ -> failwithf "Codegen: unknown SIMD function %s" op

            // how an Atomic stores its value: as it is, except a bool, which is a byte (atomic
            // operations take whole bytes)
            let atomicRep (t: Ty) =
                match llty t with
                | "i1" -> "i8", (fun v -> em.Instr(sprintf "zext i1 %s to i8" v)), (fun v -> em.Instr(sprintf "trunc i8 %s to i1" v))
                | lt -> lt, id, id

            let newArray (el: Ty) (n: string) =
                let es = sizeOf em (llty el)
                let bytes = em.Instr(sprintf "add i_W HDR2, %s" (em.Instr(sprintf "mul i_W %s, %s" n es)))
                let a = em.Instr(sprintf "call ptr @zs_alloc(i_W %s)" bytes)
                em.Emit(sprintf "store i_W 1, ptr %s" a)
                let lenp = em.Instr(sprintf "getelementptr { i_W, i_W }, ptr %s, i32 0, i32 1" a)
                em.Emit(sprintf "store i_W %s, ptr %s" n lenp)
                a

            match op with
            | "ignore" ->
                dropValue em (argTy 0) (arg 0)
                "zeroinitializer"
            | "panic" ->
                em.Emit(sprintf "call void @zs_panic(ptr %s)" (arg 0))
                em.Emit "unreachable"
                em.Dead()
                "poison"
            | "assert" ->
                check em (arg 0) "assertion failed"
                "zeroinitializer"
            | _ when op.StartsWith "assert:" ->
                check em (arg 0) ("assertion failed at " + op.Substring 7)
                "zeroinitializer"
            | "print"
            | "println" ->
                em.Emit(sprintf "call void @zs_%s(ptr %s)" op (arg 0))
                dropValue em (argTy 0) (arg 0)
                "zeroinitializer"
            | "string" ->
                let t = argTy 0
                let lt = llty t

                match tyName t with
                | n when isVectorName n || isMaskName n ->
                    // <1, 2, 3, 4>: the lanes from memory, a mask's as bytes
                    let e, k, _, _ = simdShape t
                    let lanes, v = if isMaskName n then sprintf "<%d x i8>" k, em.Instr(sprintf "zext %s %s to <%d x i8>" lt (arg 0) k) else lt, arg 0
                    let slot = "%" + em.Fresh "lanes"
                    em.Alloca(sprintf "%s = alloca %s" slot lanes)
                    em.Emit(sprintf "store %s %s, ptr %s" lanes v slot)
                    let kind = [ "f32"; "f64"; "i8"; "i16"; "i32"; "i64"; "u8"; "u16"; "u32"; "u64"; "bool" ] |> List.findIndex ((=) e)
                    em.Instr(sprintf "call ptr @zs_str_of_lanes(ptr %s, i_W %d, i_W %d)" slot kind k)
                | "string" -> arg 0
                | "bool" -> em.Instr(sprintf "call ptr @zs_str_of_bool(i1 zeroext %s)" (arg 0))
                | "char" -> em.Instr(sprintf "call ptr @zs_str_of_char(i32 %s)" (arg 0))
                | "f64" -> em.Instr(sprintf "call ptr @zs_str_of_f64(double %s)" (arg 0))
                | "f32" -> em.Instr(sprintf "call ptr @zs_str_of_f32(float %s)" (arg 0))
                | _ when isUnsigned t ->
                    let v = if lt = "i64" then arg 0 else em.Instr(sprintf "zext %s %s to i64" lt (arg 0))
                    em.Instr(sprintf "call ptr @zs_str_of_u64(i64 %s)" v)
                | _ ->
                    let v = if lt = "i64" then arg 0 else em.Instr(sprintf "sext %s %s to i64" lt (arg 0))
                    em.Instr(sprintf "call ptr @zs_str_of_i64(i64 %s)" v)
            | "compare" ->
                let t = argTy 0
                let lt = llty t

                match tyName t with
                | "string" ->
                    let c = em.Instr(sprintf "call i_W @zs_str_cmp(ptr %s, ptr %s)" (arg 0) (arg 1))
                    dropValue em t (arg 0)
                    dropValue em t (arg 1)
                    c
                | _ ->
                    let gt, lt' =
                        if isFloat t then
                            em.Instr(sprintf "fcmp ogt %s %s, %s" lt (arg 0) (arg 1)), em.Instr(sprintf "fcmp olt %s %s, %s" lt (arg 0) (arg 1))
                        else
                            let u = if isUnsigned t then "u" else "s"
                            em.Instr(sprintf "icmp %sgt %s %s, %s" u lt (arg 0) (arg 1)), em.Instr(sprintf "icmp %slt %s %s, %s" u lt (arg 0) (arg 1))

                    let a = em.Instr(sprintf "zext i1 %s to i_W" gt)
                    let b = em.Instr(sprintf "zext i1 %s to i_W" lt')
                    em.Instr(sprintf "sub i_W %s, %s" a b)
            | "hash" ->
                let t = argTy 0
                let lt = llty t

                match tyName t with
                | "string" ->
                    let h = em.Instr(sprintf "call i_W @zs_str_hash(ptr %s)" (arg 0))
                    dropValue em t (arg 0)
                    h
                | "f64" -> foldWord em (em.Instr(sprintf "bitcast double %s to i64" (arg 0)))
                | "f32" -> em.Instr(sprintf "zext i32 %s to i_W" (em.Instr(sprintf "bitcast float %s to i32" (arg 0))))
                | _ when lt = wordTy () -> arg 0
                | _ when lt = "i64" -> foldWord em (arg 0) // i64/u64 on a 32-bit chip
                | _ -> em.Instr(sprintf "%s %s %s to i_W" (if isUnsigned t || lt = "i1" then "zext" else "sext") lt (arg 0))
            | "Process.exit" ->
                em.Emit(sprintf "call void @zs_exit(i_W %s)" (arg 0))
                em.Emit "unreachable"
                em.Dead()
                "poison"
            | "String.ofCStr" -> em.Instr(sprintf "call ptr @zs_str_from_c(ptr %s)" (arg 0))
            | _ when runtimePrims.ContainsKey op ->
                let fn, ret, pts = runtimePrims[op]

                // work for another thread: its objects shared first
                if op = "Loop.blocking" || op = "Loop.spawn" then
                    shareValue em (argTy 0) (arg 0)

                let real = List.zip args vs |> List.filter (fun (a, _) -> prune a.ty <> tUnit)
                let argv = List.zip pts real |> List.map (fun (pt, (_, v)) -> pt.TrimEnd '!' + " " + v) |> String.concat ", "
                let call = sprintf "call %s @%s(%s)" ret fn argv

                let r =
                    if ret = "void" then
                        em.Emit call
                        "zeroinitializer"
                    else
                        em.Instr call

                for k, (a, v) in List.indexed real do
                    if not (borrowed0 && k = 0) && not ((List.item k pts).EndsWith "!") then
                        dropValue em a.ty v

                r
            | "String.length" ->
                let lp = em.Instr(sprintf "getelementptr i8, ptr %s, i_W HDR1" (arg 0))
                let n = loadLen em lp
                if not borrowed0 then dropValue em (argTy 0) (arg 0)
                n
            | "ref" ->
                let cell = sprintf "{ i_W, %s }" (llty (argTy 0))
                let r = em.Instr(sprintf "call ptr @zs_alloc(i_W %s)" (sizeOf em cell))
                em.Emit(sprintf "store i_W 1, ptr %s" r)
                let vp = em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 1" cell r)
                em.Emit(sprintf "store %s %s, ptr %s" (llty (argTy 0)) (arg 0) vp)
                r
            | "ref.get" ->
                let vp = em.Instr(sprintf "getelementptr { i_W, %s }, ptr %s, i32 0, i32 1" (llty ty) (arg 0))
                let v = em.Instr(sprintf "load %s, ptr %s" (llty ty) vp)
                dupValue em ty v
                dropValue em (argTy 0) (arg 0)
                v
            | "ref.set" ->
                let vt = argTy 1
                let vp = em.Instr(sprintf "getelementptr { i_W, %s }, ptr %s, i32 0, i32 1" (llty vt) (arg 0))
                let old = em.Instr(sprintf "load %s, ptr %s" (llty vt) vp)
                em.Emit(sprintf "store %s %s, ptr %s" (llty vt) (arg 1) vp)
                dropValue em vt old
                dropValue em (argTy 0) (arg 0)
                "zeroinitializer"
            | "Array.length" ->
                let lp = em.Instr(sprintf "getelementptr { i_W, i_W }, ptr %s, i32 0, i32 1" (arg 0))
                let n = loadLen em lp
                if not borrowed0 then dropValue em (argTy 0) (arg 0)
                n
            | "Array.create" ->
                let el = argTy 1
                let n = arg 0
                check em (em.Instr(sprintf "icmp sge i_W %s, 0" n)) "negative array size"
                let a = newArray el n
                let at = sprintf "{ i_W, i_W, [0 x %s] }" (llty el)
                let slot = "%" + em.Fresh "fill"
                em.Alloca(sprintf "%s = alloca i_W" slot)
                em.Emit(sprintf "store i_W 0, ptr %s" slot)
                let lc, lb, lend = em.Fresh "acond", em.Fresh "abody", em.Fresh "aend"
                em.Emit(sprintf "br label %%%s" lc)
                em.Label lc
                let i = em.Instr(sprintf "load i_W, ptr %s" slot)
                em.Emit(sprintf "br i1 %s, label %%%s, label %%%s" (em.Instr(sprintf "icmp slt i_W %s, %s" i n)) lb lend)
                em.Label lb
                let ep = em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 2, i_W %s" at a i)
                em.Emit(sprintf "store %s %s, ptr %s" (llty el) (arg 1) ep)
                dupValue em el (arg 1)
                em.Emit(sprintf "store i_W %s, ptr %s" (em.Instr(sprintf "add i_W %s, 1" i)) slot)
                em.Emit(sprintf "br label %%%s" lc)
                em.Label lend
                dropValue em el (arg 1) // each slot took its own reference
                a
            | "array.lit" ->
                let el =
                    match prune ty with
                    | TCon("array", [ el ]) -> el
                    | _ -> failwith "array literal type"

                let a = newArray el (string vs.Length)

                vs
                |> List.iteri (fun i v ->
                    let ep = em.Instr(sprintf "getelementptr { i_W, i_W, [0 x %s] }, ptr %s, i32 0, i32 2, i_W %d" (llty el) a i)
                    em.Emit(sprintf "store %s %s, ptr %s" (llty el) v ep))

                a
            | "array.get" ->
                if not unchecked then
                    bounds (arg 0) (arg 1)

                let el, ep = elemPtr (arg 0) (arg 1)
                let v = em.Instr(sprintf "load %s, ptr %s" (llty el) ep)
                dupValue em el v
                if not borrowed0 then dropValue em (argTy 0) (arg 0)
                v
            | "array.update" ->
                // Array.set a i x: a changed array (the same one when `a` was unique)
                let u = em.Instr(sprintf "call ptr %s(ptr %s)" (uniqueFn (argTy 0) false) (arg 0))
                bounds u (arg 1)
                let el, ep = elemPtr u (arg 1)
                let old = em.Instr(sprintf "load %s, ptr %s" (llty el) ep)
                em.Emit(sprintf "store %s %s, ptr %s" (llty el) (arg 2) ep)
                dropValue em el old
                u
            | "array.copy" -> em.Instr(sprintf "call ptr %s(ptr %s)" (uniqueFn (argTy 0) true) (arg 0))
            | "wrap+"
            | "wrap-"
            | "wrap*" ->
                let instr = dict [ "wrap+", "add"; "wrap-", "sub"; "wrap*", "mul" ]
                em.Instr(sprintf "%s %s %s, %s" instr[op] (llty ty) (arg 0) (arg 1))
            | "slot.take" -> arg 0
            | "mmio.read.u32"
            | "mmio.read.u8" ->
                // a hardware register: a volatile load the optimizer keeps exactly as written
                let w = if op.EndsWith "u32" then "i32" else "i8"
                let p = em.Instr(sprintf "inttoptr i_W %s to ptr" (arg 0))
                em.Instr(sprintf "load volatile %s, ptr %s" w p)
            | "mmio.write.u32"
            | "mmio.write.u8" ->
                let w = if op.EndsWith "u32" then "i32" else "i8"
                let p = em.Instr(sprintf "inttoptr i_W %s to ptr" (arg 0))
                em.Emit(sprintf "store volatile %s %s, ptr %s" w (arg 1) p)
                "zeroinitializer"
            | "Runtime.ticks" -> em.Instr "call i64 @zs_ticks()"
            | "Runtime.mallocs" -> em.Instr "call i_W @zs_mallocs()"
            | "par.fork" ->
                // a job for the thread pool: the closure's objects shared, its reference moved
                // into the job, whose runner stores its result for par.join
                let rt =
                    match prune (argTy 0) with
                    | TFun(_, r) -> r
                    | t -> failwithf "par.fork of %s" (show t)

                shareValue em (argTy 0) (arg 0)
                em.Instr(sprintf "call ptr @zs_par_fork(ptr %s, ptr %s, i_W %s)" (arg 0) (parRunner rt) (sizeOf em (llty rt)))
            | "par.join" ->
                // the job's result (moved out), once it has run: here, or on the thread that stole it
                let rp = em.Instr(sprintf "call ptr @zs_par_join(ptr %s)" (arg 0))
                let r = em.Instr(sprintf "load %s, ptr %s" (llty ty) rp)
                em.Emit(sprintf "call void @zs_par_free(ptr %s)" (arg 0))
                r
            | "par.workers" -> em.Instr "call i_W @zs_par_workers()"
            | "atomic.make" ->
                let st, toStore, _ = atomicRep (argTy 0)
                let cell = sprintf "{ i_W, %s }" st
                let r = em.Instr(sprintf "call ptr @zs_alloc(i_W %s)" (sizeOf em cell))
                em.Emit(sprintf "store i_W 1, ptr %s" r)
                em.Emit(sprintf "store %s %s, ptr %s" st (toStore (arg 0)) (em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 1" cell r)))
                r
            | "atomic.get"
            | "atomic.set"
            | "atomic.exchange"
            | "atomic.cas"
            | "atomic.add" ->
                // sequentially consistent, on the value in the cell { count, value }
                let vt = match prune (argTy 0) with
                         | TCon("Atomic", [ v ]) -> v
                         | t -> failwithf "%s of %s" op (show t)

                let st, toStore, ofStore = atomicRep vt
                let vp = em.Instr(sprintf "getelementptr { i_W, %s }, ptr %s, i32 0, i32 1" st (arg 0))

                let align =
                    match st with
                    | "i8" -> "1"
                    | "i16" -> "2"
                    | "i32"
                    | "float" -> "4"
                    | "i_W" -> "HDR1"
                    | _ -> "8"

                let r =
                    match op with
                    | "atomic.get" -> ofStore (em.Instr(sprintf "load atomic %s, ptr %s seq_cst, align %s" st vp align))
                    | "atomic.set" ->
                        em.Emit(sprintf "store atomic %s %s, ptr %s seq_cst, align %s" st (toStore (arg 1)) vp align)
                        "zeroinitializer"
                    | "atomic.exchange" -> ofStore (em.Instr(sprintf "atomicrmw xchg ptr %s, %s %s seq_cst" vp st (toStore (arg 1))))
                    | "atomic.cas" ->
                        // compared as bits (cmpxchg takes integers): the value it held
                        let it, toInt, ofInt =
                            match st with
                            | "double" -> "i64", (fun v -> em.Instr(sprintf "bitcast double %s to i64" v)), (fun v -> em.Instr(sprintf "bitcast i64 %s to double" v))
                            | "float" -> "i32", (fun v -> em.Instr(sprintf "bitcast float %s to i32" v)), (fun v -> em.Instr(sprintf "bitcast i32 %s to float" v))
                            | t -> t, id, id

                        let pair = em.Instr(sprintf "cmpxchg ptr %s, %s %s, %s %s seq_cst seq_cst" vp it (toInt (toStore (arg 1))) it (toInt (toStore (arg 2))))
                        ofStore (ofInt (em.Instr(sprintf "extractvalue { %s, i1 } %s, 0" it pair)))
                    | _ ->
                        // add: the new value (wrapping, as atomic arithmetic does)
                        if isFloat vt then
                            let old = em.Instr(sprintf "atomicrmw fadd ptr %s, %s %s seq_cst" vp st (arg 1))
                            em.Instr(sprintf "fadd %s %s, %s" st old (arg 1))
                        else
                            let old = em.Instr(sprintf "atomicrmw add ptr %s, %s %s seq_cst" vp st (arg 1))
                            em.Instr(sprintf "add %s %s, %s" st old (arg 1))

                dropValue em (argTy 0) (arg 0)
                r
            | "mutex.make" ->
                // { count, lock, value }: what it holds is always shared
                let vt = argTy 0
                let cell = sprintf "{ i_W, i32, %s }" (llty vt)
                shareValue em vt (arg 0)
                let r = em.Instr(sprintf "call ptr @zs_alloc(i_W %s)" (sizeOf em cell))
                em.Emit(sprintf "store i_W 1, ptr %s" r)
                em.Emit(sprintf "store i32 0, ptr %s" (em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 1" cell r)))
                em.Emit(sprintf "store %s %s, ptr %s" (llty vt) (arg 0) (em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 2" cell r)))
                r
            | "mutex.get"
            | "mutex.set"
            | "mutex.update" ->
                let vt = match prune (argTy 0) with
                         | TCon("Mutex", [ v ]) -> v
                         | t -> failwithf "%s of %s" op (show t)

                let lt = llty vt
                let cell = sprintf "{ i_W, i32, %s }" lt
                let lp = em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 1" cell (arg 0))
                let vp = em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 2" cell (arg 0))

                let r =
                    match op with
                    | "mutex.get" ->
                        // a reference of its own, taken under the lock: a set may drop the old value
                        em.Emit(sprintf "call void @zs_lock(ptr %s)" lp)
                        let v = em.Instr(sprintf "load %s, ptr %s" lt vp)
                        dupValue em vt v
                        em.Emit(sprintf "call void @zs_unlock(ptr %s)" lp)
                        v
                    | "mutex.set" ->
                        shareValue em vt (arg 1)
                        em.Emit(sprintf "call void @zs_lock(ptr %s)" lp)
                        let old = em.Instr(sprintf "load %s, ptr %s" lt vp)
                        em.Emit(sprintf "store %s %s, ptr %s" lt (arg 1) vp)
                        em.Emit(sprintf "call void @zs_unlock(ptr %s)" lp)
                        dropValue em vt old
                        "zeroinitializer"
                    | _ ->
                        // f's result replaces the value, under the lock (f gets the mutex's reference)
                        em.Emit(sprintf "call void @zs_lock(ptr %s)" lp)
                        let old = em.Instr(sprintf "load %s, ptr %s" lt vp)
                        let code = em.Instr(sprintf "load ptr, ptr %s" (em.Instr(sprintf "getelementptr { i_W, ptr }, ptr %s, i32 0, i32 1" (arg 1))))
                        let v = em.Instr(sprintf "call %s %s(ptr %s, %s %s)" lt code (arg 1) lt old)
                        shareValue em vt v
                        em.Emit(sprintf "store %s %s, ptr %s" lt v vp)
                        dupValue em vt v
                        em.Emit(sprintf "call void @zs_unlock(ptr %s)" lp)
                        dropValue em (argTy 1) (arg 1)
                        v

                dropValue em (argTy 0) (arg 0)
                r
            | "chan.make" ->
                let vt = match prune ty with
                         | TCon("Channel", [ v ]) -> v
                         | t -> failwithf "chan.make of %s" (show t)

                check em (em.Instr(sprintf "icmp sgt i_W %s, 0" (arg 0))) "a channel's capacity must be at least 1"
                em.Instr(sprintf "call ptr @zs_chan_new(i_W %s, i_W %s, ptr %s)" (arg 0) (sizeOf em (llty vt)) (slotDrop vt))
            | "chan.send" ->
                // the value, shared, moves into the channel (the runtime copies its bytes)
                let vt = argTy 1
                shareValue em vt (arg 1)
                let slot = "%" + em.Fresh "sent"
                em.Alloca(sprintf "%s = alloca %s" slot (llty vt))
                em.Emit(sprintf "store %s %s, ptr %s" (llty vt) (arg 1) slot)
                em.Emit(sprintf "call void @zs_chan_send(ptr %s, ptr %s)" (arg 0) slot)
                dropValue em (argTy 0) (arg 0)
                "zeroinitializer"
            | "chan.receive" ->
                // Some value, or None once the channel is closed and empty
                let t =
                    match prune ty with
                    | TCon(_, [ t ]) -> t
                    | _ -> failwith "chan.receive"

                let slot = "%" + em.Fresh "received"
                em.Alloca(sprintf "%s = alloca %s" slot (llty t))
                let ok = em.Instr(sprintf "call i1 @zs_chan_recv(ptr %s, ptr %s)" (arg 0) slot)
                dropValue em (argTy 0) (arg 0)
                let _, cases = union ty
                let tagOf (c: string) = cases |> List.findIndex (fun (n, _) -> n = c)
                let gotL, closedL, doneL = em.Fresh "got", em.Fresh "closed", em.Fresh "received"
                em.Emit(sprintf "br i1 %s, label %%%s, label %%%s" ok gotL closedL)
                em.Label gotL
                let x = "$recv" + em.Fresh ""
                let v = em.Instr(sprintf "load %s, ptr %s" (llty t) slot)
                let some = gen (env.Add(x, Ssa v)) false { k = CCtor("option", tagOf "Some", [ { k = CLocal x; ty = t } ]); ty = ty }
                let fromSome = em.Block
                em.Emit(sprintf "br label %%%s" doneL)
                em.Label closedL
                let none = gen env false { k = CCtor("option", tagOf "None", []); ty = ty }
                let fromNone = em.Block
                em.Emit(sprintf "br label %%%s" doneL)
                em.Label doneL
                phi (llty ty) [ some, fromSome; none, fromNone ]
            | "chan.close" ->
                em.Emit(sprintf "call void @zs_chan_close(ptr %s)" (arg 0))
                dropValue em (argTy 0) (arg 0)
                "zeroinitializer"
            | _ when op.StartsWith "vec." || op.StartsWith "mask." -> simdPrim op args vs argTy ty borrowed0 unchecked
            | _ when op.StartsWith "llvm:" ->
                // a target intrinsic (Simd.X86, Simd.Arm): for its architecture only
                let name = op.Substring 5
                let arch = if name.StartsWith "llvm.x86." then "x86_64" else "aarch64"

                let building =
                    if target = "" then
                        if Runtime.InteropServices.RuntimeInformation.OSArchitecture = Runtime.InteropServices.Architecture.X64 then "x86_64" else "aarch64"
                    else
                        target.Split('-')[0]

                let zsName, _, _, _, need = simdIntrinsics |> List.find (fun (_, i, _, _, _) -> i = name)

                if building <> arch then
                    fail 0 (sprintf "%s is for %s; this build is for %s" zsName arch building)

                // the CPU feature it needs: the target's baseline has it, or --cpu, or the
                // function's [<Target>] (an unknown --cpu, native say, is trusted)

                let cpuHas =
                    match cpu with
                    | None -> Some [ "sse2" ]
                    | Some c when arch = "x86_64" && x86CpuFeatures.ContainsKey c -> Some x86CpuFeatures[c]
                    | Some _ -> None

                match cpuHas with
                | Some have when arch = "x86_64" && not (featuresInclude (have @ featureList) need) ->
                    fail 0 (sprintf "%s needs the CPU feature %s: build with --cpu (x86-64-v3, say), or mark the function [<Target \"%s\">] (or [<Multiversion>])" zsName need need)
                | _ when arch = "aarch64" && need <> "" && cpu.IsNone && not (List.contains need featureList) ->
                    fail 0 (sprintf "%s needs the CPU feature %s: build with --cpu, or mark the function [<Target \"%s\">] (or [<Multiversion>])" zsName need need)
                | _ -> ()

                intrinsic em name (llty ty) (List.zip (args |> List.map (fun a -> llty a.ty)) vs) ""
            | "weak.new" ->
                let t = argTy 0

                if not (heap t && llty t = "ptr") then
                    fail 0 (sprintf "weak<%s> isn't possible: a weak reference is to an object (a union's cell, a ref, an array, a string, a closure or a dyn value)" (show t))

                // the cell takes no reference to the object; the argument's is given up
                let w = em.Instr(sprintf "call ptr @zs_weak_new(ptr %s)" (arg 0))
                dropValue em t (arg 0)
                w
            | "weak.get" ->
                // Some object (with a reference of its own) while it lives, else None
                let t =
                    match prune ty with
                    | TCon(_, [ t ]) -> t
                    | _ -> failwith "weak.get"

                let target = em.Instr(sprintf "call ptr @zs_weak_target(ptr %s)" (arg 0))
                dropValue em (argTy 0) (arg 0)
                let _, cases = union ty
                let tagOf (c: string) = cases |> List.findIndex (fun (n, _) -> n = c)
                let aliveL, deadL, gotL = em.Fresh "alive", em.Fresh "dead", em.Fresh "got"
                em.Emit(sprintf "br i1 %s, label %%%s, label %%%s" (em.Instr(sprintf "icmp ne ptr %s, null" target)) aliveL deadL)
                em.Label aliveL
                let x = "$weak" + em.Fresh ""
                let some = gen (env.Add(x, Ssa target)) false { k = CCtor("option", tagOf "Some", [ { k = CLocal x; ty = t } ]); ty = ty }
                let fromSome = em.Block
                em.Emit(sprintf "br label %%%s" gotL)
                em.Label deadL
                let none = gen env false { k = CCtor("option", tagOf "None", []); ty = ty }
                let fromNone = em.Block
                em.Emit(sprintf "br label %%%s" gotL)
                em.Label gotL
                phi (llty ty) [ some, fromSome; none, fromNone ]
            | "arena.with" ->
                // f () with an arena open: what it allocates comes from the arena's blocks
                em.Emit "call void @zs_arena_open()"
                let code = em.Instr(sprintf "load ptr, ptr %s" (em.Instr(sprintf "getelementptr { i_W, ptr }, ptr %s, i32 0, i32 1" (arg 0))))
                let r = em.Instr(sprintf "call %s %s(ptr %s, {} zeroinitializer)" (llty ty) code (arg 0))
                em.Emit "call void @zs_arena_close()"
                dropValue em (argTy 0) (arg 0)
                r
            | _ when op.StartsWith "fn:" -> "zeroinitializer" // a function named for a vtable
            | _ when op.StartsWith "dyn.box:" ->
                // { count, vtable, value }: the value moves in; the vtable frees it, then has
                // the trait's methods for the value's type
                let t = argTy 0
                let cell = sprintf "{ i_W, ptr, %s }" (llty t)
                let vt = vtable (op.Substring 8) t (args |> List.tail |> List.map (fun a -> match a.k with CPrim(f, _) -> f.Substring 3 | _ -> failwith "vtable entry"))
                let c = em.Instr(sprintf "call ptr @zs_alloc(i_W %s)" (sizeOf em cell))
                em.Emit(sprintf "store i_W 1, ptr %s" c)
                em.Emit(sprintf "store ptr %s, ptr %s" vt (em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 1" cell c)))
                em.Emit(sprintf "store %s %s, ptr %s" (llty t) (arg 0) (em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 2" cell c)))
                c
            | "dyn.unbox" ->
                // the value a dyn holds, with a reference of its own; the dyn's is given up
                let v = em.Instr(sprintf "load %s, ptr %s" (llty ty) (em.Instr(sprintf "getelementptr { i_W, ptr, %s }, ptr %s, i32 0, i32 2" (llty ty) (arg 0))))
                dupValue em ty v
                dropValue em (argTy 0) (arg 0)
                v
            | _ when op.StartsWith "dyn.call:" ->
                // the method at this index of the vtable, given the dyn (whose reference it takes)
                // and the other arguments
                let i = int (op.Substring 9)
                let vt = em.Instr(sprintf "load ptr, ptr %s" (em.Instr(sprintf "getelementptr { i_W, ptr }, ptr %s, i32 0, i32 1" (arg 0))))
                let entry = em.Instr(sprintf "load ptr, ptr %s" (em.Instr(sprintf "getelementptr ptr, ptr %s, i32 %d" vt (i + 1))))
                let argv = List.zip args vs |> List.map (fun (a, v) -> sprintf "%s %s" (llty a.ty) v) |> String.concat ", "
                em.Instr(sprintf "call %s %s(%s)" (llty ty) entry argv)
            // raw pointers (ptr<T>): T is C data (the type checker allows nothing else), so
            // nothing is counted
            | "ptr.read" ->
                if heap ty then fail 0 (sprintf "Ptr.read: a ptr<%s> can't be read, since %s is reference counted" (show ty) (show ty))
                if llty ty = "{}" then "zeroinitializer" else em.Instr(sprintf "load %s, ptr %s" (llty ty) (arg 0))
            | "ptr.write" ->
                let vt = argTy 1
                if heap vt then fail 0 (sprintf "Ptr.write: a ptr<%s> can't be written, since %s is reference counted" (show vt) (show vt))
                if llty vt <> "{}" then em.Emit(sprintf "store %s %s, ptr %s" (llty vt) (arg 1) (arg 0))
                "zeroinitializer"
            | "ptr.add" ->
                let el =
                    match prune (argTy 0) with
                    | TCon("ptr", [ el ]) -> el
                    | _ -> failwith "ptr.add"

                if llty el = "{}" then arg 0 else em.Instr(sprintf "getelementptr %s, ptr %s, i_W %s" (llty el) (arg 0) (arg 1))
            | "ptr.null" -> "null"
            | "ptr.isNull" -> em.Instr(sprintf "icmp eq ptr %s, null" (arg 0))
            | "ptr.cast" -> arg 0
            | "ptr.alloc" ->
                let el =
                    match prune ty with
                    | TCon("ptr", [ el ]) -> el
                    | _ -> failwith "ptr.alloc"

                em.Instr(sprintf "call ptr @zs_ptr_alloc(i_W %s, i_W %s)" (arg 0) (sizeOf em (llty el)))
            | "ptr.free" ->
                em.Emit(sprintf "call void @zs_ptr_free(ptr %s)" (arg 0))
                "zeroinitializer"
            | "fnptr.call" ->
                // a C function pointer called with C's conventions, as an extern is
                let rec split t =
                    match prune t with
                    | TFun(a, r) ->
                        let ps, res = split r
                        a :: ps, res
                    | r -> [], r

                let pars =
                    match prune (argTy 0) with
                    | TCon("fnptr", [ f ]) -> fst (split f) |> List.filter (fun p -> prune p <> tUnit)
                    | _ -> failwith "fnptr.call"

                cCall (arg 0) { pars = pars; ret = ty; variadic = false } (List.tail args) (List.tail vs)
            | "Runtime.allocations" -> em.Instr "call i_W @zs_allocations()"
            | "token.null" -> "null" // no cell to build in (a jump to a join point)
            | "Math.sqrt" ->
                // one instruction where the hardware has it (x86-64, aarch64, the M4's FPU)
                let lt = llty (argTy 0)
                em.Instr(sprintf "call %s @llvm.sqrt.%s(%s %s)" lt (if lt = "double" then "f64" else "f32") lt (arg 0))
            | "array.set" ->
                bounds (arg 0) (arg 1)
                let el, ep = elemPtr (arg 0) (arg 1)
                let old = em.Instr(sprintf "load %s, ptr %s" (llty el) ep)
                em.Emit(sprintf "store %s %s, ptr %s" (llty el) (arg 2) ep)
                dropValue em el old
                dropValue em (argTy 0) (arg 0)
                "zeroinitializer"
            | "conv" ->
                let src, dst = argTy 0, ty
                let ls, ld = llty src, llty dst
                let v = arg 0

                if ls = ld && isFloat src = isFloat dst then
                    v
                elif isFloat src && isFloat dst then
                    em.Instr(sprintf "%s %s %s to %s" (if ls = "float" then "fpext" else "fptrunc") ls v ld)
                elif isFloat src then
                    em.Instr(sprintf "%s %s %s to %s" (if isUnsigned dst then "fptoui" else "fptosi") ls v ld)
                elif isFloat dst then
                    em.Instr(sprintf "%s %s %s to %s" (if isUnsigned src then "uitofp" else "sitofp") ls v ld)
                else
                    let bits (s: string) = int (s.Substring 1)

                    if bits ls > bits ld then em.Instr(sprintf "trunc %s %s to %s" ls v ld)
                    elif bits ls < bits ld then em.Instr(sprintf "%s %s %s to %s" (if isUnsigned src then "zext" else "sext") ls v ld)
                    else v
            | _ -> failwithf "unknown primitive %s" op

        let env = f.pars |> List.fold (fun (m: Map<_, _>) (x, _) -> m.Add(x, Ssa("%p." + x))) Map.empty
        f.pars |> List.iteri (fun i (x, t) -> declareVar x t ("%p." + x) None (i + 1))
        let v = gen env true f.body
        let rt = llty f.ret

        if debugInfo then
            em.Dbg <- diLoc (max 1 lastLine) sp // returning belongs to the last statement, not the header

        em.Emit(sprintf "ret %s %s" rt v)
        let ps = f.pars |> List.map (fun (x, t) -> sprintf "%s %%p.%s" (llty t) x) |> String.concat ", "
        let dbg = if debugInfo then " !dbg " + sp else ""

        // a function taking a function (List.map, a lifted loop over a closure): inlining it
        // lets the closure call become direct, and the closure's allocation disappear
        let hint =
            if f.pars |> List.exists (fun (_, t) -> match prune t with TFun _ -> true | _ -> false) then " inlinehint" else ""

        // called from another part: external (hidden in the program)
        let linkage =
            match part with
            | Some p when p.called.Contains f.name -> "hidden"
            | _ -> "internal"

        let linkage = if name <> f.name then "internal" else linkage // a version: only its dispatcher calls it

        let features =
            if features = "" then ""
            else sprintf " \"target-features\"=\"%s\"" (features.Split ',' |> Array.map (fun f -> "+" + f.Trim()) |> String.concat ",")

        funcs.Append(sprintf "define %s %s %s(%s)%s%s%s {\n%s}\n\n" linkage rt (sym name) ps hint features dbg em.Body) |> ignore

    /// A [<Multiversion>] function: a version for each set of features, and one for the baseline;
    /// its own name is a dispatcher that picks one the first time (the first the CPU has, in
    /// order) and calls it.
    let multiversion (f: MFun) (versions: string list) =
        for v in versions do
            genFunAs f (f.name + "." + v) v

        genFunAs f (f.name + ".default") ""
        let rt = llty f.ret
        let ps = f.pars |> List.map (fun (x, t) -> sprintf "%s %%p.%s" (llty t) x) |> String.concat ", "
        let slot = sprintf "@\"mv.%s\"" f.name
        top.AppendLine(sprintf "%s = internal global ptr null" slot) |> ignore
        let em = Emitter()
        let cached = em.Instr(sprintf "load atomic ptr, ptr %s monotonic, align HDR1" slot)
        em.Emit(sprintf "br i1 %s, label %%pick, label %%go" (em.Instr(sprintf "icmp eq ptr %s, null" cached)))
        em.Label "pick"

        let chosen =
            List.foldBack
                (fun (v: string) (rest: string) ->
                    let name = sprintf "@\"cpu.%s\"" v

                    if generated.Add name then
                        top.AppendLine(sprintf "%s = private unnamed_addr constant [%d x i8] c\"%s\\00\"" name (v.Length + 1) v) |> ignore

                    let ok = em.Instr(sprintf "call i1 @zs_cpu_supports(ptr %s)" name)
                    em.Instr(sprintf "select i1 %s, ptr %s, ptr %s" ok (sym (f.name + "." + v)) rest))
                versions
                (sym (f.name + ".default"))

        em.Emit(sprintf "store atomic ptr %s, ptr %s monotonic, align HDR1" chosen slot)
        em.Emit "br label %go"
        em.Label "go"
        let p = em.Instr(sprintf "phi ptr [ %s, %%entry ], [ %s, %%pick ]" cached chosen)
        let args = f.pars |> List.map (fun (x, t) -> sprintf "%s %%p.%s" (llty t) x) |> String.concat ", "
        let r = em.Instr(sprintf "musttail call %s %s(%s)" rt p args)
        em.Emit(sprintf "ret %s %s" rt r)

        let linkage =
            match part with
            | Some p when p.called.Contains f.name -> "hidden"
            | _ -> "internal"

        funcs.Append(sprintf "define %s %s %s(%s) {\n%s}\n\n" linkage rt (sym f.name) ps em.Body) |> ignore

    let genFun (f: MFun) =
        match targets.TryGetValue(baseFunName f.name) with
        | true, "multiversion" :: versions when not (f.name.Contains "$") -> multiversion f versions
        | true, [ "target"; features ] -> genFunAs f f.name features
        | _ -> genFunAs f f.name ""

    for KeyValue(name, s) in externs do
        let ret, sret = cRet s.ret
        let sretP = if sret then [ sprintf "ptr sret(%s)" (llty s.ret) ] else []
        let ps = sretP @ cParamList s.pars sret @ (if s.variadic then [ "..." ] else [])
        top.AppendLine(sprintf "declare %s @%s(%s)" ret name (String.concat ", " ps)) |> ignore

    for f in funs do
        if defined f.name then
            genFun f

    /// Runs the initializers in order, storing each value (main's prologue). With threads, a
    /// value threads can share is marked shared: any of them may read it.
    let initValues () =
        values
        |> List.mapi (fun i (v, init) ->
            let t = llty valueTypes[v]

            let share =
                if threaded && (shareBlocker ignore types Set.empty valueTypes[v]).IsNone then
                    let em = Emitter()
                    shareValue em valueTypes[v] (sprintf "%%iv%d" i)
                    em.Code
                else
                    ""

            sprintf "  %%iv%d = call %s %s()\n%s  store %s %%iv%d, ptr %s\n" i t (sym init) share t i (valueSym v))
        |> String.concat ""

    // the values, released in reverse order after main returns (so the leak check stays exact)
    if entry then
        let em = Emitter()

        for v, _ in List.rev values do
            let t = valueTypes[v]

            if heap t then
                dropValue em t (em.Instr(sprintf "load %s, ptr %s" (llty t) (valueSym v)))

        em.Emit "ret void"
        funcs.Append(sprintf "define private void @zsv.dropAll() {\n%s}\n\n" em.Body) |> ignore

    // C entry points: main (an int result becomes the exit code) and [<Export>] wrappers
    if entry && fnTable.ContainsKey "main" then
        let main = fnTable["main"]
        let rt = llty main.ret

        let body =
            match tyName main.ret with
            | "unit" -> sprintf "  call {} %s({} zeroinitializer)\n  ret i32 0" (sym "main")
            | _ when rt = "i32" -> sprintf "  %%r = call i32 %s({} zeroinitializer)\n  ret i32 %%r" (sym "main")
            | _ -> sprintf "  %%r = call %s %s({} zeroinitializer)\n  %%c = trunc %s %%r to i32\n  ret i32 %%c" rt (sym "main") rt

        funcs.AppendLine("define i32 @main(i32 %argc, ptr %argv) {").AppendLine("  call void @zs_set_args(i32 %argc, ptr %argv)") |> ignore
        funcs.Append(initValues ()) |> ignore
        funcs.AppendLine(body.Replace("  ret i32", "  call void @zsv.dropAll()\n  ret i32")).AppendLine("}") |> ignore

    // a test build (zs test): `exe <n>` runs test n, so each test runs in its own process
    if entry && not tests.IsEmpty && not (fnTable.ContainsKey "main") then
        let cases = tests |> List.mapi (fun i _ -> sprintf "i_W %d, label %%t%d" i i) |> String.concat " "
        funcs.AppendLine("define i32 @main(i32 %argc, ptr %argv) {") |> ignore
        funcs.AppendLine("  call void @zs_set_args(i32 %argc, ptr %argv)") |> ignore
        funcs.Append(initValues ()) |> ignore
        funcs.AppendLine("  %n = call i_W @zs_test_index()") |> ignore
        funcs.AppendLine(sprintf "  switch i_W %%n, label %%bad [ %s ]" cases) |> ignore

        tests
        |> List.iteri (fun i t ->
            funcs.AppendLine(sprintf "t%d:\n  call {} %s({} zeroinitializer)\n  call void @zsv.dropAll()\n  ret i32 0" i (sym t)) |> ignore)

        funcs.AppendLine("bad:\n  ret i32 2\n}") |> ignore

    for e in (if entry then exports else []) do
        let fd = fnTable[e.fname]
        let em = Emitter()
        let rt, sret = cRet e.ret
        let cps = ResizeArray<string>()

        if sret then
            cps.Add(sprintf "ptr sret(%s) align 8 %%ret" (llty e.ret))

        let modes = cModes (fd.pars |> List.map snd) sret

        let args =
            fd.pars
            |> List.mapi (fun i (_, t) ->
                let n = sprintf "%%a%d" i

                match prune t with
                | TCon("unit", []) -> t, "zeroinitializer"
                | _ when isHandle t ->
                    // C lends the handle: the object, with a reference of its own for the function
                    cps.Add(sprintf "ptr %s" n)
                    t, em.Instr(sprintf "call ptr @zs_handle_get(ptr %s)" n)
                | _ ->
                    match List.item i modes with
                    | Scalar ->
                        cps.Add(sprintf "%s %s" (cParam t) n)
                        t, n
                    | Pieces ps ->
                        let named =
                            ps
                            |> List.mapi (fun k p ->
                                let nk = sprintf "%s.%d" n k
                                cps.Add(p + " " + nk)
                                p, nk)

                        t, fromPieces em t named
                    | Memory ->
                        cps.Add(sprintf "%s %s" (byval t) n)
                        t, em.Instr(sprintf "load %s, ptr %s" (llty t) n))

        let argv = args |> List.map (fun (t, v) -> sprintf "%s %s" (llty t) v) |> String.concat ", "
        let r = em.Instr(sprintf "call %s %s(%s)" (llty fd.ret) (sym e.fname) argv)

        match prune e.ret, abiFor e.ret true with
        | TCon("unit", []), _ -> em.Emit "ret void"
        | _ when isHandle e.ret ->
            // the result's reference goes to a new handle, the caller's to release
            em.Emit(sprintf "ret ptr %s" (em.Instr(sprintf "call ptr @zs_handle_new(ptr %s, ptr %s)" r (dropFn e.ret))))
        | _, Memory ->
            em.Emit(sprintf "store %s %s, ptr %%ret" (llty e.ret) r)
            em.Emit "ret void"
        | _, Scalar -> em.Emit(sprintf "ret %s %s" (llty e.ret) r)
        | _, Pieces [ p ] -> em.Emit(sprintf "ret %s %s" p (snd (toPieces em e.ret r [ p ]).Head))
        | _, Pieces ps ->
            let agg =
                toPieces em e.ret r ps
                |> List.indexed
                |> List.fold (fun acc (k, (p, v)) -> em.Instr(sprintf "insertvalue %s %s, %s %s, %d" rt acc p v k)) "poison"

            em.Emit(sprintf "ret %s %s" rt agg)

        funcs.Append(sprintf "define %s @%s(%s) {\n%s}\n\n" rt e.cname (String.concat ", " cps) em.Body) |> ignore

    // the header: [<CLayout>] structs, then prototypes
    let rec cName (t: Ty) =
        match prune t with
        | t when isHandle t -> "zs_handle"
        | TCon("ptr", [ p ]) -> (match prune p with TCon("unit", []) -> "void" | p -> cName p) + "*"
        | TCon("cptr", []) -> "void*"
        | TCon("fnptr", [ f ]) -> cFnPtr f ""
        | TCon("int", []) -> "intptr_t"
        | TCon(("i8" | "i16" | "i32" | "i64") as n, []) -> sprintf "int%s_t" (n.Substring 1)
        | TCon(("u8" | "u16" | "u32" | "u64") as n, []) -> sprintf "uint%s_t" (n.Substring 1)
        | TCon("usize", []) -> "size_t"
        | TCon("f64", []) -> "double"
        | TCon("f32", []) -> "float"
        | TCon("bool", []) -> "bool"
        | TCon("cstr", []) -> "const char*"
        | TCon("unit", []) -> "void"
        | TCon(n, []) -> n.Replace('.', '_')
        | t -> failwithf "no C name for %s" (show t)

    /// A C function pointer's declarator: R (*name)(A, B).
    and cFnPtr (f: Ty) (name: string) =
        let rec split t =
            match prune t with
            | TFun(a, r) ->
                let ps, res = split r
                a :: ps, res
            | r -> [], r

        let ps, r = split f
        let ps = ps |> List.filter (fun p -> prune p <> tUnit) |> List.map cName
        sprintf "%s (*%s)(%s)" (cName r) name (if ps.IsEmpty then "void" else String.concat ", " ps)

    /// A C declaration of `name` with this type (a function pointer's name goes inside it).
    let cDecl (t: Ty) (name: string) =
        match prune t with
        | TCon("fnptr", [ f ]) -> cFnPtr f name
        | t -> sprintf "%s %s" (cName t) name

    let header =
        StringBuilder(
            "// Generated by zs. Do not edit.\n#pragma once\n#include <stdbool.h>\n#include <stddef.h>\n#include <stdint.h>\n\n"
            + "// Runs when the library panics, after the message is printed (to log, flush or save state).\n"
            + "// The process stops when it returns. It must not call back into the library.\n"
            + "void zs_set_panic_hook(void (*hook)(const char *message));\n\n"
            + "// A Z# value held by C: an object with its own count. zs_retain adds a reference and\n"
            + "// zs_release gives one up (the last one frees the object). A handle a function returns is\n"
            + "// the caller's to release; one passed to a function is only borrowed for the call.\n"
            + "typedef struct zs_handle_ *zs_handle;\nvoid zs_retain(zs_handle h);\nvoid zs_release(zs_handle h);\n\n"
        )

    for KeyValue(n, info) in types do
        match info.def with
        | RecordDef fs when clayouts.Contains n ->
            let name = n.Replace('.', '_')
            let fields = fs |> List.map (fun (f, ft) -> sprintf "    %s;" (cDecl ft f)) |> String.concat "\n"
            header.Append(sprintf "typedef struct %s {\n%s\n} %s;\n\n" name fields name) |> ignore
        | _ -> ()

    for e in exports do
        let ps = e.pars |> List.mapi (fun i t -> cDecl t (sprintf "p%d" i))
        header.Append(sprintf "%s %s(%s);\n" (cName e.ret) e.cname (if ps.IsEmpty then "void" else String.concat ", " ps)) |> ignore

    if debugInfo then
        compileUnit.Force() |> ignore
        let flags = meta "!{i32 7, !\"Dwarf Version\", i32 5}"
        let version = meta "!{i32 2, !\"Debug Info Version\", i32 3}"
        md.AppendLine(sprintf "!llvm.dbg.cu = !{%s}" compileUnit.Value) |> ignore
        md.AppendLine(sprintf "!llvm.module.flags = !{%s, %s}" flags version) |> ignore

    // the functions of other parts this one calls
    for f in List.ofSeq referenced do
        if not (defined f) && fnTable.ContainsKey f then
            let ps, rt = proto fnTable[f]
            funcs.AppendLine(sprintf "declare %s %s(%s)" rt (sym f) (String.concat ", " ps)) |> ignore

    resolveWord (top.ToString() + "\n" + helpers.ToString() + funcs.ToString() + "\n" + md.ToString()), header.ToString()
