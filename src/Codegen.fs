module Codegen

open System.Collections.Generic
open System.Text
open Syntax

type Sig =
    { args: Ty list
      variadic: bool
      ret: Ty
      sym: string }

let llty =
    function
    | TInt -> "i64"
    | TCInt -> "i32"
    | TBool -> "i1"
    | TCStr -> "ptr"
    | TUnit -> "void"

let private arith =
    dict [ "+", "add"; "-", "sub"; "*", "mul"; "/", "sdiv"; "%", "srem" ]

let private cmp =
    dict [ "=", "eq"; "<>", "ne"; "<", "slt"; ">", "sgt"; "<=", "sle"; ">=", "sge" ]

let private isInt t = t = TInt || t = TCInt

let private mismatch what expected actual =
    fail 0 (sprintf "%s: expected %s, got %s" what (tyName expected) (tyName actual))

// ponytail: type checking is fused into codegen (no inference); phase 1 splits out HM typecheck
/// Compiles a program to textual LLVM IR.
let compile (decls: (int * Decl) list) : string =
    let globals = StringBuilder()
    let funcs = StringBuilder()
    let fns = Dictionary<string, Sig>()
    let syms = HashSet<string>()
    let strCount = ref 0

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

    /// Returns the body's type, its result operand, and its instructions.
    let genBody (pars: (string * Ty) list) (retHint: Ty option) (body: Expr) =
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

        // hint: expected type, lets integer literals become c_int where C wants one
        let rec gen (env: Map<string, Ty * string>) (hint: Ty option) (e: Expr) : Ty * string =
            match e with
            | At(ln, e) ->
                try
                    gen env hint e
                with CompileError(0, msg) ->
                    fail ln msg
            | Lit n -> (if hint = Some TCInt then TCInt else TInt), string n
            | BoolLit b -> TBool, (if b then "true" else "false")
            | StrLit s -> TCStr, str s
            | UnitLit -> TUnit, ""
            | Var x ->
                match env.TryFind x with
                | Some v -> v
                | None when fns.ContainsKey x -> fail 0 (sprintf "'%s' is a function; call it (no first-class functions yet)" x)
                | None -> fail 0 (sprintf "unknown name '%s'" x)
            | Neg e ->
                let t, v = gen env hint e

                if not (isInt t) then
                    mismatch "operand of '-'" TInt t

                let r = tmp ()
                emit (sprintf "%s = sub %s 0, %s" r (llty t) v)
                t, r
            | Not e ->
                let t, v = gen env None e

                if t <> TBool then
                    mismatch "operand of 'not'" TBool t

                let r = tmp ()
                emit (sprintf "%s = xor i1 %s, true" r v)
                TBool, r
            | Bin(op, a, b) ->
                let ta, va = gen env (if cmp.ContainsKey op then None else hint) a
                let tb, vb = gen env (Some ta) b

                if ta <> tb then
                    mismatch (sprintf "right operand of '%s'" op) ta tb

                let r = tmp ()

                if arith.ContainsKey op then
                    if not (isInt ta) then
                        mismatch (sprintf "operand of '%s'" op) TInt ta

                    // ponytail: '/' and '%' by zero are UB; add a trap check with debug builds
                    emit (sprintf "%s = %s %s %s, %s" r (arith[op]) (llty ta) va vb)
                    ta, r
                else
                    if not (isInt ta || (ta = TBool && (op = "=" || op = "<>"))) then
                        fail 0 (sprintf "cannot compare values of type %s with '%s'" (tyName ta) op)

                    emit (sprintf "%s = icmp %s %s %s, %s" r (cmp[op]) (llty ta) va vb)
                    TBool, r
            | If(c, t, e) ->
                let tc, vc = gen env None c

                if tc <> TBool then
                    mismatch "condition of 'if'" TBool tc

                let lt, le, lend = fresh "then", fresh "else", fresh "endif"
                emit (sprintf "br i1 %s, label %%%s, label %%%s" vc lt le)
                label lt
                let tt, vt = gen env hint t
                let bt = block.Value
                emit (sprintf "br label %%%s" lend)
                label le

                let te, ve =
                    match e with
                    | Some e -> gen env (Some tt) e
                    | None when tt <> TUnit -> fail 0 "'if' without 'else' must have type unit"
                    | None -> TUnit, ""

                let be = block.Value
                emit (sprintf "br label %%%s" lend)

                if tt <> te then
                    mismatch "'else' branch" tt te

                label lend

                if tt = TUnit then
                    TUnit, ""
                else
                    let r = tmp ()
                    emit (sprintf "%s = phi %s [ %s, %%%s ], [ %s, %%%s ]" r (llty tt) vt bt ve be)
                    tt, r
            | Let(x, ann, v, rest) ->
                let t, value = gen env ann v

                if ann.IsSome && ann.Value <> t then
                    mismatch (sprintf "value of '%s'" x) ann.Value t

                gen (env.Add(x, (t, value))) hint rest
            | Seq(a, b) ->
                gen env None a |> ignore
                gen env hint b
            | Call("ignore", [ a ]) when not (fns.ContainsKey "ignore") ->
                gen env None a |> ignore
                TUnit, ""
            | Call(f, args) ->
                let s =
                    match fns.TryGetValue f with
                    | true, s -> s
                    | _ when env.ContainsKey f -> fail 0 (sprintf "'%s' is not a function" f)
                    | _ -> fail 0 (sprintf "unknown function '%s'" f)

                let nFixed = s.args.Length

                if args.Length < nFixed || (args.Length > nFixed && not s.variadic) then
                    fail 0 (sprintf "'%s' expects %d argument(s), got %d" f nFixed args.Length)

                let argv =
                    args
                    |> List.mapi (fun i a ->
                        if i < nFixed then
                            let pt = s.args[i]
                            let t, v = gen env (Some pt) a

                            if t <> pt then
                                mismatch (sprintf "argument %d of '%s'" (i + 1) f) pt t

                            sprintf "%s %s" (llty t) v
                        else
                            let t, v = gen env None a

                            match t with
                            | TUnit -> fail 0 "cannot pass unit to a C variadic function"
                            | TBool -> // C default argument promotion
                                let r = tmp ()
                                emit (sprintf "%s = zext i1 %s to i32" r v)
                                "i32 " + r
                            | _ -> sprintf "%s %s" (llty t) v)

                let fnTy =
                    if s.variadic then
                        sprintf "%s (%s, ...)" (llty s.ret) (s.args |> List.map llty |> String.concat ", ")
                    else
                        llty s.ret

                let call = sprintf "call %s %s(%s)" fnTy s.sym (String.concat ", " argv)

                if s.ret = TUnit then
                    emit call
                    TUnit, ""
                else
                    let r = tmp ()
                    emit (sprintf "%s = %s" r call)
                    s.ret, r

        let env =
            pars |> List.fold (fun (m: Map<_, _>) (x, t) -> m.Add(x, (t, "%p." + x))) Map.empty

        out.AppendLine "entry:" |> ignore
        let t, v = gen env retHint body
        t, v, out.ToString()

    for ln, d in decls do
        try
            match d with
            | Extern(name, args, variadic, ret) ->
                if not (syms.Add("@" + name)) then
                    fail 0 (sprintf "'%s' is already declared" name)

                fns[name] <-
                    { args = args
                      variadic = variadic
                      ret = ret
                      sym = "@" + name }

                let ps = (args |> List.map llty) @ (if variadic then [ "..." ] else [])

                globals.AppendLine(sprintf "declare %s @%s(%s)" (llty ret) name (String.concat ", " ps))
                |> ignore
            | Fun(name, isRec, pars, ret, body) ->
                let sym = "@zs." + name

                if not (syms.Add sym) then
                    fail 0 (sprintf "'%s' is already defined" name)

                if pars |> List.exists (fun (_, t) -> t = TUnit) then
                    fail 0 "parameters of type unit are not allowed"

                if (pars |> List.map fst |> List.distinct).Length <> pars.Length then
                    fail 0 "duplicate parameter name"

                let mk r =
                    { args = List.map snd pars
                      variadic = false
                      ret = r
                      sym = sym }

                // phase 0 has no inference: an unannotated 'let rec' is assumed to return int
                if isRec then
                    fns[name] <- mk (defaultArg ret TInt)

                let t, v, text = genBody pars ret body
                let rt = if isRec then defaultArg ret TInt else defaultArg ret t

                if t <> rt then
                    mismatch (sprintf "result of '%s'" name) rt t

                fns[name] <- mk rt
                let ps = pars |> List.map (fun (x, t) -> sprintf "%s %%p.%s" (llty t) x) |> String.concat ", "
                funcs.AppendLine(sprintf "define %s %s(%s) {" (llty rt) sym ps).Append(text) |> ignore

                funcs
                    .AppendLine(if rt = TUnit then "  ret void" else sprintf "  ret %s %s" (llty rt) v)
                    .AppendLine("}")
                    .AppendLine()
                |> ignore
        with CompileError(0, msg) ->
            fail ln msg

    // C entry point; the int result becomes the exit code
    let main =
        match fns.TryGetValue "main" with
        | true, s when s.sym = "@zs.main" ->
            if not s.args.IsEmpty then
                fail 0 "'main' must take no parameters: let main () = ..."

            match s.ret with
            | TUnit -> "  call void @zs.main()\n  ret i32 0"
            | TCInt -> "  %r = call i32 @zs.main()\n  ret i32 %r"
            | TInt -> "  %r = call i64 @zs.main()\n  %c = trunc i64 %r to i32\n  ret i32 %c"
            | t -> fail 0 (sprintf "'main' must return int, c_int or unit, not %s" (tyName t))
        | _ -> fail 0 "no 'main' function"

    funcs.AppendLine("define i32 @main() {").AppendLine(main).AppendLine("}") |> ignore
    globals.ToString() + "\n" + funcs.ToString()
