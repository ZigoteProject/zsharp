module Codegen

open System.Collections.Generic
open System.Text
open Syntax
open Typer

let private arith =
    dict [ "+", "add"; "-", "sub"; "*", "mul"; "/", "sdiv"; "%", "srem" ]

let private cmp =
    dict [ "=", "eq"; "<>", "ne"; "<", "slt"; ">", "sgt"; "<=", "sle"; ">=", "sge" ]

// Representation:
//   int i64, c_int i32, bool i1, cstr ptr, unit {} (value: zeroinitializer)
//   tuples and records: LLVM struct values
//   unions: ptr to a heap cell { i32 tag, field... }; nullary constructors point to a constant
// ponytail: every union is boxed; keep small non-recursive ones inline when perf matters
/// Compiles a type-checked program to textual LLVM IR.
let compile (prog: Program) : string =
    let globals = StringBuilder()
    let funcs = StringBuilder()
    let ctorGlobals = HashSet<string>()
    let strCount = ref 0

    globals.AppendLine("declare ptr @malloc(i64)").AppendLine("declare void @llvm.trap()") |> ignore

    let union u =
        match prog.types[u] with
        | UnionDef cs -> cs
        | RecordDef _ -> failwith "not a union"

    let rec llty (t: Ty) =
        match resolve t with
        | TCon "int" -> "i64"
        | TCon "c_int" -> "i32"
        | TCon "bool" -> "i1"
        | TCon "cstr" -> "ptr"
        | TCon "unit" -> "{}"
        | TCon n ->
            match prog.types[n] with
            | RecordDef fs -> structTy (List.map snd fs)
            | UnionDef _ -> "ptr"
        | TTuple ts -> structTy ts
        | TVar _ -> failwith "unresolved type"

    and structTy ts =
        "{ " + (ts |> List.map llty |> String.concat ", ") + " }"

    let cellTy fields = structTy (TCon "c_int" :: fields)

    // C functions returning unit are void
    let retTy (s: FunSig) =
        if s.isExtern && resolve s.ret = TCon "unit" then "void" else llty s.ret

    let str (s: string) =
        let bytes = Encoding.UTF8.GetBytes s

        let enc =
            bytes
            |> Array.map (fun b ->
                if b >= 32uy && b < 127uy && b <> '"'B && b <> '\\'B then
                    string (char b)
                else
                    sprintf "\\%02X" b)
            |> String.concat ""

        let name = sprintf "@.str.%d" strCount.Value
        strCount.Value <- strCount.Value + 1

        globals.AppendLine(sprintf "%s = private unnamed_addr constant [%d x i8] c\"%s\\00\"" name (bytes.Length + 1) enc)
        |> ignore

        name

    /// Returns the body's result operand and its instructions.
    let genBody (pars: (string * Ty) list) (body: CExpr) =
        let out = StringBuilder()
        let n = ref 0
        let block = ref "entry"

        let fresh (prefix: string) =
            n.Value <- n.Value + 1
            sprintf "%s%d" prefix n.Value

        let tmp () = "%" + fresh "t"
        let emit (s: string) = out.Append("  ").AppendLine s |> ignore

        let label l =
            out.AppendLine(l + ":") |> ignore
            block.Value <- l

        let instr (fmt: string) =
            let r = tmp ()
            emit (r + " = " + fmt)
            r

        let phi ty (incoming: (string * string) list) =
            incoming
            |> List.map (fun (v, b) -> sprintf "[ %s, %%%s ]" v b)
            |> String.concat ", "
            |> sprintf "phi %s %s" ty
            |> instr

        /// Continues at a fresh block when `cond` holds, otherwise jumps to failL.
        let guardOr cond failL =
            let ok = fresh "ok"
            emit (sprintf "br i1 %s, label %%%s, label %%%s" cond ok failL)
            label ok

        /// Emits the test of pattern p against v (of type t); returns env extended with its bindings.
        let rec test (p: CPat) (t: Ty) (v: string) failL (env: Map<string, string>) =
            match p with
            | CPWild -> env
            | CPVar(x, _) -> env.Add(x, v)
            | CPAs(p, x, _) -> (test p t v failL env).Add(x, v)
            | CPInt k ->
                guardOr (instr (sprintf "icmp eq %s %s, %d" (llty t) v k)) failL
                env
            | CPBool b ->
                guardOr (instr (sprintf "icmp eq i1 %s, %b" v b)) failL
                env
            | CPTuple ps ->
                let ts =
                    match resolve t with
                    | TTuple ts -> ts
                    | _ -> failwith "tuple pattern on non-tuple"

                List.zip ps ts
                |> List.indexed
                |> List.fold
                    (fun env (i, (p, et)) -> test p et (instr (sprintf "extractvalue %s %s, %d" (llty t) v i)) failL env)
                    env
            | CPCtor(u, tag, ps) ->
                let fields = snd (List.item tag (union u))
                guardOr (instr (sprintf "icmp eq i32 %s, %d" (instr (sprintf "load i32, ptr %s" v)) tag)) failL
                let cell = cellTy fields

                List.zip ps fields
                |> List.indexed
                |> List.fold
                    (fun env (i, (p, ft)) ->
                        let fp = instr (sprintf "getelementptr %s, ptr %s, i32 0, i32 %d" cell v (i + 1))
                        test p ft (instr (sprintf "load %s, ptr %s" (llty ft) fp)) failL env)
                    env
            | CPOr(a, b) ->
                // both sides bind the same variables; merge them with phis
                let altL, okL = fresh "alt", fresh "or"
                let vars = patVars a
                let envA = test a t v altL env
                let fromA = vars |> List.map (fun (x, _) -> envA[x]), block.Value
                emit (sprintf "br label %%%s" okL)
                label altL
                let envB = test b t v failL env
                let fromB = vars |> List.map (fun (x, _) -> envB[x]), block.Value
                emit (sprintf "br label %%%s" okL)
                label okL

                vars
                |> List.indexed
                |> List.fold
                    (fun (env: Map<_, _>) (i, (x, xt)) ->
                        env.Add(x, phi (llty xt) [ (fst fromA)[i], snd fromA; (fst fromB)[i], snd fromB ]))
                    env

        let rec gen (env: Map<string, string>) (e: CExpr) : string =
            match e.k with
            | CLine(ln, e) ->
                try
                    gen env e
                with CompileError(0, msg) ->
                    fail ln msg
            | CInt k -> string k
            | CBool b -> if b then "true" else "false"
            | CStr s -> str s
            | CUnit -> "zeroinitializer"
            | CLocal x -> env[x]
            | CNeg a -> instr (sprintf "sub %s 0, %s" (llty a.ty) (gen env a))
            | CNot a -> instr (sprintf "xor i1 %s, true" (gen env a))
            | CBin(op, a, b) ->
                let va = gen env a
                let vb = gen env b

                // ponytail: '/' and '%' by zero are UB; add a trap check with debug builds
                if arith.ContainsKey op then
                    instr (sprintf "%s %s %s, %s" (arith[op]) (llty a.ty) va vb)
                else
                    instr (sprintf "icmp %s %s %s, %s" (cmp[op]) (llty a.ty) va vb)
            | CIf(c, t, f) ->
                let vc = gen env c
                let lt, lf, lend = fresh "then", fresh "else", fresh "endif"
                emit (sprintf "br i1 %s, label %%%s, label %%%s" vc lt lf)
                label lt
                let vt = gen env t
                let bt = block.Value
                emit (sprintf "br label %%%s" lend)
                label lf
                let vf = gen env f
                let bf = block.Value
                emit (sprintf "br label %%%s" lend)
                label lend
                phi (llty e.ty) [ vt, bt; vf, bf ]
            | CLet(x, v, body) -> gen (env.Add(x, gen env v)) body
            | CSeq(a, b) ->
                gen env a |> ignore
                gen env b
            | CTuple xs ->
                let ty = llty e.ty
                let vs = xs |> List.map (gen env)

                List.zip xs vs
                |> List.indexed
                |> List.fold (fun agg (i, (x, v)) -> instr (sprintf "insertvalue %s %s, %s %s, %d" ty agg (llty x.ty) v i)) "poison"
            | CField(r, i) -> instr (sprintf "extractvalue %s %s, %d" (llty r.ty) (gen env r) i)
            | CCtor(u, tag, []) ->
                let g = sprintf "@zs.ctor.%s.%s" u (fst (List.item tag (union u)))

                if ctorGlobals.Add g then
                    globals.AppendLine(sprintf "%s = private unnamed_addr constant { i32 } { i32 %d }" g tag) |> ignore

                g
            | CCtor(u, tag, args) ->
                let vs = args |> List.map (gen env)
                let cell = cellTy (snd (List.item tag (union u)))
                let size = instr (sprintf "getelementptr %s, ptr null, i32 1" cell)
                // ponytail: cells are never freed; Perceus RC (phase 2) frees them
                let c = instr (sprintf "call ptr @malloc(i64 %s)" (instr (sprintf "ptrtoint ptr %s to i64" size)))
                emit (sprintf "store i32 %d, ptr %s" tag c)

                List.zip args vs
                |> List.iteri (fun i (a, v) ->
                    let fp = instr (sprintf "getelementptr %s, ptr %s, i32 0, i32 %d" cell c (i + 1))
                    emit (sprintf "store %s %s, ptr %s" (llty a.ty) v fp))

                c
            | CCall(f, args) ->
                let s = prog.sigs[f]

                let argv =
                    args
                    |> List.mapi (fun i a ->
                        let v = gen env a

                        if i < s.pars.Length then
                            sprintf "%s %s" (llty a.ty) v
                        else
                            match resolve a.ty with
                            | TCon "bool" -> "i32 " + instr (sprintf "zext i1 %s to i32" v) // C default promotion
                            | TCon("int" | "c_int" | "cstr") -> sprintf "%s %s" (llty a.ty) v
                            | t -> fail 0 (sprintf "a %s cannot be passed to a C variadic function" (show t)))

                let ret = retTy s

                let fnTy =
                    if s.variadic then
                        sprintf "%s (%s, ...)" ret (s.pars |> List.map llty |> String.concat ", ")
                    else
                        ret

                let call = sprintf "call %s %s(%s)" fnTy s.sym (String.concat ", " argv)

                if ret = "void" then
                    emit call
                    "zeroinitializer"
                else
                    instr call
            | CMatch(s, cases) ->
                // ponytail: clauses are tested one after another; decision trees when match speed matters
                let v = gen env s
                let endL = fresh "mend"
                let mutable next = fresh "case"
                let results = ResizeArray()
                emit (sprintf "br label %%%s" next)

                for p, guard, body in cases do
                    label next
                    let failL = fresh "case"
                    let env = test p s.ty v failL env

                    if guard.IsSome then
                        guardOr (gen env guard.Value) failL

                    results.Add(gen env body, block.Value)
                    emit (sprintf "br label %%%s" endL)
                    next <- failL

                label next
                emit "call void @llvm.trap()" // unreachable: the type checker proved exhaustiveness
                emit "unreachable"
                label endL
                phi (llty e.ty) (List.ofSeq results)

        let env = pars |> List.fold (fun (m: Map<_, _>) (x, _) -> m.Add(x, "%p." + x)) Map.empty
        out.AppendLine "entry:" |> ignore
        let v = gen env body
        v, out.ToString()

    for KeyValue(name, s) in prog.sigs do
        if s.isExtern && name <> "malloc" then
            let ps = (s.pars |> List.map llty) @ (if s.variadic then [ "..." ] else [])
            globals.AppendLine(sprintf "declare %s @%s(%s)" (retTy s) name (String.concat ", " ps)) |> ignore

    for name, pars, body in prog.funs do
        let s = prog.sigs[name]
        let typed = List.zip pars s.pars
        let v, text = genBody typed body
        let ps = typed |> List.map (fun (x, t) -> sprintf "%s %%p.%s" (llty t) x) |> String.concat ", "
        let rt = llty s.ret

        funcs
            .AppendLine(sprintf "define %s %s(%s) {" rt s.sym ps)
            .Append(text)
            .AppendLine(sprintf "  ret %s %s" rt v)
            .AppendLine("}")
            .AppendLine()
        |> ignore

    // C entry point; an int result becomes the exit code
    let main =
        match resolve prog.sigs["main"].ret with
        | TCon "unit" -> "  call {} @zs.main()\n  ret i32 0"
        | TCon "c_int" -> "  %r = call i32 @zs.main()\n  ret i32 %r"
        | _ -> "  %r = call i64 @zs.main()\n  %c = trunc i64 %r to i32\n  ret i32 %c"

    funcs.AppendLine("define i32 @main() {").AppendLine(main).AppendLine("}") |> ignore
    globals.ToString() + "\n" + funcs.ToString()
