module Codegen

open System
open System.Collections.Generic
open System.Text
open Syntax
open Core
open Mono

// Representation (every heap object starts with an i64 reference count; 0 = static, never freed):
//   int/i64/u64/usize i64, i32/u32 i32, i16/u16 i16, i8/u8 i8, f64 double, f32 float, bool i1,
//   unit {} (value: zeroinitializer), cstr ptr
//   string   ptr -> { i64 rc, i64 len, [len+1 x i8] }
//   array<T> ptr -> { i64 rc, i64 len, [len x T] }
//   ref<T>   ptr -> { i64 rc, T }
//   union    ptr -> { i64 rc, i32 tag, field... }; nullary constructors point to a static cell
//   closure  ptr -> { i64 rc, ptr code, ptr drop, env... }; code: (ptr self, arg) -> result
//   tuples and records: LLVM struct values
// ponytail: every union is boxed; keep small non-recursive ones inline when perf matters

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
    member _.Emit(s: string) = sb.Append("  ").AppendLine(s) |> ignore

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
    """declare ptr @zs_alloc(i64)
declare void @zs_free(ptr)
declare void @zs_panic(ptr) noreturn
declare void @zs_panic_c(ptr) noreturn
declare ptr @zs_str_concat(ptr, ptr)
declare i64 @zs_str_cmp(ptr, ptr)
declare i64 @zs_str_hash(ptr)
declare ptr @zs_str_of_i64(i64)
declare ptr @zs_str_of_u64(i64)
declare ptr @zs_str_of_f64(double)
declare ptr @zs_str_of_bool(i1 zeroext)
declare void @zs_print(ptr)
declare void @zs_println(ptr)
declare ptr @zs_str_from_c(ptr)
declare ptr @zs_str_sub(ptr, i64, i64)
declare zeroext i8 @zs_str_byte(ptr, i64)
declare ptr @zs_str_of_byte(i8 zeroext)
declare i64 @zs_str_index_of(ptr, ptr, i64)
declare ptr @zs_str_trim(ptr)
declare ptr @zs_str_upper(ptr)
declare ptr @zs_str_lower(ptr)
declare ptr @zs_str_replace(ptr, ptr, ptr)
declare zeroext i1 @zs_str_is_float(ptr)
declare double @zs_str_to_float(ptr)
declare ptr @zs_read_line()
declare zeroext i1 @zs_eof()
declare void @zs_eprintln(ptr)

define private void @zs.dup(ptr %p) alwaysinline {
entry:
  %rc = load i64, ptr %p
  %static = icmp eq i64 %rc, 0
  br i1 %static, label %done, label %inc
inc:
  %n = add i64 %rc, 1
  store i64 %n, ptr %p
  br label %done
done:
  ret void
}

; true when this was the last reference (the caller frees the object)
define private i1 @zs.release(ptr %p) alwaysinline {
entry:
  %rc = load i64, ptr %p
  %last = icmp eq i64 %rc, 1
  br i1 %last, label %yes, label %no
yes:
  ret i1 true
no:
  %static = icmp eq i64 %rc, 0
  br i1 %static, label %keep, label %dec
dec:
  %n = sub i64 %rc, 1
  store i64 %n, ptr %p
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
  %fp = getelementptr { i64, ptr, ptr }, ptr %p, i32 0, i32 2
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
        [ "String.sub", ("zs_str_sub", "ptr", [ "ptr"; "i64"; "i64" ])
          "String.byte", ("zs_str_byte", "zeroext i8", [ "ptr"; "i64" ])
          "String.ofByte", ("zs_str_of_byte", "ptr", [ "i8 zeroext" ])
          "String.indexOfFrom", ("zs_str_index_of", "i64", [ "ptr"; "ptr"; "i64" ])
          "String.trim", ("zs_str_trim", "ptr", [ "ptr" ])
          "String.toUpper", ("zs_str_upper", "ptr", [ "ptr" ])
          "String.toLower", ("zs_str_lower", "ptr", [ "ptr" ])
          "String.replace", ("zs_str_replace", "ptr", [ "ptr"; "ptr"; "ptr" ])
          "String.isFloat", ("zs_str_is_float", "zeroext i1", [ "ptr" ])
          "String.toFloat", ("zs_str_to_float", "double", [ "ptr" ])
          "Console.readLineRaw", ("zs_read_line", "ptr", [])
          "Console.eof", ("zs_eof", "zeroext i1", [])
          "eprintln", ("zs_eprintln", "void", [ "ptr" ]) ]

let private floatConst (ty: string) (f: float) =
    let v = if ty = "float" then float (float32 f) else f
    sprintf "0x%016X" (BitConverter.DoubleToInt64Bits v)

/// Compiles closure-converted, RC-annotated functions to textual LLVM IR, plus a C header for
/// the exported functions.
let compile
    (types: Dictionary<string, TypeInfo>)
    (externs: Dictionary<string, ExternSig>)
    (exports: Export list)
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
        | TCon(("int" | "u64" | "usize"), []) -> "i64"
        | TCon(("i32" | "u32"), []) -> "i32"
        | TCon(("i16" | "u16"), []) -> "i16"
        | TCon(("i8" | "u8"), []) -> "i8"
        | TCon("f64", []) -> "double"
        | TCon("f32", []) -> "float"
        | TCon("bool", []) -> "i1"
        | TCon("unit", []) -> "{}"
        | TCon(("cstr" | "string" | "array" | "ref"), _)
        | TFun _ -> "ptr"
        | TCon(n, args) ->
            match types[n].def with
            | RecordDef fs -> structTy (fs |> List.map (fun (_, ft) -> substGen args ft))
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

    let cellTy (fields: Ty list) =
        "{ i64, i32" + (fields |> List.map (fun f -> ", " + llty f) |> String.concat "") + " }"

    let cloTy (env: Ty list) =
        "{ i64, ptr, ptr" + (env |> List.map (fun f -> ", " + llty f) |> String.concat "") + " }"

    // ------------------------------------------------------------ C ABI (x86-64 System V)
    // ponytail: x86-64 System V only, and running out of argument registers (a struct then goes
    // to the stack whole) isn't modelled; aarch64 AAPCS comes with cross-compilation (Phase 4)

    /// Size, alignment and scalar fields (offset, LLVM type) of a C-representable type.
    let rec cLayout (t: Ty) : int * int * (int * string) list =
        match llty t with
        | "i1"
        | "i8" -> 1, 1, [ 0, "i8" ]
        | "i16" -> 2, 2, [ 0, "i16" ]
        | "i32" -> 4, 4, [ 0, "i32" ]
        | "float" -> 4, 4, [ 0, "float" ]
        | "i64"
        | "ptr"
        | "double" as lt -> 8, 8, [ 0, lt ]
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

    let abiOf (t: Ty) : Abi =
        match llty t with
        | lt when not (lt.StartsWith "{") -> Scalar
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

    let cParam (t: Ty) = if llty t = "i1" then "i1 zeroext" else llty t

    let byval (t: Ty) =
        let _, a, _ = cLayout t
        sprintf "ptr byval(%s) align %d" (llty t) a

    /// LLVM return type for a C result, and whether it is returned through an sret pointer.
    let cRet (t: Ty) : string * bool =
        match prune t with
        | TCon("unit", []) -> "void", false
        | _ ->
            match abiOf t with
            | Scalar -> (if llty t = "i1" then "zeroext i1" else llty t), false
            | Pieces [ p ] -> p, false
            | Pieces ps -> "{ " + String.concat ", " ps + " }", false
            | Memory -> "void", true

    /// A struct in memory, read or written as its eightbytes.
    let slotFor (em: Emitter) (t: Ty) =
        let slot = "%" + em.Fresh "abi"
        em.Alloca(sprintf "%s = alloca %s, align 8" slot (llty t))
        slot

    let toPieces (em: Emitter) (t: Ty) (v: string) (pieces: string list) =
        let slot = slotFor em t
        em.Emit(sprintf "store %s %s, ptr %s" (llty t) v slot)

        pieces
        |> List.mapi (fun k pt ->
            let p = em.Instr(sprintf "getelementptr i8, ptr %s, i64 %d" slot (8 * k))
            pt, em.Instr(sprintf "load %s, ptr %s" pt p))

    let fromPieces (em: Emitter) (t: Ty) (pieces: (string * string) list) =
        let slot = slotFor em t

        pieces
        |> List.iteri (fun k (pt, pv) ->
            let p = em.Instr(sprintf "getelementptr i8, ptr %s, i64 %d" slot (8 * k))
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
        em.Instr(sprintf "ptrtoint ptr %s to i64" p)

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
                    "%s = private unnamed_addr constant { i64, i64, [%d x i8] } { i64 0, i64 %d, [%d x i8] c\"%s\\00\" }"
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
            "getelementptr inbounds ({ i64, i64, [%d x i8] }, ptr %s, i32 0, i32 2)"
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
        let name = sprintf "@\"%s.%s\"" kind (show t)

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

    and dropFn (t: Ty) : string =
        match prune t with
        | TFun _ -> "@zs.drop.clo"
        | TCon("string", _) -> "@zs.drop.str"
        | TTuple _ -> structHelper "drop" t
        | TCon(n, _) when (match types.TryGetValue n with
                           | true, { def = RecordDef _ } -> true
                           | _ -> false) -> structHelper "drop" t
        | pt ->
            let name = sprintf "@\"drop.%s\"" (show pt)

            if generated.Add name then
                let em = Emitter()
                let last = em.Instr "call i1 @zs.release(ptr %p)"
                em.Emit(sprintf "br i1 %s, label %%free, label %%done" last)
                em.Label "free"

                match pt with
                | TCon("array", [ el ]) ->
                    if heap el then
                        let lenp = em.Instr "getelementptr { i64, i64 }, ptr %p, i32 0, i32 1"
                        let len = em.Instr(sprintf "load i64, ptr %s" lenp)
                        em.Emit "br label %loop"
                        em.Label "loop"
                        let i = em.Tmp()
                        em.Emit(sprintf "%s = phi i64 [ 0, %%free ], [ %%next, %%body ]" i)
                        let c = em.Instr(sprintf "icmp slt i64 %s, %s" i len)
                        em.Emit(sprintf "br i1 %s, label %%body, label %%end" c)
                        em.Label "body"
                        let ep = em.Instr(sprintf "getelementptr { i64, i64, [0 x %s] }, ptr %%p, i32 0, i32 2, i64 %s" (llty el) i)
                        dropValue em el (em.Instr(sprintf "load %s, ptr %s" (llty el) ep))
                        em.Emit(sprintf "%%next = add i64 %s, 1" i)
                        em.Emit "br label %loop"
                        em.Label "end"

                    em.Emit "call void @zs_free(ptr %p)"
                    em.Emit "ret void"
                | TCon("ref", [ v ]) ->
                    let vp = em.Instr(sprintf "getelementptr { i64, %s }, ptr %%p, i32 0, i32 1" (llty v))
                    let x = em.Instr(sprintf "load %s, ptr %s" (llty v) vp)
                    em.Emit "call void @zs_free(ptr %p)"
                    dropValue em v x
                    em.Emit "ret void"
                | _ ->
                    let _, cases = union pt
                    let tagp = em.Instr "getelementptr { i64, i32 }, ptr %p, i32 0, i32 1"
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
        let c = em.Instr(sprintf "call ptr @zs_alloc(i64 %s)" (sizeOf em cell))
        em.Emit(sprintf "store i64 1, ptr %s" c)
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
            top.AppendLine(sprintf "%s = private unnamed_addr constant { i64, ptr, ptr } { i64 0, ptr %s, ptr null }" name (stub f 0))
            |> ignore

        name

    /// C entry point for a callback<A -> R>: R thunk(void* user, A) calls the closure `user`.
    let thunk (f: Ty) : string =
        let a, r =
            match prune f with
            | TFun(a, r) -> a, r
            | _ -> failwith "callback type"

        let name = sprintf "@\"cb.%s\"" (show f)

        if generated.Add name then
            let em = Emitter()
            let unitArg = prune a = tUnit
            let cp = em.Instr "getelementptr { i64, ptr }, ptr %user, i32 0, i32 1"
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

    let genFun (f: MFun) =
        let em = Emitter()
        let selfProto = proto f

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
            | CPCtor(_, tag, ps) ->
                let fields = snd (List.item tag (snd (union t)))
                let tagp = em.Instr(sprintf "getelementptr { i64, i32 }, ptr %s, i32 0, i32 1" v)
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

        let lookup (env: Map<string, Binding>) x t =
            match env[x] with
            | Ssa v -> v
            | Slot p -> em.Instr(sprintf "load %s, ptr %s" (llty t) p)

        let rec gen (env: Map<string, Binding>) (tail: bool) (e: CExpr) : string =
            match e.k with
            | CLine(ln, e) ->
                try
                    gen env tail e
                with CompileError(0, msg) ->
                    fail ln msg
            | CInt k -> if isFloat e.ty then floatConst (llty e.ty) (float k) else string k
            | CFloat x -> floatConst (llty e.ty) x
            | CBool b -> if b then "true" else "false"
            | CUnit -> "zeroinitializer"
            | CStr s -> if tyName e.ty = "cstr" then cstrConst s else strGlobal s
            | CLocal x -> lookup env x e.ty
            | CLet(x, v, body) ->
                let vv = gen env false v
                gen (env.Add(x, Ssa vv)) tail body
            | CLetMut(x, v, body) ->
                let vv = gen env false v
                let slot = "%slot." + x
                em.Alloca(sprintf "%s = alloca %s" slot (llty v.ty))
                em.Emit(sprintf "store %s %s, ptr %s" (llty v.ty) vv slot)
                let needsDrop = heap v.ty
                let r = gen (env.Add(x, Slot slot)) (tail && not needsDrop) body

                if needsDrop then
                    dropValue em v.ty (em.Instr(sprintf "load %s, ptr %s" (llty v.ty) slot))

                r
            | CAssign(x, v) ->
                let vv = gen env false v

                match env[x] with
                | Slot p ->
                    let old = if heap v.ty then Some(em.Instr(sprintf "load %s, ptr %s" (llty v.ty) p)) else None
                    em.Emit(sprintf "store %s %s, ptr %s" (llty v.ty) vv p)
                    old |> Option.iter (dropValue em v.ty)
                    "zeroinitializer"
                | Ssa _ -> failwith "assignment to an immutable variable"
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
                let a = em.Instr(sprintf "call ptr @zs_alloc(i64 %s)" (sizeOf em cell))
                let fromAlloc = em.Block
                em.Emit(sprintf "br label %%%s" join)
                em.Label reuse
                em.Emit(sprintf "br label %%%s" join)
                em.Label join
                let c = em.Instr(sprintf "phi ptr [ %s, %%%s ], [ %s, %%%s ]" a fromAlloc t reuse)
                em.Emit(sprintf "store i64 1, ptr %s" c)
                let tp = em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 1" cell c)
                em.Emit(sprintf "store i32 %d, ptr %s" tag tp)

                List.zip args vs
                |> List.iteri (fun i (a, v) ->
                    let fp = em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 %d" cell c (i + 2))
                    em.Emit(sprintf "store %s %s, ptr %s" (llty a.ty) v fp))

                c
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
                // ponytail: clauses are tested one after another; decision trees when match speed matters
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
            | CCtor(u, tag, []) ->
                let g = sprintf "@\"ctor.%s.%d\"" u tag

                if generated.Add g then
                    top.AppendLine(sprintf "%s = private unnamed_addr constant { i64, i32 } { i64 0, i32 %d }" g tag) |> ignore

                g
            | CCtor(_, tag, args) ->
                let vs = args |> List.map (gen env false)
                let cell = cellTy (snd (List.item tag (snd (union e.ty))))
                let c = em.Instr(sprintf "call ptr @zs_alloc(i64 %s)" (sizeOf em cell))
                em.Emit(sprintf "store i64 1, ptr %s" c)
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

                match tyName t with
                | "string" ->
                    let r =
                        if op = "+" then
                            em.Instr(sprintf "call ptr @zs_str_concat(ptr %s, ptr %s)" va vb)
                        else
                            let c = em.Instr(sprintf "call i64 @zs_str_cmp(ptr %s, ptr %s)" va vb)
                            em.Instr(sprintf "icmp %s i64 %s, 0" (icmpS[op]) c)

                    dropValue em t va
                    dropValue em t vb
                    r
                | "unit" -> if op = "=" then "true" else "false"
                | _ when isFloat t ->
                    if farith.ContainsKey op then
                        em.Instr(sprintf "%s %s %s, %s" (farith[op]) lt va vb)
                    else
                        em.Instr(sprintf "fcmp %s %s %s, %s" (fcmp[op]) lt va vb)
                | _ when arith.ContainsKey op -> em.Instr(sprintf "%s %s %s, %s" (arith[op]) lt va vb)
                | _ when op = "/" || op = "%" ->
                    check em (em.Instr(sprintf "icmp ne %s %s, 0" lt vb)) "division by zero"
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
                    em.Instr(sprintf "sub %s 0, %s" (llty a.ty) va)
            | CNot a -> em.Instr(sprintf "xor i1 %s, true" (gen env false a))
            | CCallDirect(f, args) ->
                let fd = fnTable[f]
                let vs = args |> List.map (gen env false)
                let argv = List.zip args vs |> List.map (fun (a, v) -> sprintf "%s %s" (llty a.ty) v) |> String.concat ", "
                let rt = llty fd.ret

                if tail && proto fd = selfProto then
                    let r = em.Instr(sprintf "musttail call %s %s(%s)" rt (sym f) argv)
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
                        | "string" -> "ptr " + em.Instr(sprintf "getelementptr inbounds i8, ptr %s, i64 16" v)
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

                        match abiOf s.ret with
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
                let cp = em.Instr(sprintf "getelementptr { i64, ptr }, ptr %s, i32 0, i32 1" vc)
                let code = em.Instr(sprintf "load ptr, ptr %s" cp)
                em.Instr(sprintf "call %s %s(ptr %s, %s %s)" (llty e.ty) code vc (llty a.ty) va)
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
                let slot = "%slot." + x
                em.Alloca(sprintf "%s = alloca %s" slot lt)
                em.Emit(sprintf "store %s %s, ptr %s" lt va slot)
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
            | CPrim(op, args) -> prim env op args e.ty
            | CGlobal _
            | CApp _
            | CLam _
            | CLetFun _ -> failwithf "Codegen: unexpected node %A" e.k

        and prim env op (args: CExpr list) (ty: Ty) : string =
            let vs = args |> List.map (gen env false)
            let arg i = List.item i vs
            let argTy i = (List.item i args).ty

            let arrTy (t: Ty) =
                match prune t with
                | TCon("array", [ el ]) -> el, sprintf "{ i64, i64, [0 x %s] }" (llty el)
                | _ -> failwith "not an array"

            let elemPtr a i =
                let el, at = arrTy (argTy 0)
                el, em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 2, i64 %s" at a i)

            let bounds a i =
                let lenp = em.Instr(sprintf "getelementptr { i64, i64 }, ptr %s, i32 0, i32 1" a)
                let len = em.Instr(sprintf "load i64, ptr %s" lenp)
                check em (em.Instr(sprintf "icmp ult i64 %s, %s" i len)) "index out of bounds"

            let newArray (el: Ty) (n: string) =
                let es = sizeOf em (llty el)
                let bytes = em.Instr(sprintf "add i64 16, %s" (em.Instr(sprintf "mul i64 %s, %s" n es)))
                let a = em.Instr(sprintf "call ptr @zs_alloc(i64 %s)" bytes)
                em.Emit(sprintf "store i64 1, ptr %s" a)
                let lenp = em.Instr(sprintf "getelementptr { i64, i64 }, ptr %s, i32 0, i32 1" a)
                em.Emit(sprintf "store i64 %s, ptr %s" n lenp)
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
                | "f64" -> em.Instr(sprintf "call ptr @zs_str_of_f64(double %s)" (arg 0))
                | "f32" -> em.Instr(sprintf "call ptr @zs_str_of_f64(double %s)" (em.Instr(sprintf "fpext float %s to double" (arg 0))))
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
                    let c = em.Instr(sprintf "call i64 @zs_str_cmp(ptr %s, ptr %s)" (arg 0) (arg 1))
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

                    let a = em.Instr(sprintf "zext i1 %s to i64" gt)
                    let b = em.Instr(sprintf "zext i1 %s to i64" lt')
                    em.Instr(sprintf "sub i64 %s, %s" a b)
            | "hash" ->
                let t = argTy 0
                let lt = llty t

                match tyName t with
                | "string" ->
                    let h = em.Instr(sprintf "call i64 @zs_str_hash(ptr %s)" (arg 0))
                    dropValue em t (arg 0)
                    h
                | "f64" -> em.Instr(sprintf "bitcast double %s to i64" (arg 0))
                | "f32" -> em.Instr(sprintf "zext i32 %s to i64" (em.Instr(sprintf "bitcast float %s to i32" (arg 0))))
                | _ when lt = "i64" -> arg 0
                | _ -> em.Instr(sprintf "%s %s %s to i64" (if isUnsigned t || lt = "i1" then "zext" else "sext") lt (arg 0))
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

                for a, v in real do
                    dropValue em a.ty v

                r
            | "String.length" ->
                let lp = em.Instr(sprintf "getelementptr i8, ptr %s, i64 8" (arg 0))
                let n = em.Instr(sprintf "load i64, ptr %s" lp)
                dropValue em (argTy 0) (arg 0)
                n
            | "ref" ->
                let cell = sprintf "{ i64, %s }" (llty (argTy 0))
                let r = em.Instr(sprintf "call ptr @zs_alloc(i64 %s)" (sizeOf em cell))
                em.Emit(sprintf "store i64 1, ptr %s" r)
                let vp = em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 1" cell r)
                em.Emit(sprintf "store %s %s, ptr %s" (llty (argTy 0)) (arg 0) vp)
                r
            | "ref.get" ->
                let vp = em.Instr(sprintf "getelementptr { i64, %s }, ptr %s, i32 0, i32 1" (llty ty) (arg 0))
                let v = em.Instr(sprintf "load %s, ptr %s" (llty ty) vp)
                dupValue em ty v
                dropValue em (argTy 0) (arg 0)
                v
            | "ref.set" ->
                let vt = argTy 1
                let vp = em.Instr(sprintf "getelementptr { i64, %s }, ptr %s, i32 0, i32 1" (llty vt) (arg 0))
                let old = em.Instr(sprintf "load %s, ptr %s" (llty vt) vp)
                em.Emit(sprintf "store %s %s, ptr %s" (llty vt) (arg 1) vp)
                dropValue em vt old
                dropValue em (argTy 0) (arg 0)
                "zeroinitializer"
            | "Array.length" ->
                let lp = em.Instr(sprintf "getelementptr { i64, i64 }, ptr %s, i32 0, i32 1" (arg 0))
                let n = em.Instr(sprintf "load i64, ptr %s" lp)
                dropValue em (argTy 0) (arg 0)
                n
            | "Array.create" ->
                let el = argTy 1
                let n = arg 0
                check em (em.Instr(sprintf "icmp sge i64 %s, 0" n)) "negative array size"
                let a = newArray el n
                let at = sprintf "{ i64, i64, [0 x %s] }" (llty el)
                let slot = "%" + em.Fresh "fill"
                em.Alloca(sprintf "%s = alloca i64" slot)
                em.Emit(sprintf "store i64 0, ptr %s" slot)
                let lc, lb, lend = em.Fresh "acond", em.Fresh "abody", em.Fresh "aend"
                em.Emit(sprintf "br label %%%s" lc)
                em.Label lc
                let i = em.Instr(sprintf "load i64, ptr %s" slot)
                em.Emit(sprintf "br i1 %s, label %%%s, label %%%s" (em.Instr(sprintf "icmp slt i64 %s, %s" i n)) lb lend)
                em.Label lb
                let ep = em.Instr(sprintf "getelementptr %s, ptr %s, i32 0, i32 2, i64 %s" at a i)
                em.Emit(sprintf "store %s %s, ptr %s" (llty el) (arg 1) ep)
                dupValue em el (arg 1)
                em.Emit(sprintf "store i64 %s, ptr %s" (em.Instr(sprintf "add i64 %s, 1" i)) slot)
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
                    let ep = em.Instr(sprintf "getelementptr { i64, i64, [0 x %s] }, ptr %s, i32 0, i32 2, i64 %d" (llty el) a i)
                    em.Emit(sprintf "store %s %s, ptr %s" (llty el) v ep))

                a
            | "array.get" ->
                bounds (arg 0) (arg 1)
                let el, ep = elemPtr (arg 0) (arg 1)
                let v = em.Instr(sprintf "load %s, ptr %s" (llty el) ep)
                dupValue em el v
                dropValue em (argTy 0) (arg 0)
                v
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
        let v = gen env true f.body
        let rt = llty f.ret
        em.Emit(sprintf "ret %s %s" rt v)
        let ps = f.pars |> List.map (fun (x, t) -> sprintf "%s %%p.%s" (llty t) x) |> String.concat ", "
        funcs.Append(sprintf "define internal %s %s(%s) {\n%s}\n\n" rt (sym f.name) ps em.Body) |> ignore

    for KeyValue(name, s) in externs do
        let ret, sret = cRet s.ret
        let sretP = if sret then [ sprintf "ptr sret(%s)" (llty s.ret) ] else []
        let ps = sretP @ (s.pars |> List.collect cParams) @ (if s.variadic then [ "..." ] else [])
        top.AppendLine(sprintf "declare %s @%s(%s)" ret name (String.concat ", " ps)) |> ignore

    for f in funs do
        genFun f

    // C entry points: main (an int result becomes the exit code) and [<Export>] wrappers
    if fnTable.ContainsKey "main" then
        let main = fnTable["main"]
        let rt = llty main.ret

        let body =
            match tyName main.ret with
            | "unit" -> sprintf "  call {} %s({} zeroinitializer)\n  ret i32 0" (sym "main")
            | "i32" -> sprintf "  %%r = call i32 %s({} zeroinitializer)\n  ret i32 %%r" (sym "main")
            | _ -> sprintf "  %%r = call %s %s({} zeroinitializer)\n  %%c = trunc %s %%r to i32\n  ret i32 %%c" rt (sym "main") rt

        funcs.AppendLine("define i32 @main() {").AppendLine(body).AppendLine("}") |> ignore

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

        match prune e.ret, abiOf e.ret with
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
        | TCon("int", []) -> "int64_t"
        | TCon(("i8" | "i16" | "i32") as n, []) -> sprintf "int%s_t" (n.Substring 1)
        | TCon(("u8" | "u16" | "u32" | "u64") as n, []) -> sprintf "uint%s_t" (n.Substring 1)
        | TCon("usize", []) -> "size_t"
        | TCon("f64", []) -> "double"
        | TCon("f32", []) -> "float"
        | TCon("bool", []) -> "bool"
        | TCon("cstr", []) -> "const char*"
        | TCon("unit", []) -> "void"
        | TCon(n, []) -> n.Replace('.', '_')
        | t -> failwithf "no C name for %s" (show t)

    let header = StringBuilder("// Generated by zs. Do not edit.\n#pragma once\n#include <stdbool.h>\n#include <stddef.h>\n#include <stdint.h>\n\n")

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

    top.ToString() + "\n" + helpers.ToString() + funcs.ToString(), header.ToString()
