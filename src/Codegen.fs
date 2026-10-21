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
//   union    ptr -> { W rc, i32 tag, field... }; nullary constructors point to a static cell
//   closure  ptr -> { W rc, ptr code, ptr drop, env... }; code: (ptr self, arg) -> result
//   tuples and records: LLVM struct values; so are small non-recursive unions (tag + fields)

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
declare i64 @zs_ticks()
declare void @zs_set_args(i32, ptr)
declare i_W @zs_test_index()
declare void @zs_exit(i_W) noreturn
declare void @llvm.memcpy.p0.p0.i_W(ptr, ptr, i_W, i1)
declare void @zs_panic(ptr) noreturn
declare void @zs_panic_c(ptr) noreturn
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

; a count above 0 is a thread-local object's, 0 a static one's (never freed); below 0 will be a
; shared object's, counted atomically (DESIGN §7.1). The fast paths test for that already
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

define private void @zs.drop.clo(ptr %p) {
entry:
  %last = call i1 @zs.release(ptr %p)
  br i1 %last, label %free, label %done
free:
  %fp = getelementptr { i_W, ptr, ptr }, ptr %p, i32 0, i32 2
  %f = load ptr, ptr %fp
  call void %f(ptr %p)
  ret void
done:
  ret void
}
"""

/// Primitives implemented by runtime functions: C name, result type, parameter types (unit
/// parameters omitted). Arguments are borrowed by the runtime and dropped after the call.
let private runtimePrims =
    dict
        [ "String.sub", ("zs_str_sub", "ptr", [ "ptr"; "i_W"; "i_W" ])
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
        head.Replace("i_W", w).Replace("HDR2", h2).Replace("HDR1", h1) + tail)
    |> String.concat "\n"

/// Compiles closure-converted, RC-annotated functions to textual LLVM IR, plus a C header for
/// the exported functions.
let compile
    (types: Dictionary<string, TypeInfo>)
    (externs: Dictionary<string, ExternSig>)
    (exports: Export list)
    (tests: string list)
    (values: (string * string) list)
    (clayouts: HashSet<string>)
    (funs: MFun list)
    : string * string =
    let top = StringBuilder(prelude)
    let helpers = StringBuilder()
    let funcs = StringBuilder()
    let generated = HashSet<string>()
    let strings = Dictionary<string, string>()
    let fnTable = funs |> List.map (fun f -> f.name, f) |> dict
    let heap t = needsRc types t
    let sym (f: string) = "@\"zs." + f + "\""

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
        | TCon(("cstr" | "cptr" | "string" | "array" | "ref"), _)
        | TFun _ -> "ptr"
        | TCon(n, args) ->
            match types[n].def with
            | RecordDef fs -> structTy (fs |> List.map (fun (_, ft) -> substGen args ft))
            | UnionDef cs when plainUnion types t ->
                // a plain union: the tag, then every case's fields in order (cases don't overlap)
                "{ i32" + (cs |> List.collect snd |> List.map (fun ft -> ", " + llty (substGen args ft)) |> String.concat "") + " }"
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

    let cellTy (fields: Ty list) =
        "{ i_W, i32" + (fields |> List.map (fun f -> ", " + llty f) |> String.concat "") + " }"

    let cloTy (env: Ty list) =
        "{ i_W, ptr, ptr" + (env |> List.map (fun f -> ", " + llty f) |> String.concat "") + " }"

    // ------------------------------------------------------------ C ABI (x86-64 System V, AAPCS64)
    // ponytail: running out of argument registers isn't modelled (x86-64 then passes a struct on
    // the stack whole; AAPCS64 HFAs then need alignstack(8)), which matters only past 6-8 struct args

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

    /// The LLVM parameter types (with attributes) a C parameter of this type becomes.
    let cParams (t: Ty) : string list =
        match prune t with
        | TCon("callback", _) -> [ "ptr"; "ptr" ]
        | TCon("unit", []) -> []
        | _ ->
            match abiOf t with
            | Scalar -> [ cParam t ]
            | Pieces ps -> ps
            | Memory -> [ byval t ]

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
                    if kind = "dup" then dupValue em ft f else dropValue em ft f)

            em.Emit "ret void"
            helpers.Append(sprintf "define private void %s(%s %%v) {\n%s}\n\n" name (llty t) em.Body) |> ignore

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
            let rc = em.Instr "load i_W, ptr %p"
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
            em.Emit(sprintf "call void @llvm.memcpy.p0.p0.i_W(ptr %s, ptr %%p, i_W %s, i1 false)" b bytes)
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
        | TCon("string", _) -> "@zs.drop.str"
        | TTuple _ -> structHelper "drop" t
        | TCon(n, _) when (match types.TryGetValue n with
                           | true, { def = RecordDef _ } -> true
                           | _ -> false) -> structHelper "drop" t
        | pt ->
            let name = sprintf "@\"drop.%s\"" (showFull pt)

            if generated.Add name then
                let em = Emitter()
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
                        em.Emit(sprintf "%s = phi i_W [ 0, %%free ], [ %%next, %%body ]" i)
                        let c = em.Instr(sprintf "icmp slt i_W %s, %s" i len)
                        em.Emit(sprintf "br i1 %s, label %%body, label %%end" c)
                        em.Label "body"
                        let ep = em.Instr(sprintf "getelementptr { i_W, i_W, [0 x %s] }, ptr %%p, i32 0, i32 2, i_W %s" (llty el) i)
                        dropValue em el (em.Instr(sprintf "load %s, ptr %s" (llty el) ep))
                        em.Emit(sprintf "%%next = add i_W %s, 1" i)
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
                | _ ->
                    let _, cases = union pt
                    let tagp = em.Instr "getelementptr { i_W, i32 }, ptr %p, i32 0, i32 1"
                    let tag = em.Instr(sprintf "load i32, ptr %s" tagp)
                    let withRefs = cases |> List.indexed |> List.filter (fun (_, (_, fs)) -> List.exists heap fs)

                    let targets =
                        withRefs |> List.map (fun (i, _) -> sprintf "i32 %d, label %%case%d" i i) |> String.concat " "

                    em.Emit(sprintf "switch i32 %s, label %%plain [ %s ]" tag targets)

                    for i, (_, fs) in withRefs do
                        em.Label(sprintf "case%d" i)
                        let cell = cellTy fs

                        let refs =
                            fs
                            |> List.indexed
                            |> List.filter (snd >> heap)
                            |> List.map (fun (j, ft) ->
                                let fp = em.Instr(sprintf "getelementptr %s, ptr %%p, i32 0, i32 %d" cell (j + 2))
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
        let dp = em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 2" cell c)
        em.Emit(sprintf "store ptr %s, ptr %s" (dropStub f k) dp)

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

    let staticClosure (f: string) =
        let name = sprintf "@\"cloS.%s\"" f

        if generated.Add name then
            top.AppendLine(sprintf "%s = private unnamed_addr constant { i_W, ptr, ptr } { i_W 0, ptr %s, ptr null }" name (stub f 0))
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

    /// The DWARF type of a variable, for the types gdb can show as values.
    let diType (t: Ty) =
        let basic name bits enc =
            match diTypes.TryGetValue name with
            | true, id -> Some id
            | _ ->
                let id = meta (sprintf "!DIBasicType(name: \"%s\", size: %d, encoding: %s)" name bits enc)
                diTypes[name] <- id
                Some id

        match tyName t with
        | "int" -> basic "int" 64 "DW_ATE_signed"
        | ("i8" | "i16" | "i32") as n -> basic n (int (n.Substring 1)) "DW_ATE_signed"
        | ("u8" | "u16" | "u32" | "u64") as n -> basic n (int (n.Substring 1)) "DW_ATE_unsigned"
        | "usize" -> basic "usize" 64 "DW_ATE_unsigned"
        | "f64" -> basic "f64" 64 "DW_ATE_float"
        | "f32" -> basic "f32" 32 "DW_ATE_float"
        | "bool" -> basic "bool" 8 "DW_ATE_boolean"
        | "char" -> basic "char" 32 "DW_ATE_UTF"
        | _ -> None

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
        top.AppendLine(sprintf "%s = internal global %s zeroinitializer" (valueSym v) (llty valueTypes[v])) |> ignore

    let genFun (f: MFun) =
        let em = Emitter()

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
                    em.Raw(sprintf "#dbg_declare(ptr %s, %s, !DIExpression(), %s)" p var loc)
                | _ -> ()
        let selfProto = proto f
        let selfName = f.name

        /// Emits the test of pattern p against v (of type t); returns env extended with its bindings.
        let rec test (p: CPat) (t: Ty) (v: string) failL (env: Map<string, Binding>) =
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
                let fields = snd (List.item tag (snd (union t)))
                guardOr (em.Instr(sprintf "icmp eq i32 %s, %d" (em.Instr(sprintf "extractvalue %s %s, 0" (llty t) v)) tag))

                List.zip ps fields
                |> List.indexed
                |> List.fold
                    (fun env (i, (p, ft)) ->
                        match p with
                        | CPWild -> env
                        | _ -> test p ft (em.Instr(sprintf "extractvalue %s %s, %d" (llty t) v (plainField t tag i))) failL env)
                    env
            | CPCtor(_, tag, ps) ->
                let fields = snd (List.item tag (snd (union t)))
                let tagp = em.Instr(sprintf "getelementptr { i_W, i32 }, ptr %s, i32 0, i32 1" v)
                guardOr (em.Instr(sprintf "icmp eq i32 %s, %d" (em.Instr(sprintf "load i32, ptr %s" tagp)) tag))
                let cell = cellTy fields

                List.zip ps fields
                |> List.indexed
                |> List.fold
                    (fun env (i, (p, ft)) ->
                        match p with
                        | CPWild -> env
                        | _ ->
                            let fp = em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 %d" cell v (i + 2))
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

        /// The array reads of a for loop's body that versioning can prove in bounds: a.[x],
        /// a.[x ± c], a.[c - x], with a and c not assigned in the loop (c a constant or a variable
        /// bound outside it). Returns the read nodes with (array, coefficient of x, c).
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

            let affine (idx: CExpr) =
                match idx.k with
                | CLocal y when y = x -> Some(1, None)
                | CBin("+", { k = CLocal y }, c)
                | CBin("+", c, { k = CLocal y }) when y = x && invariant c -> Some(1, Some c)
                | CBin("-", c, { k = CLocal y }) when y = x && invariant c -> Some(-1, Some c)
                | _ -> None

            let found = ResizeArray<CExpr * (CExpr * int * CExpr option)>()

            let rec walk (e: CExpr) =
                match e.k with
                | CPrim("array.get#b", [ ({ k = CLocal arr } as a); idx ]) when arr <> x && env.ContainsKey arr && not (assigned.Contains arr) ->
                    match affine idx with
                    | Some(coef, c) -> found.Add(e, (a, coef, c))
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

        let lookup (env: Map<string, Binding>) x t =
            match env[x] with
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
            | CDropFields(x, xt, tag, keep, tok, rest) ->
                let v = lookup env x xt
                let fields = snd (List.item tag (snd (union xt)))
                let cell = cellTy fields

                let load i ft =
                    let fp = em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 %d" cell v (i + 2))
                    em.Instr(sprintf "load %s, ptr %s" (llty ft) fp)

                let uniq, shared, join = em.Fresh "unique", em.Fresh "shared", em.Fresh "dropped"
                em.Emit(sprintf "br i1 %s, label %%%s, label %%%s" (em.Instr(sprintf "call i1 @zs.release(ptr %s)" v)) uniq shared)
                em.Label uniq

                fields
                |> List.iteri (fun i ft ->
                    if heap ft && not (keep.Contains i) then
                        dropValue em ft (load i ft))

                if tok.IsNone then
                    em.Emit(sprintf "call void @zs_free(ptr %s)" v)

                em.Emit(sprintf "br label %%%s" join)
                em.Label shared

                fields
                |> List.iteri (fun i ft ->
                    if heap ft && keep.Contains i then
                        dupValue em ft (load i ft))

                em.Emit(sprintf "br label %%%s" join)
                em.Label join

                let env =
                    match tok with
                    | Some t -> env.Add(t, Ssa(em.Instr(sprintf "phi ptr [ %s, %%%s ], [ null, %%%s ]" v uniq shared)))
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
                let cell = cellTy (snd (List.item tag (snd (union e.ty))))
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
                let tp = em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 1" cell c)
                em.Emit(sprintf "store i32 %d, ptr %s" tag tp)

                List.zip args vs
                |> List.iteri (fun i (a, v) ->
                    let fp = em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 %d" cell c (i + 2))
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

                for p, guard, body in cases do
                    em.Label next
                    let failL = em.Fresh "case"
                    let env = test p s.ty v failL env

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
                let withTag = em.Instr(sprintf "insertvalue %s zeroinitializer, i32 %d, 0" lt tag)

                List.zip args vs
                |> List.indexed
                |> List.fold (fun agg (i, (a, v)) -> em.Instr(sprintf "insertvalue %s %s, %s %s, %d" lt agg (llty a.ty) v (plainField e.ty tag i))) withTag
            | CCtor(u, tag, []) ->
                let g = sprintf "@\"ctor.%s.%d\"" u tag

                if generated.Add g then
                    top.AppendLine(sprintf "%s = private unnamed_addr constant { i_W, i32 } { i_W 0, i32 %d }" g tag) |> ignore

                g
            | CCtor(_, tag, args) ->
                let vs = args |> List.map (gen env false)
                let cell = cellTy (snd (List.item tag (snd (union e.ty))))
                let c = em.Instr(sprintf "call ptr @zs_alloc(i_W %s)" (sizeOf em cell))
                em.Emit(sprintf "store i_W 1, ptr %s" c)
                let tp = em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 1" cell c)
                em.Emit(sprintf "store i32 %d, ptr %s" tag tp)

                List.zip args vs
                |> List.iteri (fun i (a, v) ->
                    let fp = em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 %d" cell c (i + 2))
                    em.Emit(sprintf "store %s %s, ptr %s" (llty a.ty) v fp))

                c
            | CBin(op, a, b) ->
                let va = gen env false a
                let vb = gen env false b
                let t = a.ty
                let lt = llty t
                // a [<Wrapping>] function's + - *: wrapping on integers, the usual ones otherwise
                let op = if op.StartsWith "wrap" && not (ints.Contains(tyName t)) then op.Substring 4 else op

                match tyName t with
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
                        em.Instr(sprintf "%s %s %s, %s" (farith[op]) lt va vb)
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

                if isFloat a.ty then
                    em.Instr(sprintf "fneg %s %s" (llty a.ty) va)
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
            | CExtern(name, args) ->
                let s = externs[name]
                let vs = args |> List.map (gen env false)

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
                            | _ ->
                                match abiOf pt with
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

                let ret, sret = cRet s.ret
                let retSlot = if sret then Some(slotFor em s.ret) else None
                let argv = (retSlot |> Option.map (fun p -> sprintf "ptr sret(%s) %s" (llty s.ret) p) |> Option.toList) @ argv |> String.concat ", "

                let fnTy =
                    if s.variadic then
                        sprintf "%s (%s)" ret ((s.pars |> List.collect cParams) @ [ "..." ] |> String.concat ", ")
                    else
                        ret

                let call = sprintf "call %s @%s(%s)" fnTy name argv

                let r =
                    if ret = "void" then
                        em.Emit call

                        match retSlot with
                        | Some p -> em.Instr(sprintf "load %s, ptr %s" (llty s.ret) p)
                        | None -> "zeroinitializer"
                    else
                        let c = em.Instr call

                        match abiFor s.ret true with
                        | Scalar -> c
                        | Pieces [ p ] -> fromPieces em s.ret [ p, c ]
                        | Pieces ps -> fromPieces em s.ret (ps |> List.mapi (fun k p -> p, em.Instr(sprintf "extractvalue %s %s, %d" ret c k)))
                        | Memory -> failwith "unreachable"

                for a, v in List.zip args vs do
                    match tyName a.ty, prune a.ty with
                    | "string", _
                    | _, TFun _ -> dropValue em a.ty v // the string's bytes / the callback's closure were borrowed
                    | _ -> ()

                r
            | CMkClosure(f, []) -> staticClosure f
            | CMkClosure(f, args) ->
                let vs = args |> List.map (gen env false)
                allocClosure em f (List.zip (args |> List.map (fun a -> a.ty)) vs)
            | CApplyClo(c, a) ->
                let vc = gen env false c
                let va = gen env false a
                let cp = em.Instr(sprintf "getelementptr { i_W, ptr }, ptr %s, i32 0, i32 1" vc)
                let code = em.Instr(sprintf "load ptr, ptr %s" cp)
                em.Instr(sprintf "call %s %s(ptr %s, %s %s)" (llty e.ty) code vc (llty a.ty) va)
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
            | CFor(x, a, { k = CInt 1L }, b, body) when not (versioning.Contains e) && not (versionedReads env x body).IsEmpty ->
                // loop versioning: if every a.[x ± c] the loop reads is in bounds for the whole
                // range, run a copy of the loop without those bounds checks; otherwise the checked one
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
                        (fun ok (arr: CExpr, coef, c) ->
                            let cv = match c with Some c -> value c | None -> "0"
                            let lo, hi, bad =
                                if coef > 0 then
                                    let lo, bad = ovf "add" va cv "false"
                                    let hi, bad = ovf "add" vb cv bad
                                    lo, hi, bad
                                else
                                    let lo, bad = ovf "sub" cv vb "false"
                                    let hi, bad = ovf "sub" cv va bad
                                    lo, hi, bad

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
                let real = List.zip args vs |> List.filter (fun (a, _) -> prune a.ty <> tUnit)
                let argv = List.zip pts real |> List.map (fun (pt, (_, v)) -> pt + " " + v) |> String.concat ", "
                let call = sprintf "call %s @%s(%s)" ret fn argv

                let r =
                    if ret = "void" then
                        em.Emit call
                        "zeroinitializer"
                    else
                        em.Instr call

                for k, (a, v) in List.indexed real do
                    if not (borrowed0 && k = 0) then
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

        funcs.Append(sprintf "define internal %s %s(%s)%s%s {\n%s}\n\n" rt (sym f.name) ps hint dbg em.Body) |> ignore

    for KeyValue(name, s) in externs do
        let ret, sret = cRet s.ret
        let sretP = if sret then [ sprintf "ptr sret(%s)" (llty s.ret) ] else []
        let ps = sretP @ (s.pars |> List.collect cParams) @ (if s.variadic then [ "..." ] else [])
        top.AppendLine(sprintf "declare %s @%s(%s)" ret name (String.concat ", " ps)) |> ignore

    for f in funs do
        genFun f

    /// Runs the initializers in order, storing each value (main's prologue).
    let initValues () =
        values
        |> List.mapi (fun i (v, init) ->
            let t = llty valueTypes[v]
            sprintf "  %%iv%d = call %s %s()\n  store %s %%iv%d, ptr %s\n" i t (sym init) t i (valueSym v))
        |> String.concat ""

    // the values, released in reverse order after main returns (so the leak check stays exact)
    do
        let em = Emitter()

        for v, _ in List.rev values do
            let t = valueTypes[v]

            if heap t then
                dropValue em t (em.Instr(sprintf "load %s, ptr %s" (llty t) (valueSym v)))

        em.Emit "ret void"
        funcs.Append(sprintf "define private void @zsv.dropAll() {\n%s}\n\n" em.Body) |> ignore

    // C entry points: main (an int result becomes the exit code) and [<Export>] wrappers
    if fnTable.ContainsKey "main" then
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
    if not tests.IsEmpty && not (fnTable.ContainsKey "main") then
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

    for e in exports do
        let fd = fnTable[e.fname]
        let em = Emitter()
        let rt, sret = cRet e.ret
        let cps = ResizeArray<string>()

        if sret then
            cps.Add(sprintf "ptr sret(%s) align 8 %%ret" (llty e.ret))

        let args =
            fd.pars
            |> List.mapi (fun i (_, t) ->
                let n = sprintf "%%a%d" i

                match prune t with
                | TCon("unit", []) -> t, "zeroinitializer"
                | _ ->
                    match abiOf t with
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

    let header =
        StringBuilder(
            "// Generated by zs. Do not edit.\n#pragma once\n#include <stdbool.h>\n#include <stddef.h>\n#include <stdint.h>\n\n"
            + "// Runs when the library panics, after the message is printed (to log, flush or save state).\n"
            + "// The process stops when it returns. It must not call back into the library.\n"
            + "void zs_set_panic_hook(void (*hook)(const char *message));\n\n"
        )

    for KeyValue(n, info) in types do
        match info.def with
        | RecordDef fs when clayouts.Contains n ->
            let name = n.Replace('.', '_')
            let fields = fs |> List.map (fun (f, ft) -> sprintf "    %s %s;" (cName ft) f) |> String.concat "\n"
            header.Append(sprintf "typedef struct %s {\n%s\n} %s;\n\n" name fields name) |> ignore
        | _ -> ()

    for e in exports do
        let ps = e.pars |> List.mapi (fun i t -> sprintf "%s p%d" (cName t) i)
        header.Append(sprintf "%s %s(%s);\n" (cName e.ret) e.cname (if ps.IsEmpty then "void" else String.concat ", " ps)) |> ignore

    if debugInfo then
        compileUnit.Force() |> ignore
        let flags = meta "!{i32 7, !\"Dwarf Version\", i32 5}"
        let version = meta "!{i32 2, !\"Debug Info Version\", i32 3}"
        md.AppendLine(sprintf "!llvm.dbg.cu = !{%s}" compileUnit.Value) |> ignore
        md.AppendLine(sprintf "!llvm.module.flags = !{%s, %s}" flags version) |> ignore

    resolveWord (top.ToString() + "\n" + helpers.ToString() + funcs.ToString() + "\n" + md.ToString()), header.ToString()
