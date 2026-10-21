/// Simplification after inlining. A small function's body copied into its caller often builds a
/// value the caller then takes apart (`match Option.map f o with …`), or applies a lambda the
/// caller passed in. Done at compile time instead, no cell is allocated and no closure built.
///   - Known constructors: a match on a value whose case is known (built right there, bound by
///     a `let`, or taken by an enclosing case) takes its case at compile time.
///   - Case of case: a match on a match (or on an `if`) moves into the inner one's branches,
///     where those that end in a known value take their case at compile time. A case body
///     reached from several branches becomes a join point instead of being copied.
///   - Lambdas: a lambda bound by `let` and only called is applied where it's called.
/// Nothing is evaluated at another time, or more or less often: only matches, branches and
/// bindings move.
module Simplify

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
    sprintf "%s.s%d" x c.Value

/// Node counts, remembered per node (per thread).
let private sizes = new System.Threading.ThreadLocal<Dictionary<CExpr, int>>(fun () -> Dictionary(HashIdentity.Reference))

let rec private size (e: CExpr) =
    match sizes.Value.TryGetValue e with
    | true, n -> n
    | _ ->
        let n = 1 + (children e.k |> List.sumBy size)
        sizes.Value[e] <- n
        n

let rec private renamePat (rn: string -> string) (p: CPat) =
    match p with
    | CPVar(x, t) -> CPVar(rn x, t)
    | CPAs(q, x, t) -> CPAs(renamePat rn q, rn x, t)
    | CPTuple ps -> CPTuple(List.map (renamePat rn) ps)
    | CPRecord(r, fs) -> CPRecord(r, fs |> List.map (fun (n, q) -> n, renamePat rn q))
    | CPCtor(u, tag, ps) -> CPCtor(u, tag, List.map (renamePat rn) ps)
    | CPOr(a, b) -> CPOr(renamePat rn a, renamePat rn b)
    | p -> p

let rec private joinNames (e: CExpr) =
    (match e.k with
     | CJoin(j, _, _, _) -> [ j ]
     | _ -> [])
    @ (children e.k |> List.collect joinNames)

/// e with free variables renamed by m, and with fresh', its binders and join points given new
/// names (a copy for another place: names stay unique per program).
let private rename (m: Map<string, string>) (fresh': bool) (e: CExpr) : CExpr =
    let m =
        if fresh' then
            binders e @ joinNames e |> List.distinct |> List.fold (fun (acc: Map<string, string>) x -> acc.Add(x, fresh x)) m
        else
            m

    if m.IsEmpty then
        e
    else
        let rn x = defaultArg (m.TryFind x) x
        let pars ps = ps |> List.map (fun (x, t) -> rn x, t)

        let rec go (e: CExpr) =
            let k =
                match e.k with
                | CLocal x -> CLocal(rn x)
                | CLam(ps, b) -> CLam(pars ps, go b)
                | CLetFun(n, r, ps, b, rest) -> CLetFun(rn n, r, pars ps, go b, go rest)
                | CLetRec(fs, rest) -> CLetRec(fs |> List.map (fun (n, ps, b) -> rn n, pars ps, go b), go rest)
                | CLet(x, v, b) -> CLet(rn x, go v, go b)
                | CLetMut(x, v, b) -> CLetMut(rn x, go v, go b)
                | CFor(x, a, s, b, body) -> CFor(rn x, go a, go s, go b, go body)
                | CAssign(x, v) -> CAssign(rn x, go v)
                | CArraySet(x, i, v) -> CArraySet(rn x, go i, go v)
                | CMatch(s, cases) -> CMatch(go s, cases |> List.map (fun (p, g, b) -> renamePat rn p, Option.map go g, go b))
                | CJoin(j, ps, b, r) -> CJoin(rn j, pars ps, go b, go r)
                | CJump(j, args) -> CJump(rn j, List.map go args)
                | k -> mapChildren go k

            { e with k = k }

        go e

/// What is known about a variable's value: its case, with the variables holding its fields
/// where they're known, or a literal.
type private Known =
    | KCtor of tag: int * fields: string option list
    | KLit of CPat

/// Whether a pattern matches a known value: yes (binding its variables, with their types, to
/// these variables), no, or it can't be told at compile time.
type private Static =
    | Yes of (string * Ty * string) list
    | No
    | Unknown

/// k: what's known about the value in x (None: nothing); know: what's known about other
/// variables (a constructor's fields).
let rec private staticMatch (know: string -> Known option) (k: Known option) (x: string) (p: CPat) : Static =
    match p with
    | CPWild -> Yes []
    | CPVar(v, t) -> Yes [ v, t, x ]
    | CPAs(q, v, t) ->
        match staticMatch know k x q with
        | Yes bs -> Yes((v, t, x) :: bs)
        | r -> r
    | CPOr(a, b) ->
        match staticMatch know k x a with
        | Yes [] -> Yes []
        | No -> staticMatch know k x b
        | _ -> Unknown
    | _ ->
        match k, p with
        | Some(KCtor(tag', fields)), CPCtor(_, tag, ps) when tag <> tag' || ps.Length = fields.Length ->
            if tag <> tag' then
                No
            else
                // every field must match: one that can't makes the pattern fail
                let parts =
                    List.map2
                        (fun (q: CPat) (f: string option) ->
                            match f, q with
                            | _, CPWild -> Yes []
                            | Some f, _ -> staticMatch know (know f) f q
                            | None, _ -> Unknown)
                        ps
                        fields

                if parts |> List.contains No then No
                elif parts |> List.contains Unknown then Unknown
                else Yes(parts |> List.collect (fun r -> match r with Yes bs -> bs | _ -> []))
        | Some(KLit l), (CPInt _ | CPStr _ | CPBool _) -> if p = l then Yes [] else No
        | _ -> Unknown

let private literal (e: CExpr) =
    match e.k with
    | CInt n -> Some(CPInt n)
    | CBool b -> Some(CPBool b)
    | CStr s -> Some(CPStr s)
    | _ -> None

/// A value whose evaluation has no effect and can't fail, so it can be dropped when unused.
let rec private pureValue (e: CExpr) =
    match e.k with
    | CInt _
    | CFloat _
    | CBool _
    | CStr _
    | CUnit
    | CLocal _
    | CGlobal _
    | CGlobalVal _
    | CLam _ -> true
    | CCtor(_, _, args)
    | CTuple args -> List.forall pureValue args
    | CField(r, _)
    | CLine(_, r) -> pureValue r
    | _ -> false

let rec private lambdaOf (e: CExpr) =
    match e.k with
    | CLam(ps, b) -> Some(ps, b)
    | CLine(_, inner) -> lambdaOf inner
    | _ -> None

/// e with f applied to its children, or e itself when none changes (so what's remembered about
/// it, such as its free variables, still holds).
let private remap (f: CExpr -> CExpr) (e: CExpr) =
    let mutable changed = false

    let k =
        mapChildren
            (fun c ->
                let c' = f c
                if not (obj.ReferenceEquals(c, c')) then changed <- true
                c')
            e.k

    if changed then { e with k = k } else e

/// e rebuilt as k, or e itself when k has the same children.
let private rebuild (e: CExpr) (k: CKind) =
    if List.forall2 (fun (a: CExpr) b -> obj.ReferenceEquals(a, b)) (children e.k) (children k) then e else { e with k = k }

/// The arguments bound to the parameters, in order, around the body.
let private bindArgs (ps: (string * Ty) list) (args: CExpr list) (body: CExpr) =
    List.foldBack2 (fun (p, _) a (acc: CExpr) -> mk (CLet(p, a, acc)) acc.ty) ps args body

let run (types: Dictionary<string, TypeInfo>) (funs: MFun list) : MFun list =
    let fieldTypes (t: Ty) (tag: int) =
        match prune t with
        | TCon(u, args) ->
            match types[u].def with
            | UnionDef cs -> snd cs[tag] |> List.map (substGen args)
            | RecordDef _ -> []
        | _ -> []

    let simplifyFun (f: MFun) =
        counter.Value.Value <- 0
        let freeVars = cachedFreeVars ()
        let uses (x: string) (e: CExpr) = (freeVars e).Contains x
        // variables bound to local functions: a join point can't take one as a parameter (it
        // would become a closure), so a body calling one is copied instead
        let localFuns = HashSet<string>()
        // mutable variables: a field known to be one could have changed when it's read
        let mutables = HashSet<string>()

        let rec collect (e: CExpr) =
            match e.k with
            | CLetFun(n, _, _, _, _) -> localFuns.Add n |> ignore
            | CLetRec(fs, _) ->
                for n, _, _ in fs do
                    localFuns.Add n |> ignore
            | CLetMut(x, _, _) -> mutables.Add x |> ignore
            | _ -> ()

            children e.k |> List.iter collect

        collect f.body

        let immutable (a: CExpr) =
            match a.k with
            | CLocal y when not (mutables.Contains y) -> Some y
            | _ -> None

        // each rewrite that builds more code to simplify uses fuel, so the pass always ends
        let mutable fuel = 100 + 4 * size f.body

        let burn () =
            fuel <- fuel - 1
            fuel > 0

        /// Every use of x in e is a call with n arguments: how many there are (None otherwise).
        let callsOnly (x: string) (n: int) (e: CExpr) =
            let mutable calls = 0
            let mutable other = false

            let rec walk (e: CExpr) =
                match e.k with
                | CApp({ k = CLocal y }, args) when y = x ->
                    if args.Length = n then calls <- calls + 1 else other <- true
                    List.iter walk args
                | CLocal y when y = x -> other <- true
                | k -> children k |> List.iter walk

            walk e
            if other then None else Some calls

        /// e with each call to x (a lambda's name) replaced by the lambda's body, its parameters
        /// bound to the arguments; a copy for every call but the last.
        let applyAt (x: string) (lam: CExpr) (e: CExpr) =
            let mutable left = defaultArg (callsOnly x (List.length (fst (lambdaOf lam).Value)) e) 0

            let rec go (e: CExpr) =
                match e.k with
                | CApp({ k = CLocal y }, args) when y = x ->
                    let args = List.map go args
                    left <- left - 1
                    let ps, b = (lambdaOf (if left = 0 then lam else rename Map.empty true lam)).Value
                    bindArgs ps args b
                | k -> { e with k = mapChildren go k }

            go e

        // nodes simplified already: moved into a new place (case of case), they aren't gone through
        // again, so the pass stays linear in what it builds
        let finished = HashSet<CExpr>(HashIdentity.Reference)

        let rec simp (env: Map<string, Known>) (e: CExpr) : CExpr =
            if finished.Contains e then
                e
            else
                let r = simp' env e
                finished.Add r |> ignore
                r

        and simp' (env: Map<string, Known>) (e: CExpr) : CExpr =
            match e.k with
            | CLet(x, v, body) ->
                let v = simp env v

                match lambdaOf v with
                | Some(ps, lb) when (match callsOnly x ps.Length body with
                                     | Some n -> n = 1 || (n > 1 && size lb <= 40)
                                     | None -> false)
                                    && burn () -> simp env (applyAt x v body)
                | _ ->
                    // let x = v in match x with … (or through let y = x, as an inlined call binds its
                    // parameters), where v is a match or an if: case of case
                    let rec matchOnX (names: Set<string>) (b: CExpr) =
                        match b.k with
                        | CMatch({ k = CLocal y }, cases) when names.Contains y ->
                            if cases |> List.exists (fun (_, g, b) -> names |> Set.exists (fun n -> uses n b || g |> Option.exists (uses n))) then None else Some cases
                        | CLet(y, { k = CLocal z }, rest) when names.Contains z -> matchOnX (names.Add y) rest
                        | CLine(_, inner) -> matchOnX names inner
                        | _ -> None

                    match matchOnX (Set.singleton x) body, v.k with
                    | Some cases, _ when (plan env v cases false).IsSome && burn () -> simp env (mk (CMatch(v, cases)) e.ty)
                    | _, CCtor(u, tag, args) when args |> List.exists (fun a -> (match a.k with CLocal _ -> false | _ -> true)) && burn () ->
                        // the fields named, so a match on x knows them
                        let named = args |> List.map (fun a -> match a.k with CLocal _ -> a, None | _ -> (let t = fresh "$f" in mk (CLocal t) a.ty, Some(t, a)))
                        let inner = mk (CLet(x, mk (CCtor(u, tag, List.map fst named)) v.ty, body)) e.ty
                        simp env (List.foldBack (fun (_, b) (acc: CExpr) -> match b with Some(t, a) -> mk (CLet(t, a, acc)) acc.ty | None -> acc) named inner)
                    | _ ->
                        let env' =
                            match v.k with
                            | CCtor(_, tag, args) -> env.Add(x, KCtor(tag, List.map immutable args))
                            | CLocal y when env.ContainsKey y -> env.Add(x, env[y])
                            | _ ->
                                match literal v with
                                | Some l -> env.Add(x, KLit l)
                                | None -> env

                        let body = simp env' body

                        // the body may have become such a match only now
                        match matchOnX (Set.singleton x) body with
                        | Some cases when (plan env v cases false).IsSome && burn () -> simp env (mk (CMatch(v, cases)) e.ty)
                        | _ -> if pureValue v && not (uses x body) then body else rebuild e (CLet(x, v, body))
            | CMatch(s, cases) -> matchOf env (Some e) (simp env s) cases e.ty
            | CIf(c, t, f) ->
                let c = simp env c
                let asMatch = [ CPBool true, None, t; CPWild, None, f ]

                match c.k with
                | CBool b -> simp env (if b then t else f)
                | CLocal x when env.ContainsKey x -> matchOn env c asMatch e.ty
                | CLocal x -> rebuild e (CIf(c, simp (env.Add(x, KLit(CPBool true))) t, simp (env.Add(x, KLit(CPBool false))) f))
                | _ ->
                    match (if fuel > 0 then caseOfCase env c asMatch e.ty true else None) with
                    | Some r when burn () -> simp env r
                    | _ -> rebuild e (CIf(c, simp env t, simp env f))
            | CApp(h, args) ->
                let h = simp env h
                let args = List.map (simp env) args

                match lambdaOf h with
                | Some(ps, b) when ps.Length = args.Length -> simp env (bindArgs ps args b)
                | _ -> rebuild e (CApp(h, args))
            | CSeq(a, b) ->
                let a = simp env a
                let b = simp env b
                if pureValue a then b else rebuild e (CSeq(a, b))
            | _ -> remap (simp env) e

        and matchOn env (s: CExpr) cases (ty: Ty) : CExpr = matchOf env None s cases ty

        and matchOf env (orig: CExpr option) (s: CExpr) cases (ty: Ty) : CExpr =
            match s.k with
            | CLocal x when env.ContainsKey x ->
                match select env x s.ty cases ty with
                | Some r -> simp env r
                | None -> plain env s cases ty
            | CCtor(u, tag, args) when burn () ->
                // the fields bound in order, and the value, then the match is on a known variable
                let temps =
                    args
                    |> List.map (fun a ->
                        match immutable a with
                        | Some v -> v, None
                        | None -> fresh "$f", Some a)

                let v = fresh "$k"
                let value = mk (CCtor(u, tag, List.map2 (fun (a: CExpr) (t, _) -> mk (CLocal t) a.ty) args temps)) s.ty
                let inner = mk (CLet(v, value, mk (CMatch(mk (CLocal v) s.ty, cases)) ty)) ty

                List.foldBack2
                    (fun (t, a) (arg: CExpr) acc ->
                        match a with
                        | Some a -> mk (CLet(t, a, acc)) ty
                        | None -> acc)
                    temps
                    args
                    inner
                |> simp env
            | _ when (literal s).IsSome && burn () ->
                let v = fresh "$k"
                simp env (mk (CLet(v, s, mk (CMatch(mk (CLocal v) s.ty, cases)) ty)) ty)
            | _ ->
                match (if fuel > 0 then caseOfCase env s cases ty false else None) with
                | Some r when burn () -> simp env r
                | _ -> plainOf env orig s cases ty

        /// The match as it is, each case knowing what it took.
        and plain env (s: CExpr) cases (ty: Ty) = plainOf env None s cases ty

        and plainOf env (orig: CExpr option) (s: CExpr) cases (ty: Ty) =
            let caseEnv (p: CPat) =
                match s.k, p with
                | CLocal x, CPCtor(_, tag, ps) ->
                    env.Add(
                        x,
                        KCtor(
                            tag,
                            ps
                            |> List.map (fun q ->
                                match q with
                                | CPVar(v, _)
                                | CPAs(_, v, _) -> Some v
                                | _ -> None)
                        )
                    )
                | CLocal x, (CPInt _ | CPStr _ | CPBool _) -> env.Add(x, KLit p)
                | _ -> env

            match cases with
            | [ CPBool true, None, t; CPWild, None, f ] ->
                let envT, envF =
                    match s.k with
                    | CLocal x -> env.Add(x, KLit(CPBool true)), env.Add(x, KLit(CPBool false))
                    | _ -> env, env

                mk (CIf(s, simp envT t, simp envF f)) ty
            | _ ->
                let cases' = cases |> List.map (fun (p, g, b) -> (let env' = caseEnv p in p, Option.map (simp env') g, simp env' b))
                let same (a: CExpr) (b: CExpr) = obj.ReferenceEquals(a, b)

                let unchanged =
                    List.forall2
                        (fun (_, g, b) (_, g', b') ->
                            same b b'
                            && (match g, g' with
                                | Some g, Some g' -> same g g'
                                | _ -> true))
                        cases
                        cases'

                match orig with
                | Some o when unchanged && (match o.k with
                                            | CMatch(s0, _) -> same s0 s
                                            | _ -> false) -> o
                | _ -> mk (CMatch(s, cases')) ty

        /// The cases a value known to be k takes at compile time: the body of the first case it
        /// matches, a test of its guard, or (where a case can't be told) the cases left. None
        /// when nothing is decided.
        and select env (x: string) (xty: Ty) cases (ty: Ty) : CExpr option =
            let rec go cases (dropped: bool) =
                match cases with
                | [] -> None
                | (p, g, b) :: rest ->
                    match staticMatch (fun v -> Map.tryFind v env) (Map.tryFind x env) x p with
                    | No -> go rest true
                    | Yes binds ->
                        // the pattern's variables bound to what they match (the guard can't
                        // see the other cases, so the bindings may enclose them)
                        let bind (e: CExpr) = List.foldBack (fun (v, t, f) (acc: CExpr) -> mk (CLet(v, mk (CLocal f) t, acc)) acc.ty) binds e

                        match g with
                        | None -> Some(bind b)
                        | Some g ->
                            let otherwise =
                                match go rest true with
                                | Some e -> e
                                | None -> mk (CMatch(mk (CLocal x) xty, rest)) ty

                            Some(bind (mk (CIf(g, b, otherwise)) ty))
                    | Unknown ->
                        match fieldMatch env x xty cases ty with
                        | Some e -> Some e
                        | None -> if dropped then Some(mk (CMatch(mk (CLocal x) xty, cases)) ty) else None

            go cases false

        /// A match on a value whose case is known, with patterns that test inside its fields:
        /// the same match on the fields themselves, so the value needn't exist.
        and fieldMatch env (x: string) (xty: Ty) cases (ty: Ty) : CExpr option =
            match Map.tryFind x env with
            | Some(KCtor(tag, fields)) when not fields.IsEmpty && fields |> List.forall Option.isSome ->
                let fs = List.map Option.get fields
                let ftys = fieldTypes xty tag
                let wild = fs |> List.map (fun _ -> CPWild)
                // a variable for the whole value: the guard renamed, the body binding it
                let whole v vt (g: CExpr option) (b: CExpr) =
                    Option.map (rename (Map.ofList [ v, x ]) false) g, mk (CLet(v, mk (CLocal x) vt, b)) b.ty

                let rec conv (p: CPat, g: CExpr option, b: CExpr) =
                    match p with
                    | CPCtor(_, t, ps) -> Some(if t = tag then Some(ps, g, b) else None)
                    | CPWild -> Some(Some(wild, g, b))
                    | CPVar(v, vt) ->
                        let g, b = whole v vt g b
                        Some(Some(wild, g, b))
                    | CPAs(q, v, vt) ->
                        let g, b = whole v vt g b
                        conv (q, g, b)
                    | _ -> None

                let converted = List.map conv cases

                if converted |> List.exists Option.isNone || ftys.Length <> fs.Length then
                    None
                else
                    let cs = converted |> List.choose id |> List.choose id
                    let locals = List.map2 (fun f t -> mk (CLocal f) t) fs ftys

                    match locals with
                    | [ one ] -> Some(mk (CMatch(one, cs |> List.map (fun (ps, g, b) -> List.head ps, g, b))) ty)
                    | _ -> Some(mk (CMatch(mk (CTuple locals) (TTuple ftys), cs |> List.map (fun (ps, g, b) -> CPTuple ps, g, b))) ty)
            | _ -> None

        /// Case of case, if a path of s ends in a value the match resolves: the match moved into
        /// each path of s.
        and caseOfCase env (s: CExpr) cases (ty: Ty) (isIf: bool) : CExpr option = pushed env s cases isIf

        /// Whether case of case applies: how many paths of s reach each case, and the cases'
        /// bodies; None when no path ends in a value the match resolves.
        and plan env (s: CExpr) cases (isIf: bool) : (int[] * (CPat * CExpr option * CExpr)[]) option =
            // the value s ends with on each path (a local function's or mutable's scope isn't entered)
            let rec tails (e: CExpr) =
                match e.k with
                | CLet(_, _, b)
                | CSeq(_, b)
                | CLine(_, b) -> tails b
                | CIf(_, t, f) -> tails t @ tails f
                | CMatch(_, cs) -> cs |> List.collect (fun (_, _, b) -> tails b)
                | _ -> [ e ]

            let shape (t: CExpr) : Known option =
                match t.k with
                | CCtor(_, tag, args) -> Some(KCtor(tag, args |> List.map (fun _ -> Some "$")))
                | CLocal y -> env.TryFind y
                | _ -> literal t |> Option.map KLit

            let n = List.length cases

            // the cases each path can take
            let reach (t: CExpr) : int list =
                match shape t with
                | None -> [ 0 .. n - 1 ]
                | Some k ->
                    let rec go i cs =
                        match cs with
                        | [] -> []
                        | (p, g: CExpr option, _) :: rest ->
                            match staticMatch (fun v -> Map.tryFind v env) (Some k) "$" p with
                            | No -> go (i + 1) rest
                            | Yes _ when g.IsNone -> [ i ]
                            | Yes _ -> i :: go (i + 1) rest
                            | Unknown -> [ i .. n - 1 ]

                    go 0 cases

            let ts = tails s

            match ts with
            | [ t ] when obj.ReferenceEquals(t, s) -> None // no paths inside s to move into
            | _ when ts |> List.forall (fun t -> (shape t).IsNone) -> None
            | _ ->
                let uses = Array.zeroCreate n

                for t in ts do
                    for i in reach t do
                        uses[i] <- uses[i] + 1

                let caseArr = Array.ofList cases

                // a body reached more than once: copied when small, else a join point, which
                // takes the pattern's variables and whatever else the body reads
                let shared i = uses[i] > 1 && (let _, _, b = caseArr[i] in size b > 16)

                let joinable i =
                    let p, _, b = caseArr[i]
                    let own = Set.ofList (binders b @ (patVars p |> List.map fst))

                    let rec assigns (e: CExpr) =
                        match e.k with
                        | CAssign(y, _)
                        | CArraySet(y, _, _) when not (own.Contains y) -> true
                        | k -> children k |> List.exists assigns

                    not (assigns b) && not ((freeVars b) |> Set.exists localFuns.Contains)

                if (isIf && Array.exists (fun u -> u > 1) uses) || (List.init n id |> List.exists (fun i -> shared i && not (joinable i))) then
                    None
                else
                    Some(uses, caseArr)

        /// Case of case: the match moved into each path of s, with join points for the bodies
        /// reached on several paths.
        and pushed env (s: CExpr) cases (isIf: bool) : CExpr option =
            match plan env s cases isIf with
            | None -> None
            | Some(uses, caseArr) ->
                    let n = caseArr.Length
                    let shared i = uses[i] > 1 && (let _, _, b = caseArr[i] in size b > 16)
                    let joins = ResizeArray<string * (string * Ty) list * CExpr>()

                    let jumps =
                        [ for i in 0 .. n - 1 do
                              if shared i then
                                  let p, _, b = caseArr[i]
                                  let pvs = patVars p
                                  let fv = freeVars b
                                  let names = Set.ofList (List.map fst pvs)
                                  let outer = refs b |> List.filter (fun (x, _) -> fv.Contains x && not (names.Contains x)) |> List.distinctBy fst
                                  let ps = (pvs @ outer) |> List.map (fun (x, t) -> x, fresh x, t)
                                  let j = fresh "$join"
                                  joins.Add(j, ps |> List.map (fun (_, x', t) -> x', t), rename (ps |> List.map (fun (x, x', _) -> x, x') |> Map.ofList) false b)
                                  yield i, (j, pvs, outer) ]
                        |> Map.ofList

                    let copies = Array.zeroCreate n

                    // the cases for one path: the first copy of a body keeps its names
                    let instance () =
                        caseArr
                        |> Array.mapi (fun i (p, g, b) ->
                            match jumps.TryFind i with
                            | Some(j, pvs, outer) ->
                                let m = pvs |> List.map (fun (x, _) -> x, fresh x) |> Map.ofList
                                let args = (pvs |> List.map (fun (x, t) -> mk (CLocal m[x]) t)) @ (outer |> List.map (fun (x, t) -> mk (CLocal x) t))
                                renamePat (fun x -> defaultArg (m.TryFind x) x) p, g |> Option.map (rename m true), mk (CJump(j, args)) b.ty
                            | None when copies[i] = 0 ->
                                copies[i] <- 1
                                p, g, b
                            | None ->
                                let m = patVars p |> List.map (fun (x, _) -> x, fresh x) |> Map.ofList
                                renamePat (fun x -> defaultArg (m.TryFind x) x) p, g |> Option.map (rename m true), rename m true b)
                        |> List.ofArray

                    let ty = (let _, _, b = caseArr[0] in b.ty)

                    let rec into (e: CExpr) =
                        match e.k with
                        | CLet(x, v, b) -> mk (CLet(x, v, into b)) ty
                        | CSeq(a, b) -> mk (CSeq(a, into b)) ty
                        | CLine(l, b) -> mk (CLine(l, into b)) ty
                        | CIf(c, t, f) -> mk (CIf(c, into t, into f)) ty
                        | CMatch(s2, cs) -> mk (CMatch(s2, cs |> List.map (fun (p, g, b) -> p, g, into b))) ty
                        | _ -> mk (CMatch(e, instance ())) ty

                    let body = into s
                    Some(Seq.foldBack (fun (j, ps, b) (acc: CExpr) -> mk (CJoin(j, ps, b, acc)) ty) joins body)

        let body = simp Map.empty f.body
        sizes.Value.Clear()
        { f with body = body }

    // each function on its own, on every core
    try
        funs |> Array.ofList |> Array.Parallel.map simplifyFun |> List.ofArray
    with :? System.AggregateException as e ->
        raise e.InnerExceptions[0]
