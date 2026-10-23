/// Effect handlers compiled by evidence passing with yield bubbling (Xie and Leijen, ICFP 2021,
/// as Koka does; DESIGN §6.1). After monomorphization each function's row is concrete:
///   - A function whose row isn't empty takes a frame per effect in it (its evidence) after its
///     last parameter; a call passes the caller's frames for the callee's effects (the k-th
///     effect of a name in the callee's row is the k-th in the caller's: the innermost first).
///   - A frame is a handler's: its marker, and a closure per operation. Performing an operation
///     calls its closure. A tail-resumptive clause (it resumes once, last) is that closure: it
///     runs where the operation is performed and returns the result, nothing captured. Any other
///     clause's closure records the clause in the thread's yield state and returns at once.
///   - After a call that may yield (its row isn't empty), a test of that state. When it's set,
///     the function adds the rest of itself to the continuation (a closure calling a local
///     function the code after the call went into, its mutable variables passed along) and
///     returns too, up to the handle whose marker it is, which runs the clause with that
///     continuation as the resumption. A clause that never resumes wants no continuation, and
///     none is made. A call in tail position needs no test: there's no rest.
///   - A loop with such calls becomes a local function taking its mutable variables, and the
///     code after it goes into the loop's exit.
/// Functions without effects and without handles compile exactly as before.
module Evidence

open System.Collections.Generic
open Core
open Mono

let private mk k ty = { k = k; ty = ty }

// per thread, numbered per function (each thread does one at a time): a function's code doesn't
// depend on the others'
let private counter = new System.Threading.ThreadLocal<int ref>(fun () -> ref 0)

let private fresh (x: string) =
    let c = counter.Value
    c.Value <- c.Value + 1
    sprintf "%s.e%d" x c.Value

let private labelsOf (row: Ty) = fst (rowParts row)

/// A handler's frame for an effect: a boxed union of one case, its marker and its operations.
let frameName (label: Ty) = "$frame:" + showFull label
let private frameTy (label: Ty) = TCon(frameName label, [])

/// A type with evidence: a function type's effects become frame parameters after its parameter,
/// and rows are gone.
let rec evTy (t: Ty) : Ty =
    match prune t with
    | TFun(a, b, row) -> TFun(evTy a, List.foldBack (fun l acc -> tfun (frameTy l) acc) (labelsOf row) (evTy b), rowEmpty)
    | TCon(("$ext" | "$total"), _) -> rowEmpty
    | TCon(n, args) -> TCon(n, List.map evTy args)
    | TTuple ts -> TTuple(List.map evTy ts)
    | t -> t

/// Whether a type has a function with effects anywhere in it (else evTy changes nothing).
let rec private effectful (t: Ty) =
    match prune t with
    | TFun(a, b, row) -> not (isRowEmpty row) || effectful a || effectful b
    | TCon(("$ext" | "$total"), _) -> false
    | TCon(_, args) -> List.exists effectful args
    | TTuple ts -> List.exists effectful ts
    | _ -> false

/// The rows of the arrows a call with n arguments goes through.
let rec private rowsOf n (t: Ty) =
    match n, prune t with
    | 0, _ -> []
    | n, TFun(_, r, row) -> row :: rowsOf (n - 1) r
    | _ -> []

let rec private resultAfter n (t: Ty) =
    match n, prune t with
    | 0, t -> t
    | n, TFun(_, r, _) -> resultAfter (n - 1) r
    | _ -> failwith "Evidence: not a function type"

let private tState = tInt
let private state () = mk (CPrim("eff.state", [])) tState
let private int' (n: int64) = mk (CInt n) tInt
let private isState (n: int64) = mk (CBin("=", state (), int' n)) tBool
let private unit' = mk CUnit tUnit
let private seq' (a: CExpr) (b: CExpr) = mk (CSeq(a, b)) b.ty
let private local (x: string) (t: Ty) = mk (CLocal x) t

/// Code made by this pass, put among code still to lower: it goes through as it is.
let private lowered (x: CExpr) = mk (CPrim("eff.lowered", [ x ])) x.ty

/// What follows an expression being lowered: it's the function's result (in tail position), or
/// the rest, given the value (an atom: a variable, or an expression evaluated where it's put)
/// in the context there.
type private K =
    | Tail
    | Then of (Ctx -> CExpr -> CExpr)

/// The function being lowered: its frames in scope (labels in canonical order, each with the
/// expression holding its frame), its mutable variables in scope (the name in Core, the name
/// in the block being made, the type), its result's type, and the joins of Simplify's that
/// became local functions (their function, the mutable variables they take).
and private Ctx =
    { ev: (Ty * CExpr) list
      muts: (string * string * Ty) list
      ret: Ty
      joins: Map<string, string * string list> }

let private cur (ctx: Ctx) (x: string) =
    match ctx.muts |> List.tryFind (fun (o, _, _) -> o = x) with
    | Some(_, n, _) -> n
    | None -> x

/// The frames for a callee's row: the k-th effect of a name gets the k-th frame of it here.
let private framesFor (ctx: Ctx) (row: Ty) : CExpr list =
    let used = Dictionary<string, int>()

    [ for l in labelsOf row do
          let n = labelName l
          let k = match used.TryGetValue n with | true, k -> k | _ -> 0
          used[n] <- k + 1

          match ctx.ev |> List.filter (fun (m, _) -> labelName m = n) |> List.tryItem k with
          | Some(_, f) -> yield f
          | None -> failwithf "Evidence: no frame for %s" (show l) ]

/// The frames in scope with a handler's added: in front of the others of its effect.
let private withFrame (ev: (Ty * CExpr) list) (label: Ty) (frame: CExpr) =
    let n = labelName label

    match ev |> List.tryFindIndex (fun (m, _) -> labelName m = n || compare (labelName m) n > 0) with
    | Some i -> List.insertAt i (label, frame) ev
    | None -> ev @ [ label, frame ]

/// Lowers a program's functions. effects: each effect's operations; types gets the frames.
let run (types: Dictionary<string, TypeInfo>) (effects: Dictionary<string, EffectInfo>) (funs: MFun list) : MFun list =
    // ---- the frames' types, made before the functions are lowered (on every core, reading them)
    let opTypes (label: Ty) =
        match prune label with
        | TCon(n, targs) ->
            effects[n].ops
            |> List.map (fun o ->
                let own = List.init o.own (fun _ -> tUnit)
                let inst = targs @ own
                List.foldBack (fun p acc -> tfun (evTy (substGen inst p)) acc) o.pars (evTy (substGen inst o.ret)))
        | _ -> []

    let rec register (label: Ty) =
        let name = frameName label

        if not (types.ContainsKey name) then
            let ops = opTypes label
            types[name] <- { npars = 0; def = UnionDef [ "$frame", tInt :: ops ] }

            for t in ops do
                labelsIn t

    and labelsIn (t: Ty) =
        match prune t with
        | TFun(a, b, row) ->
            labelsIn a
            labelsIn b

            for l in labelsOf row do
                labelsIn l
                register l
        | TCon(_, args)
        | TTuple args -> List.iter labelsIn args
        | _ -> ()

    let rec labelsInExpr (e: CExpr) =
        labelsIn e.ty

        match e.k with
        | CPerform(l, _, _) -> register l
        | CHandle(l, _, cls, _, _) ->
            register l

            for _, ps, (_, kt), _ in cls do
                labelsIn kt

                for _, t in ps do
                    labelsIn t
        | CLam(ps, _)
        | CLetFun(_, _, ps, _, _) -> ps |> List.iter (snd >> labelsIn)
        | CLetRec(fs, _) -> fs |> List.iter (fun (_, ps, _) -> ps |> List.iter (snd >> labelsIn))
        | CMatch(_, cases) -> cases |> List.iter (fun (p, _, _) -> patVars p |> List.iter (snd >> labelsIn))
        | _ -> ()

        children e.k |> List.iter labelsInExpr

    /// Whether a function has anything to lower: effects in its row or types, a perform, a
    /// handle, or an opened function.
    let rec touches (e: CExpr) =
        effectful e.ty
        || (match e.k with
            | CPerform _
            | CHandle _ -> true
            | CPrim("eff.open", _) -> true
            | CLam(ps, _)
            | CLetFun(_, _, ps, _, _) -> ps |> List.exists (snd >> effectful)
            | CLetRec(fs, _) -> fs |> List.exists (fun (_, ps, _) -> ps |> List.exists (snd >> effectful))
            | _ -> false)
        || (children e.k |> List.exists touches)

    let needs (f: MFun) =
        not (isRowEmpty f.row) || effectful f.ret || f.pars |> List.exists (snd >> effectful) || touches f.body

    let funs = funs |> Array.ofList |> Array.Parallel.map (fun f -> f, needs f)

    for f, lower in funs do
        if lower then
            labelsIn f.row
            labelsIn f.ret
            f.pars |> List.iter (snd >> labelsIn)
            labelsInExpr f.body

    let opIsPolymorphic (label: Ty) (op: int) = effects[labelName label].ops[op].own > 0
    let tagOf (u: string) (case: string) =
        match types[u].def with
        | UnionDef cs -> cs |> List.findIndex (fun (c, _) -> c = case)
        | _ -> failwith "tagOf"

    // ---- lowering one function

    let lowerFun (f: MFun) : MFun =
        let fname = f.name
        counter.Value.Value <- 0
        let localTypes = localTypesIn f.body

        // a local function's row: the one of its type where it's used (unused: none)
        let localRow (n: string) (arity: int) =
            match localTypes.TryGetValue n with
            | true, t -> rowsOf arity t |> List.tryLast |> Option.defaultValue rowEmpty
            | _ -> rowEmpty

        /// A call's or an operation's code that may yield, k given its value: a tail call as it
        /// is, else the test, the rest in a local function the continuation calls too.
        let rec yieldPoint (ctx: Ctx) (call: CExpr) (k: K) : CExpr =
            match k with
            | Tail -> call
            | Then _ ->
                withJoin ctx k call.ty (fun ctx (k: K) ->
                    match k with
                    | Then jump ->
                        let contTy = tfun tCPtr call.ty
                        let resumeTy = tfun tCPtr ctx.ret
                        let yielding () = mk (CBin("<>", state (), int' 0L)) tBool
                        let dummy () = mk (CPrim("eff.dummy", [])) ctx.ret
                        // this frame's continuation, made when the call yields: the continuation
                        // so far (c), then the rest; when that yields again, this frame is added
                        // to the new continuation the same way (a local function: it calls itself)
                        let resume = fresh "$resume"
                        let c, p, y = fresh "$c", fresh "$p", fresh "$y"
                        let snaps = ctx.muts |> List.map (fun (o, n, t) -> o, fresh n, n, t)
                        let rctx = { ctx with muts = snaps |> List.map (fun (o, s, _, t) -> o, s, t) }
                        let rpars = (c, contTy) :: (snaps |> List.map (fun (_, s, _, t) -> s, t)) @ [ p, tCPtr ]
                        let rty = List.foldBack (fun (_, t) acc -> tfun t acc) rpars ctx.ret
                        let rlocal = local resume rty

                        // the continuation of this frame: resume applied to all but p
                        let contOf (c: CExpr) (vals: CExpr list) = mk (CApp(rlocal, c :: vals)) resumeTy

                        let extendWith (vals: Ctx -> CExpr list) (ctx: Ctx) =
                            let inner = fresh "$inner"
                            mk (CLet(inner, mk (CPrim("eff.takeCont", [])) contTy, mk (CPrim("eff.setCont", [ contOf (local inner contTy) (vals ctx) ])) tUnit)) tUnit

                        let bubble (x: CExpr) (extend: CExpr) =
                            seq' (mk (CIf(isState 1L, extend, unit')) tUnit) (seq' (mk (CPrim("eff.forget", [ x ])) tUnit) (dummy ()))

                        let snapVals (c: Ctx) = snaps |> List.map (fun (o, _, _, t) -> local (cur c o) t)

                        let rbody =
                            let yv = local y call.ty
                            let again = extendWith snapVals rctx
                            mk (CLet(y, mk (CApp(local c contTy, [ local p tCPtr ])) call.ty, mk (CIf(yielding (), bubble yv again, jump rctx yv)) ctx.ret)) ctx.ret

                        let x = fresh "$r"
                        let xv = local x call.ty
                        // the mutable variables' values now, for the continuation
                        let first =
                            List.foldBack (fun (_, s, n, t) acc -> mk (CLet(s, local n t, acc)) acc.ty) snaps (extendWith (fun _ -> snaps |> List.map (fun (_, s, _, t) -> local s t)) ctx)

                        let main = mk (CLet(x, call, mk (CIf(yielding (), bubble xv first, jump ctx xv)) ctx.ret)) ctx.ret
                        mk (CLetRec([ resume, rpars, rbody ], main)) ctx.ret
                    | Tail -> failwith "unreachable")

        /// k as a local function when it's Then (so the code after a branch or a call is made
        /// once): body gets the context and a K that jumps to it (the mutable variables passed).
        and withJoin (ctx: Ctx) (k: K) (vty: Ty) (body: Ctx -> K -> CExpr) : CExpr =
            match k with
            | Tail -> body ctx Tail
            | Then rest ->
                let j = fresh "$join"
                let v = fresh "$v"
                let ms = ctx.muts
                let inner = ms |> List.map (fun (o, n, t) -> o, fresh n, t)
                let ps = (v, vty) :: (inner |> List.map (fun (_, n, t) -> n + "p", t))
                let jctx = { ctx with muts = inner }

                let jbody =
                    List.foldBack (fun (_, n, t) acc -> mk (CLetMut(n, local (n + "p") t, acc)) acc.ty) inner (rest jctx (local v vty))

                let jty = List.foldBack (fun (_, t) acc -> tfun t acc) ps ctx.ret
                let jump (c: Ctx) (a: CExpr) = mk (CApp(local j jty, a :: (ms |> List.map (fun (o, _, t) -> local (cur c o) t)))) ctx.ret
                let code = body ctx (Then jump)
                mk (CLetFun(j, false, ps, jbody, code)) code.ty

        /// Whether e has a yield point of this function's (not in its lambdas and local functions,
        /// which are functions of their own, nor in a handle's body and clauses).
        and yields (ctx: Ctx) (e: CExpr) : bool =
            match e.k with
            | CPerform _ -> true
            // a jump to a join point lowered as a local function: that function runs the rest,
            // so the jump goes through lower, where nothing follows it
            | CJump(j, _) when ctx.joins.ContainsKey j -> true
            | CApp(h, args) -> (rowsOf args.Length h.ty |> List.exists (isRowEmpty >> not)) || yields ctx h || List.exists (yields ctx) args
            | CHandle _ -> not ctx.ev.IsEmpty
            | CLam _ -> false
            | CLetFun(_, _, _, _, rest) -> yields ctx rest
            | CLetRec(_, rest) -> yields ctx rest
            | k -> children k |> List.exists (yields ctx)

        /// e without yield points, rebuilt: types with evidence, mutable variables renamed, and its
        /// lambdas, local functions and handles lowered.
        and plain (ctx: Ctx) (e: CExpr) : CExpr =
            let ty = evTy e.ty

            match e.k with
            | CLocal x -> mk (CLocal(cur ctx x)) ty
            | CAssign(x, v) -> mk (CAssign(cur ctx x, plain ctx v)) ty
            | CArraySet(x, i, v) -> mk (CArraySet(cur ctx x, plain ctx i, plain ctx v)) ty
            | CLam(ps, b) -> lambda ctx e ps b
            | CLetFun(n, r, ps, b, rest) ->
                let ps', b' = localFun ctx n ps b
                mk (CLetFun(n, r, ps', b', plain ctx rest)) ty
            | CLetRec(fs, rest) ->
                let fs' = fs |> List.map (fun (n, ps, b) -> (let ps', b' = localFun ctx n ps b in n, ps', b'))
                mk (CLetRec(fs', plain ctx rest)) ty
            | CHandle(l, b, cls, r, rb) -> handle ctx l b cls r rb ty
            | CPrim("eff.open", [ g ]) -> adapter ctx g e.ty
            | CPrim("eff.lowered", [ x ]) -> x
            | CJoin(j, ps, b, r) ->
                let r' = plain ctx r
                mk (CJoin(j, ps |> List.map (fun (x, t) -> x, evTy t), plain ctx b, r')) ty
            | CMatch(s, cases) -> mk (CMatch(plain ctx s, cases |> List.map (fun (p, g, b) -> mapPatTypes evTy p, Option.map (plain ctx) g, plain ctx b))) ty
            | CApp(h, args) -> mk (CApp(plain ctx h, List.map (plain ctx) args)) ty
            | CJump(j, args) when ctx.joins.ContainsKey j ->
                let fn, ms = ctx.joins[j]
                let args = List.map (plain ctx) args
                mk (CApp(local fn (List.foldBack (fun (a: CExpr) acc -> tfun a.ty acc) args ctx.ret), args @ (ms |> List.map (fun o -> local (cur ctx o) (mutTy ctx o))))) ctx.ret
            | k -> mk (mapChildren (plain ctx) k) ty

        and mutTy (ctx: Ctx) (o: string) =
            match ctx.muts |> List.tryFind (fun (x, _, _) -> x = o) with
            | Some(_, _, t) -> t
            | None -> failwith "mutTy"

        /// A lambda with evidence: its frames after its parameters, its body lowered.
        and lambda (ctx: Ctx) (e: CExpr) (ps: (string * Ty) list) (b: CExpr) =
            let row = rowsOf ps.Length e.ty |> List.tryLast |> Option.defaultValue rowEmpty
            let evs = labelsOf row |> List.map (fun l -> l, fresh "$ev")
            let body = lowerBody { ev = evs |> List.map (fun (l, x) -> l, local x (frameTy l)); muts = []; ret = evTy (resultAfter ps.Length e.ty); joins = Map.empty } b
            mk (CLam((ps |> List.map (fun (x, t) -> x, evTy t)) @ (evs |> List.map (fun (l, x) -> x, frameTy l)), body)) (evTy e.ty)

        and localFun (ctx: Ctx) (n: string) (ps: (string * Ty) list) (b: CExpr) =
            let row = localRow n ps.Length
            let evs = labelsOf row |> List.map (fun l -> l, fresh "$ev")
            let body = lowerBody { ev = evs |> List.map (fun (l, x) -> l, local x (frameTy l)); muts = []; ret = evTy b.ty; joins = Map.empty } b
            (ps |> List.map (fun (x, t) -> x, evTy t)) @ (evs |> List.map (fun (l, x) -> x, frameTy l)), body

        /// A global function opened to a larger row (Typer.opened): a lambda taking that row's
        /// frames, which calls it with those of its own row.
        and adapter (ctx: Ctx) (g: CExpr) (openTy: Ty) =
            let rec arity n (a: Ty) (b: Ty) =
                match prune a, prune b with
                | TFun(_, ra, rowA), TFun(_, rb, rowB) -> if showFull rowA <> showFull rowB then n + 1 else arity (n + 1) ra rb
                | _ -> n

            let n = arity 0 g.ty openTy
            let rec pars k (t: Ty) = if k = 0 then [] else (match prune t with TFun(a, r, _) -> a :: pars (k - 1) r | _ -> [])
            let ps = pars n openTy |> List.map (fun t -> fresh "$x", t)
            let openRow = rowsOf n openTy |> List.last
            let evs = labelsOf openRow |> List.map (fun l -> l, fresh "$ev")
            let actx = { ctx with ev = evs |> List.map (fun (l, x) -> l, local x (frameTy l)); muts = [] }
            let ownRow = rowsOf n g.ty |> List.last
            let args = (ps |> List.map (fun (x, t) -> local x (evTy t))) @ framesFor actx ownRow
            let resTy = evTy (resultAfter n g.ty)
            let call = mk (CApp(plain ctx g, args)) resTy
            mk (CLam((ps |> List.map (fun (x, t) -> x, evTy t)) @ (evs |> List.map (fun (l, x) -> x, frameTy l)), call)) (evTy openTy)

        /// A call's arguments with the frames for the rows of the arrows they go through.
        and withEvidence (ctx: Ctx) (calleeTy: Ty) (args: CExpr list) =
            let rows = rowsOf args.Length calleeTy
            List.zip args rows |> List.collect (fun (a, row) -> a :: framesFor ctx row)

        /// These expressions' values, in order, then f with them: those before the last one that
        /// yields are bound first (or are constants or variables that can't change).
        and lowerAtoms (ctx: Ctx) (es: CExpr list) (f: Ctx -> CExpr list -> CExpr) : CExpr =
            let lastY = es |> List.tryFindIndexBack (yields ctx)

            let trivial (e: CExpr) =
                match e.k with
                | CInt _
                | CFloat _
                | CBool _
                | CStr _
                | CUnit
                | CGlobal _
                | CGlobalVal _ -> true
                | CLocal x -> not (ctx.muts |> List.exists (fun (o, _, _) -> o = x))
                | _ -> false

            let rec go (ctx: Ctx) (i: int) (acc: CExpr list) (es: CExpr list) =
                match es with
                | [] -> f ctx (List.rev acc)
                | e :: rest ->
                    match lastY with
                    | Some j when i <= j ->
                        if yields ctx e then
                            lower ctx e (Then(fun ctx' a -> go ctx' (i + 1) (a :: acc) rest))
                        elif trivial e then
                            go ctx (i + 1) (plain ctx e :: acc) rest
                        else
                            let t = fresh "$a"
                            let pe = plain ctx e
                            let inner = go ctx (i + 1) (local t pe.ty :: acc) rest
                            mk (CLet(t, pe, inner)) inner.ty
                    | _ -> go ctx (i + 1) (plain ctx e :: acc) rest

            go ctx 0 [] es

        and give (ctx: Ctx) (k: K) (v: CExpr) =
            match k with
            | Tail -> v
            | Then f -> f ctx v

        /// e lowered, k given its value.
        and lower (ctx: Ctx) (e: CExpr) (k: K) : CExpr =
            if not (yields ctx e) then
                give ctx k (plain ctx e)
            else
                match e.k with
                | CLine(l, a) ->
                    let inner = lower ctx a k
                    mk (CLine(l, inner)) inner.ty
                | CLet(x, v, b) ->
                    lower ctx v (Then(fun ctx a ->
                        let b' = lower ctx b k
                        mk (CLet(x, a, b')) b'.ty))
                | CSeq(a, b) ->
                    lower ctx a (Then(fun ctx a' ->
                        let b' = lower ctx b k
                        mk (CSeq(a', b')) b'.ty))
                | CLetMut(x, v, b) ->
                    lower ctx v (Then(fun ctx a ->
                        let b' = lower { ctx with muts = (x, x, a.ty) :: ctx.muts } b k
                        mk (CLetMut(x, a, b')) b'.ty))
                | CAssign(x, v) -> lower ctx v (Then(fun ctx a -> give ctx k (mk (CAssign(cur ctx x, a)) tUnit)))
                | CArraySet(x, i, v) ->
                    lowerAtoms ctx [ i; v ] (fun ctx args ->
                        match args with
                        | [ i'; v' ] -> give ctx k (mk (CArraySet(cur ctx x, i', v')) tUnit)
                        | _ -> failwith "unreachable")
                | CLetFun(n, r, ps, b, rest) ->
                    let ps', b' = localFun ctx n ps b
                    let rest' = lower ctx rest k
                    mk (CLetFun(n, r, ps', b', rest')) rest'.ty
                | CLetRec(fs, rest) ->
                    let fs' = fs |> List.map (fun (n, ps, b) -> (let ps', b' = localFun ctx n ps b in n, ps', b'))
                    let rest' = lower ctx rest k
                    mk (CLetRec(fs', rest')) rest'.ty
                | CIf(c, t, f) ->
                    lower ctx c (Then(fun ctx c' ->
                        withJoin ctx k (evTy e.ty) (fun ctx k ->
                            let t' = lower ctx t k
                            let f' = lower ctx f k
                            mk (CIf(c', t', f')) t'.ty)))
                | CMatch(s, cases) ->
                    if cases |> List.exists (fun (_, g, _) -> g |> Option.exists (yields ctx)) then
                        Syntax.fail 0 (sprintf "a when guard can't perform an effect: match first, then perform in the case (in %s)" (Core.baseFunName fname))

                    lower ctx s (Then(fun ctx s' ->
                        withJoin ctx k (evTy e.ty) (fun ctx k ->
                            let cases' = cases |> List.map (fun (p, g, b) -> mapPatTypes evTy p, Option.map (plain ctx) g, lower ctx b k)
                            let _, _, b0 = cases'.Head
                            mk (CMatch(s', cases')) b0.ty)))
                | CJoin(j, ps, body, rest) ->
                    // a join point of Simplify's: a local function (its paths may yield)
                    withJoin ctx k (evTy e.ty) (fun ctx k ->
                        let fn = fresh "$jp"
                        let ms = ctx.muts
                        let inner = ms |> List.map (fun (o, n, t) -> o, fresh n, t)
                        let ps' = (ps |> List.map (fun (x, t) -> x, evTy t)) @ (inner |> List.map (fun (_, n, t) -> n + "p", t))
                        let jctx = { ctx with muts = inner }
                        let jbody = List.foldBack (fun (_, n, t) acc -> mk (CLetMut(n, local (n + "p") t, acc)) acc.ty) inner (lower jctx body k)
                        let rest' = lower { ctx with joins = ctx.joins.Add(j, (fn, ms |> List.map (fun (o, _, _) -> o))) } rest k
                        mk (CLetFun(fn, false, ps', jbody, rest')) rest'.ty)
                | CJump(j, args) when ctx.joins.ContainsKey j ->
                    let fn, ms = ctx.joins[j]

                    lowerAtoms ctx args (fun ctx args ->
                        let fty = List.foldBack (fun (a: CExpr) acc -> tfun a.ty acc) args ctx.ret
                        mk (CApp(local fn fty, args @ (ms |> List.map (fun o -> local (cur ctx o) (mutTy ctx o))))) ctx.ret)
                | CWhile(c, b) -> loop ctx k [] (fun ctx finish -> lower ctx c (Then(fun ctx cv -> mk (CIf(cv, lower ctx b (Then(fun ctx v -> seq' v (finish ctx true []))), finish ctx false [])) (roundTy ctx []))))
                | CFor(x, a, s, b, body) ->
                    lowerAtoms ctx [ a; s; b ] (fun ctx args ->
                        match args with
                        | [ a'; s'; b' ] ->
                            let sv, bv = fresh "$step", fresh "$to"
                            let down =
                                match s.k with
                                | CInt n -> n < 0L
                                | CNeg _ -> true
                                | _ -> false

                            let it = evTy a.ty
                            let iv = local x it
                            let cond = mk (CBin((if down then ">=" else "<="), iv, local bv it)) tBool
                            let next = mk (CPrim("wrap+", [ iv; local sv it ])) it

                            let lp =
                                loop ctx k [ x, it, a' ] (fun ctx finish ->
                                    mk (CIf(cond, lower ctx body (Then(fun ctx v -> seq' v (finish ctx true [ next ]))), finish ctx false [ iv ])) (roundTy ctx [ it ]))

                            mk (CLet(sv, s', mk (CLet(bv, b', lp)) lp.ty)) lp.ty
                        | _ -> failwith "unreachable")
                | CPerform(l, op, args) ->
                    lowerAtoms ctx args (fun ctx args ->
                        let frame = (framesFor ctx (rowExt l rowEmpty)).Head
                        let ops = opTypes l
                        let o = fresh "$op"
                        let fields = CPWild :: (ops |> List.mapi (fun i t -> if i = op then CPVar(o, t) else CPWild))
                        let opTy = ops[op]
                        let res = evTy e.ty

                        let call =
                            if opIsPolymorphic l op then
                                // its result is its own type: no clause gives one (none resumes)
                                seq' (mk (CApp(local o opTy, args)) tUnit) (mk (CPrim("eff.dummy", [])) res)
                            else
                                mk (CApp(local o opTy, args)) res

                        let body = yieldPoint ctx call k
                        mk (CMatch(frame, [ CPCtor(frameName l, 0, fields), None, body ])) body.ty)
                | CApp(h, args) ->
                    lowerAtoms ctx (h :: args) (fun ctx atoms ->
                        let h' = atoms.Head
                        let call = mk (CApp(h', withEvidence ctx h.ty atoms.Tail)) (evTy e.ty)

                        if rowsOf args.Length h.ty |> List.forall isRowEmpty then give ctx k call else yieldPoint ctx call k)
                | CHandle(l, b, cls, r, rb) -> yieldPoint ctx (handle ctx l b cls r rb (evTy e.ty)) k
                | _ ->
                    // anything else: its parts' values first, in order
                    let parts = children e.k

                    lowerAtoms ctx parts (fun ctx atoms ->
                        let q = Queue<CExpr>(atoms)
                        give ctx k (mk (mapChildren (fun _ -> q.Dequeue()) e.k) (evTy e.ty)))

        /// The type a loop's round gives: whether to go on, then the loop's state (the for loop's
        /// variable, then the mutable variables in scope).
        and roundTy (ctx: Ctx) (xs: Ty list) =
            match xs @ (ctx.muts |> List.map (fun (_, _, t) -> t)) with
            | [] -> tBool
            | ts -> TTuple(tBool :: ts)

        /// A loop with yield points: a round function (the condition and the body once, giving
        /// whether to go on and the new state) and a driver running rounds in a while loop, so no
        /// round's code waits on another's: no stack grows with the rounds, at any optimization.
        /// When a round yields, the driver adds itself to the continuation (resume: the round's
        /// result once it's resumed, then driving on) and returns. round gets the context in the
        /// round and finish (the round's result: going on?, the for variable's next value).
        /// xs: the for loop's variable (its name, type, first value).
        and loop (ctx: Ctx) (k: K) (xs: (string * Ty * CExpr) list) (round: Ctx -> (Ctx -> bool -> CExpr list -> CExpr) -> CExpr) =
            let ms = ctx.muts
            let xtys = xs |> List.map (fun (_, t, _) -> t)
            let stateTys = xtys @ (ms |> List.map (fun (_, _, t) -> t))
            let rty = roundTy ctx xtys
            let roundFn, driveFn, resumeFn, exitFn = fresh "$round", fresh "$drive", fresh "$resume", fresh "$exit"
            let yielding () = mk (CBin("<>", state (), int' 0L)) tBool

            let pack (more: bool) (vals: CExpr list) =
                match vals with
                | [] -> mk (CBool more) tBool
                | _ -> mk (CTuple(mk (CBool more) tBool :: vals)) rty

            // a round: the state as parameters (the mutable variables declared again)
            let inner = ms |> List.map (fun (o, n, t) -> o, fresh n, t)
            let rps = (xs |> List.map (fun (x, t, _) -> x, t)) @ (inner |> List.map (fun (_, n, t) -> n + "p", t))
            let rctx = { ctx with muts = inner; ret = rty }
            let finish (c: Ctx) (more: bool) (next: CExpr list) = pack more (next @ (ms |> List.map (fun (o, _, t) -> local (cur c o) t)))
            let rbody = List.foldBack (fun (_, n, t) acc -> mk (CLetMut(n, local (n + "p") t, acc)) acc.ty) inner (round rctx finish)
            let roundLocal = local roundFn (List.foldBack (fun (_, t) acc -> tfun t acc) rps rty)

            // after the loop: the rest, with the mutable variables' last values
            let outs = ms |> List.map (fun (o, n, t) -> o, fresh n, t)
            let eps = (fresh "$u", tUnit) :: (outs |> List.map (fun (_, n, t) -> n + "p", t))
            let ectx = { ctx with muts = outs }
            let ebody = List.foldBack (fun (_, n, t) acc -> mk (CLetMut(n, local (n + "p") t, acc)) acc.ty) outs (give ectx k unit')
            let exitLocal = local exitFn (List.foldBack (fun (_, t) acc -> tfun t acc) eps ctx.ret)
            let exitWith (mutVals: CExpr list) = mk (CApp(exitLocal, unit' :: mutVals)) ctx.ret

            // the state's parts out of a round's result, then f with them
            let unpack (r: CExpr) (f: CExpr -> CExpr list -> CExpr) =
                match stateTys with
                | [] -> f r []
                | _ ->
                    let more = fresh "$more"
                    let vs = stateTys |> List.map (fun t -> fresh "$s", t)
                    let body = f (local more tBool) (vs |> List.map (fun (v, t) -> local v t))
                    mk (CMatch(r, [ CPTuple(CPVar(more, tBool) :: (vs |> List.map CPVar)), None, body ])) body.ty

            let nx = xs.Length
            let dps = stateTys |> List.map (fun t -> fresh "$st", t)
            let driveTy = List.foldBack (fun (_, t) acc -> tfun t acc) dps ctx.ret
            let driveLocal = local driveFn driveTy
            let contTy = tfun tCPtr rty
            let resumeTy = tfun contTy (tfun tCPtr ctx.ret)

            let extend () =
                let c = fresh "$inner"
                mk (CLet(c, mk (CPrim("eff.takeCont", [])) contTy, mk (CPrim("eff.setCont", [ mk (CApp(local resumeFn resumeTy, [ local c contTy ])) (tfun tCPtr ctx.ret) ])) tUnit)) tUnit

            // the driver: rounds while they go on, the state in mutable variables
            let driveBody =
                let cells = dps |> List.map (fun (p, t) -> fresh "$cell", t, p)
                let go, yielded, r = fresh "$go", fresh "$yielded", fresh "$r"
                let call = mk (CApp(roundLocal, cells |> List.map (fun (c, t, _) -> local c t))) rty
                let rv = local r rty

                let onYield =
                    seq' (mk (CIf(isState 1L, extend (), unit')) tUnit) (seq' (mk (CPrim("eff.forget", [ rv ])) tUnit) (seq' (mk (CAssign(yielded, mk (CBool true) tBool)) tUnit) (mk (CAssign(go, mk (CBool false) tBool)) tUnit)))

                let onRound =
                    unpack rv (fun more vals ->
                        let assigns = List.foldBack2 (fun (c, _, _) (v: CExpr) acc -> seq' (mk (CAssign(c, v)) tUnit) acc) cells vals (mk (CAssign(go, more)) tUnit)
                        assigns)

                let roundOnce = mk (CLet(r, call, mk (CIf(yielding (), onYield, onRound)) tUnit)) tUnit
                let loopCode = mk (CWhile(local go tBool, roundOnce)) tUnit
                let after = mk (CIf(local yielded tBool, mk (CPrim("eff.dummy", [])) ctx.ret, exitWith (cells |> List.skip nx |> List.map (fun (c, t, _) -> local c t)))) ctx.ret
                let body = seq' loopCode after
                let body = mk (CLetMut(go, mk (CBool true) tBool, mk (CLetMut(yielded, mk (CBool false) tBool, body)) ctx.ret)) ctx.ret
                List.foldBack (fun (c, t, p) acc -> mk (CLetMut(c, local p t, acc)) acc.ty) cells body

            // a round resumed: its result, then driving on (or, yielding again, this once more)
            let resumeBody =
                let c, p, y = fresh "$c", fresh "$p", fresh "$y"
                let yv = local y rty
                let resumed = mk (CApp(local c contTy, [ local p tCPtr ])) rty
                let again = seq' (mk (CIf(isState 1L, extend (), unit')) tUnit) (seq' (mk (CPrim("eff.forget", [ yv ])) tUnit) (mk (CPrim("eff.dummy", [])) ctx.ret))
                let goOn = unpack yv (fun more vals -> mk (CIf(more, mk (CApp(driveLocal, vals)) ctx.ret, exitWith (vals |> List.skip nx))) ctx.ret)
                [ c, contTy; p, tCPtr ], mk (CLet(y, resumed, mk (CIf(yielding (), again, goOn)) ctx.ret)) ctx.ret

            let rpars, rb = resumeBody
            let start = mk (CApp(driveLocal, (xs |> List.map (fun (_, _, v) -> v)) @ (ms |> List.map (fun (o, _, t) -> local (cur ctx o) t)))) ctx.ret
            let drive = mk (CLetRec([ driveFn, dps, driveBody; resumeFn, rpars, rb ], start)) ctx.ret
            let withRound = mk (CLetFun(roundFn, false, rps, rbody, drive)) ctx.ret
            mk (CLetFun(exitFn, false, eps, ebody, withRound)) ctx.ret

        /// A body lowered as a function's: its mutable variables under handles boxed first.
        and lowerBody (ctx: Ctx) (b: CExpr) = lower ctx (boxUnderHandles b) Tail

        /// handle body with clauses, as code: a frame for the effect (its marker, a closure per
        /// operation), the body run in a local function with the frame in front of the others,
        /// and its result given to the dispatch, a local function that applies the return
        /// clause, runs the clause of a yield to this marker with the continuation, or adds
        /// itself to the continuation of a yield to another (deep handlers: a resumption is
        /// handled again).
        and handle (ctx: Ctx) (label: Ty) (body: CExpr) cls (rv: string, rt: Ty) (retBody: CExpr) (ansTy: Ty) : CExpr =
            let outer = { ctx with muts = []; joins = Map.empty }
            let bt = evTy rt
            let marker = fresh "$marker"
            let disp = fresh "$dispatch"
            let bodyFn = fresh "$body"
            let frame = fresh "$frame"
            let mv = local marker tInt
            let dispTy = tfun bt ansTy
            let callDisp (v: CExpr) = mk (CApp(local disp dispTy, [ v ])) ansTy
            let contTy = tfun tCPtr bt
            let r = fresh "$res"

            // the dispatch: its own function (its return clause may yield to outer handlers)
            let dispBody =
                let mine =
                    let cp, ck = fresh "$cp", fresh "$ck"
                    let ckTy = tfun tCPtr ansTy

                    mk
                        (CLet(cp, mk (CPrim("eff.takeCont", [])) tCPtr,
                              mk (CLet(ck, mk (CPrim("eff.takeClause", [])) ckTy, mk (CApp(local ck ckTy, [ local cp tCPtr ])) ansTy)) ansTy))
                        ansTy

                let other =
                    let c, p = fresh "$c", fresh "$p"
                    let again = mk (CLam([ p, tCPtr ], callDisp (mk (CApp(local c contTy, [ local p tCPtr ])) bt))) (tfun tCPtr ansTy)
                    let extend = mk (CLet(c, mk (CPrim("eff.takeCont", [])) contTy, mk (CPrim("eff.setCont", [ again ])) tUnit)) tUnit
                    seq' (mk (CIf(isState 1L, extend, unit')) tUnit) (mk (CPrim("eff.dummy", [])) ansTy)

                let returned = lower { outer with ret = ansTy } (mk (CLet(rv, local r bt, boxUnderHandles retBody)) retBody.ty) Tail
                let forget = mk (CPrim("eff.forget", [ local r bt ])) tUnit
                let isMine = mk (CBin("=", mk (CPrim("eff.marker", [])) tInt, mv)) tBool
                mk (CIf(isState 0L, returned, seq' forget (mk (CIf(isMine, mine, other)) ansTy))) ansTy

            // each operation's closure
            let ops = opTypes label

            let opClosure (op: int) (ps: (string * Ty) list) (k: string, kty: Ty) (cbody: CExpr) =
                let opTy = ops[op]
                let ps' = ps |> List.map (fun (x, t) -> x, evTy t)
                let resTy = if opIsPolymorphic label op then tUnit else resultAfter ps.Length opTy

                // a path that doesn't resume gives the handle its answer, by a yield that wants no
                // continuation (the clause, which the dispatch runs, is just that answer)
                let stop (answer: CExpr) =
                    let cp = fresh "$cp"
                    let clause = mk (CLam([ cp, tCPtr ], lowerBody { outer with ret = ansTy } answer)) (tfun tCPtr ansTy)
                    lowered (seq' (mk (CPrim("eff.startFinal", [ mv; clause ])) tUnit) (mk (CPrim("eff.dummy", [])) resTy))

                // a path that does something else with k: a yield to the handle, whose clause is the
                // path with k the resumption (the continuation made on the way there, once)
                let control (path: CExpr) =
                    let cp = fresh "$cp"
                    let ckTy = tfun tCPtr ansTy
                    let cont, cell, v, c = fresh "$cont", fresh "$once", fresh "$v", fresh "$c"
                    let optTy = TCon("option", [ contTy ])
                    let cellTy = TCon("ref", [ optTy ])
                    let some, none = tagOf "option" "Some", tagOf "option" "None"
                    let resumeArgTy = match prune kty with | TFun(a, _, _) -> evTy a | _ -> tUnit
                    let kRow = rowsOf 1 kty |> List.head
                    let kev = labelsOf kRow |> List.map (fun l -> fresh "$ev", frameTy l)
                    let boxed = if prune resumeArgTy = tUnit then mk (CPrim("eff.null", [])) tCPtr else mk (CPrim("eff.box", [ local v resumeArgTy ])) tCPtr

                    let resume =
                        mk
                            (CMatch(
                                mk (CPrim("ref.get", [ local cell cellTy ])) optTy,
                                [ CPCtor("option", some, [ CPVar(c, contTy) ]),
                                  None,
                                  seq' (mk (CPrim("ref.set", [ local cell cellTy; mk (CCtor("option", none, [])) optTy ])) tUnit) (callDisp (mk (CApp(local c contTy, [ boxed ])) bt))
                                  CPCtor("option", none, []), None, mk (CPrim("panic", [ mk (CStr "resumption called twice (one-shot)") tStr ])) ansTy ]
                            ))
                            ansTy

                    let kLam = mk (CLam((v, resumeArgTy) :: kev, resume)) (evTy kty)
                    let withK = mk (CLet(k, kLam, lowerBody { outer with ret = ansTy } path)) ansTy
                    let made = mk (CLet(cell, mk (CPrim("ref", [ mk (CCtor("option", some, [ local cont contTy ])) optTy ])) cellTy, withK)) ansTy
                    let clauseBody = mk (CLet(cont, mk (CPrim("eff.asClosure", [ local cp tCPtr ])) contTy, made)) ansTy
                    let clause = mk (CLam([ cp, tCPtr ], clauseBody)) ckTy
                    let p = fresh "$p"
                    let initial = if prune resTy = tUnit then unit' else mk (CPrim("eff.unbox", [ local p tCPtr ])) resTy
                    let start = mk (CPrim("eff.start", [ mv; clause; mk (CLam([ p, tCPtr ], initial)) (tfun tCPtr resTy) ])) tUnit
                    lowered (seq' start (mk (CPrim("eff.dummy", [])) resTy))

                // runs where it's performed: a path resuming last gives the result, the others
                // stop or yield
                mk (CLam(ps', lowerBody { outer with ret = resTy } (direct k stop control cbody))) opTy

            let closures =
                [ for i in 0 .. ops.Length - 1 ->
                      match cls |> List.tryFind (fun (op, _, _, _) -> op = i) with
                      | Some(_, ps, k, b) -> opClosure i ps k b
                      | None -> failwith "Evidence: a clause missing" ]

            let frameV = local frame (frameTy label)
            let bctx = { ev = withFrame outer.ev label frameV; muts = []; ret = bt; joins = Map.empty }
            let bodyCode = lowerBody bctx body
            let run = callDisp (mk (CApp(local bodyFn (tfun tUnit bt), [ unit' ])) bt)
            let withBody = mk (CLetFun(bodyFn, false, [ fresh "$u", tUnit ], bodyCode, run)) ansTy
            let withFrameV = mk (CLet(frame, mk (CCtor(frameName label, 0, mv :: closures)) (frameTy label), withBody)) ansTy
            let withDisp = mk (CLetRec([ disp, [ r, bt ], dispBody ], withFrameV)) ansTy
            mk (CLet(marker, mk (CPrim("eff.newMarker", [])) tInt, withDisp)) ansTy

        /// A clause's body as the closure performing the operation runs it: each path that resumes
        /// last (k v, k nowhere else on it) as v; each that doesn't mention k given to stop; each
        /// other one (k kept, or used before the end) given to control.
        and direct (k: string) (stop: CExpr -> CExpr) (control: CExpr -> CExpr) (e: CExpr) : CExpr =
            let free (x: CExpr) = not ((freeVars x).Contains k)

            let rec go (e: CExpr) : CExpr =
                match e.k with
                | CApp({ k = CLocal f }, [ v ]) when f = k && free v -> v
                | _ when free e -> stop e
                | CLine(l, a) ->
                    let a' = go a
                    mk (CLine(l, a')) a'.ty
                | CLet(x, v, b) when free v ->
                    let b' = go b
                    mk (CLet(x, v, b')) b'.ty
                | CLetMut(x, v, b) when free v ->
                    let b' = go b
                    mk (CLetMut(x, v, b')) b'.ty
                | CSeq(a, b) when free a ->
                    let b' = go b
                    mk (CSeq(a, b')) b'.ty
                | CIf(c, t, f) when free c ->
                    let t' = go t
                    mk (CIf(c, t', go f)) t'.ty
                | CMatch(s, cases) when free s && cases |> List.forall (fun (_, g, _) -> g |> Option.forall free) ->
                    let cases' = cases |> List.map (fun (p, g, b) -> p, g, go b)
                    let _, _, b0 = cases'.Head
                    mk (CMatch(s, cases')) b0.ty
                | _ -> control e

            if k = "_" then stop e else go e

        /// Mutable variables declared outside a handle and used inside it (its body runs in a
        /// function of its own, its clauses in closures) as ref cells.
        and boxUnderHandles (body: CExpr) : CExpr =
            let mutables = HashSet<string>()
            let boxed = HashSet<string>()

            let rec scan (e: CExpr) =
                match e.k with
                | CLetMut(x, _, _) -> mutables.Add x |> ignore
                | CHandle _ ->
                    for x in freeVars e do
                        if mutables.Contains x then
                            boxed.Add x |> ignore
                | CLam _ -> ()
                | _ -> ()

                match e.k with
                | CLam _ -> () // a function of its own
                | k -> children k |> List.iter scan

            scan body

            if boxed.Count = 0 then
                body
            else
                let rec go (e: CExpr) : CExpr =
                    match e.k with
                    | CLetMut(x, v, b) when boxed.Contains x ->
                        let cellTy = TCon("ref", [ v.ty ])
                        let b' = go b
                        mk (CLet(x, mk (CPrim("ref", [ go v ])) cellTy, b')) b'.ty
                    | CLocal x when boxed.Contains x -> mk (CPrim("ref.get", [ mk (CLocal x) (TCon("ref", [ e.ty ])) ])) e.ty
                    | CAssign(x, v) when boxed.Contains x -> mk (CPrim("ref.set", [ mk (CLocal x) (TCon("ref", [ v.ty ])); go v ])) tUnit
                    | CArraySet(x, i, v) when boxed.Contains x ->
                        // the cell's array with the element changed (copied when shared)
                        let at = TCon("array", [ v.ty ])
                        let cell = mk (CLocal x) (TCon("ref", [ at ]))
                        let changed = mk (CPrim("array.update",[ mk (CPrim("ref.get", [ cell ])) at; go i; go v ])) at
                        mk (CPrim("ref.set", [ cell; changed ])) tUnit
                    | CLam _ -> e
                    | k -> { e with k = mapChildren go k }

                go body

        // the function itself
        let evs = labelsOf f.row |> List.map (fun l -> l, fresh "$ev")
        let ctx = { ev = evs |> List.map (fun (l, x) -> l, local x (frameTy l)); muts = []; ret = evTy f.ret; joins = Map.empty }

        { f with
            pars = (f.pars |> List.map (fun (x, t) -> x, evTy t)) @ (evs |> List.map (fun (l, x) -> x, frameTy l))
            ret = evTy f.ret
            row = rowEmpty
            body = lowerBody ctx f.body }

    try
        funs |> Array.Parallel.map (fun (f, lower) -> if lower then lowerFun f else f) |> List.ofArray
    with :? System.AggregateException as e ->
        raise e.InnerExceptions[0]
