/// Perceus reference counting (Reinking, Xie, de Moura, Leijen; PLDI 2021), base algorithm:
/// precise ownership. Every owned variable is consumed exactly once on every path: moved into
/// its last use, dup'ed before earlier uses, and dropped as soon as it is dead (at the start of
/// a branch that does not use it). Function arguments are owned by the callee; a closure being
/// applied is borrowed. Pattern variables borrow from the scrutinee and are dup'ed when used.
module Rc

open Core
open Mono

/// entries: the functions called from outside (main, C exports), which own their parameters.
/// The variable a value is, or a field (of a field…) of: what a read through it borrows.
let rec private rootLocal (e: CExpr) =
    match e.k with
    | CLocal x -> Some x
    | CField(r, _) -> rootLocal r
    | _ -> None

/// A function's body with the parameters of its join points that are its own parameters gone:
/// where every jump to a join point passes the same parameter of the function from `keep` (one
/// it borrows) in a place, the join point's body uses that parameter itself, which outlives it,
/// so no jump dups it to pass it.
let private elideAliases (keep: string -> bool) (body: CExpr) : CExpr =
    let passed = System.Collections.Generic.Dictionary<string, string option array>()

    let rec scan (e: CExpr) =
        match e.k with
        | CJump(j, args) ->
            let here = args |> List.map (fun a -> match a.k with CLocal x when keep x -> Some x | _ -> None) |> Array.ofList

            match passed.TryGetValue j with
            | true, before -> passed[j] <- Array.map2 (fun a b -> if a = b then a else None) before here
            | _ -> passed[j] <- here
        | _ -> ()

        children e.k |> List.iter scan

    scan body
    let elided (j: string) = passed.ContainsKey j && Array.exists Option.isSome passed[j]

    if not (passed.Keys |> Seq.exists elided) then
        body
    else
        let rec subst (m: Map<string, string>) (e: CExpr) =
            match e.k with
            | CLocal x when m.ContainsKey x -> { e with k = CLocal m[x] }
            | k -> { e with k = mapChildren (subst m) k }

        let rec go (e: CExpr) =
            match e.k with
            | CJoin(j, ps, b, rest) when elided j ->
                let slots = passed[j]
                let m = ps |> List.indexed |> List.choose (fun (i, (q, _)) -> slots[i] |> Option.map (fun x -> q, x)) |> Map.ofList
                let ps' = ps |> List.indexed |> List.filter (fun (i, _) -> slots[i].IsNone) |> List.map snd
                { e with k = CJoin(j, ps', go (subst m b), go rest) }
            | CJump(j, args) when elided j ->
                let slots = passed[j]
                { e with k = CJump(j, args |> List.indexed |> List.filter (fun (i, _) -> slots[i].IsNone) |> List.map (snd >> go)) }
            | k -> { e with k = mapChildren go k }

        go body

/// Borrowed parameters (Perceus borrowing), each function's indices: a heap parameter the
/// function only applies, reads (a.[i], lengths, a record's fields) or passes on to a borrowed
/// parameter is borrowed. The caller keeps ownership and the callee neither dups nor drops it, so a closure
/// or array threaded through a loop costs no reference counting. Only for functions called
/// directly (not closures, which are called through code pointers, nor the entries). For the
/// whole program, since a caller's code depends on its callees'.
/// external: what another module's code borrows (its functions aren't in funs).
let borrowingWith
    (types: System.Collections.Generic.Dictionary<string, TypeInfo>)
    (entries: Set<string>)
    (external: string -> Set<int> option)
    (funs: MFun list)
    =
    let heap t = needsRc types t
    let asValues = System.Collections.Generic.HashSet<string>(entries)

    let rec values (e: CExpr) =
        match e.k with
        | CMkClosure(n, _) -> asValues.Add n |> ignore
        | CPrim(op, _) when op.StartsWith "fn:" -> asValues.Add(op.Substring 3) |> ignore // in a vtable
        | _ -> ()

        children e.k |> List.iter values

    for f in funs do
        values f.body

    let borrowedOf = System.Collections.Generic.Dictionary<string, Set<int>>()

    for f in funs do
        if not (asValues.Contains f.name) then
            borrowedOf[f.name] <- f.pars |> List.indexed |> List.filter (fun (_, (_, t)) -> heap t) |> List.map fst |> Set.ofList

    let fnOf = funs |> List.map (fun f -> f.name, f) |> dict
    let mutable changed = true

    // each round on every core, from the sets of the round before: they only shrink, so the
    // rounds end at the same sets in any order
    while changed do
        let fewer (name: string, set: Set<int>) =
            // the parameters of the set the body uses in other ways, in one walk
            let f = fnOf[name]
            let index = set |> Seq.map (fun i -> fst f.pars[i], i) |> dict
            let bad = System.Collections.Generic.HashSet<int>()

            let rec walk (e: CExpr) =
                match e.k with
                | CLocal x when index.ContainsKey x -> bad.Add index[x] |> ignore
                // a field read dups the field: the record itself stays the caller's
                | CField({ k = CLocal x }, _) when index.ContainsKey x -> ()
                | CApplyClo({ k = CLocal x }, args) when index.ContainsKey x -> List.iter walk args
                | CPrim(("array.get" | "Array.length" | "String.length" | "String.byte" | "fixed.get" | "fixed.length" | "ref.get" | "ref.set"), { k = CLocal x } :: rest) when index.ContainsKey x ->
                    List.iter walk rest
                | CCallDirect(g, args) ->
                    args
                    |> List.iteri (fun j a ->
                        match a.k with
                        | CLocal x when index.ContainsKey x ->
                            let once = (args |> List.filter (fun b -> b.k = CLocal x)).Length = 1

                            let bs =
                                match borrowedOf.TryGetValue g with
                                | true, bs -> Some bs
                                | _ -> if fnOf.ContainsKey g then None else external g

                            match bs with
                            | Some bs when once && bs.Contains j -> ()
                            | _ -> bad.Add index[x] |> ignore
                        | _ -> walk a)
                | CAssign(x, _)
                | CArraySet(x, _, _) when index.ContainsKey x ->
                    bad.Add index[x] |> ignore
                    children e.k |> List.iter walk
                | k -> children k |> List.iter walk

            if not set.IsEmpty then
                walk (elideAliases index.ContainsKey f.body)

            if bad.Count > 0 then Some(name, set - Set.ofSeq bad) else None

        let updates = borrowedOf |> Seq.map (fun kv -> kv.Key, kv.Value) |> Array.ofSeq |> Array.Parallel.choose fewer
        changed <- updates.Length > 0

        for name, set in updates do
            borrowedOf[name] <- set

    borrowedOf

let borrowing types (entries: Set<string>) (funs: MFun list) = borrowingWith types entries (fun _ -> None) funs

/// Reference counting for funs, with the program's borrowed parameters (borrowing).
let lower (types: System.Collections.Generic.Dictionary<string, TypeInfo>) (borrowedParams: System.Collections.Generic.Dictionary<string, Set<int>>) (funs: MFun list) : MFun list =
    let heap t = needsRc types t
    let mk k ty = { k = k; ty = ty }
    // temporaries numbered per function (each thread does one at a time): a function's code
    // doesn't depend on the others'
    let count = new System.Threading.ThreadLocal<int ref>(fun () -> ref 0)

    let next () =
        let c = count.Value
        c.Value <- c.Value + 1
        c.Value

    let tmp () = sprintf "$rc%d" (next ())

    /// print/println of a string built with + (an interpolation, usually) prints the pieces
    /// instead of joining them: no concatenation, no allocation. Every piece is evaluated first,
    /// in order, as before, so output and panics happen exactly as they did.
    let rec printPieces (e: CExpr) : CExpr =
        let isString (e: CExpr) =
            match prune e.ty with
            | TCon("string", []) -> true
            | _ -> false

        let rec flatten (e: CExpr) =
            match e.k with
            | CBin(("+" | "wrap+"), a, b) when isString a -> flatten a @ flatten b
            | _ -> [ e ]

        match e.k with
        | CPrim(("print" | "println") as op, [ ({ k = CBin(("+" | "wrap+"), a, _) } as arg) ]) when isString a ->
            let temps = flatten arg |> List.map (fun p -> tmp (), printPieces p)
            let last = temps.Length - 1

            let prints =
                temps
                |> List.mapi (fun i (t, p) -> mk (CPrim((if i = last then op else "print"), [ mk (CLocal t) p.ty ])) tUnit)
                |> List.reduce (fun a b -> mk (CSeq(a, b)) tUnit)

            List.foldBack (fun (t, p) acc -> mk (CLet(t, p, acc)) tUnit) temps prints
        | k -> mk (mapChildren printPieces k) e.ty

    // ---- re-matching: in `match x with C (a, b) -> if c then f a else x`, x stays alive for the
    // branch that returns it, so its drop can't be specialized for the whole case. Each branch
    // where x dies matches it again (a known constructor), so that branch takes the cell apart
    // itself: the fields move out without a dup, and the cell can be reused.
    let rematch (body: CExpr) : CExpr =
        let rec renameVars (m: Map<string, string>) (e: CExpr) : CExpr =
            match e.k with
            | CLocal x when m.ContainsKey x -> { e with k = CLocal m[x] }
            | k -> { e with k = mapChildren (renameVars m) k }

        let single (fps: CPat list) =
            fps
            |> List.forall (fun fp ->
                match fp with
                | CPVar _
                | CPWild -> true
                | _ -> false)

        let rec go (e: CExpr) : CExpr =
            let e = { e with k = mapChildren go e.k }

            match e.k with
            | CMatch(({ k = CLocal x } as s), cases) when heap s.ty && not (plainUnion types s.ty) ->
                let cases' =
                    cases
                    |> List.map (fun (p, g, b) ->
                        match p with
                        | CPCtor(u, tag, fps) when not fps.IsEmpty && single fps && (freeVars b).Contains x -> p, g, push s x u tag fps b
                        | _ -> p, g, b)

                { e with k = CMatch(s, cases') }
            | _ -> e

        // the branches of b where x (the scrutinee s) dies match it again; where x is used, b is
        // left as it is
        and push (s: CExpr) (x: string) u tag (fps: CPat list) (b: CExpr) : CExpr =
            let uses (e: CExpr) = (freeVars e).Contains x
            let branch (br: CExpr) = if uses br then push s x u tag fps br else again s u tag fps br

            match b.k with
            | CIf(c, t, f) when not (uses c) -> { b with k = CIf(c, branch t, branch f) }
            | CLet(v, e, rest) when not (uses e) -> { b with k = CLet(v, e, push s x u tag fps rest) }
            | CLine(l, inner) -> { b with k = CLine(l, push s x u tag fps inner) }
            | CMatch(s2, cases) when not (uses s2) && cases |> List.forall (fun (_, g, _) -> not (g |> Option.exists uses)) ->
                { b with k = CMatch(s2, cases |> List.map (fun (p, g, br) -> p, g, branch br)) }
            | _ -> b

        // match s again, with fresh names for the fields br uses
        and again (s: CExpr) u tag (fps: CPat list) (br: CExpr) : CExpr =
            let fv = freeVars br

            let fps', pairs =
                fps
                |> List.map (fun fp ->
                    match fp with
                    | CPVar(v, t) when fv.Contains v ->
                        let v' = sprintf "%s.r%d" v (next ())
                        CPVar(v', t), Some(v, v')
                    | _ -> CPWild, None)
                |> List.unzip

            let m = pairs |> List.choose id |> Map.ofList
            mk (CMatch(s, [ CPCtor(u, tag, fps'), None, renameVars m br ])) br.ty

        go body

    let rcFun (f: MFun) =
        count.Value.Value <- 0

        let mine =
            match borrowedParams.TryGetValue f.name with
            | true, bs -> bs
            | _ -> Set.empty

        let lent = f.pars |> List.indexed |> List.filter (fun (i, _) -> mine.Contains i) |> List.map (snd >> fst) |> Set.ofList
        let f = { f with body = elideAliases lent.Contains (rematch (printPieces f.body)) }
        let freeVars = cachedFreeVars ()
        // every variable's type, by unique name
        let vtypes = System.Collections.Generic.Dictionary<string, Ty>()

        for x, t in f.pars do
            vtypes[x] <- t

        let rec collect (e: CExpr) =
            match e.k with
            | CLet(x, v, _)
            | CLetMut(x, v, _) -> vtypes[x] <- v.ty
            | CFor(x, a, _, _, _) -> vtypes[x] <- a.ty
            | CJoin(_, ps, _, _) ->
                for x, t in ps do
                    vtypes[x] <- t
            | CMatch(_, cases) ->
                for p, _, _ in cases do
                    for x, t in patVars p do
                        vtypes[x] <- t
            | _ -> ()

            children e.k |> List.iter collect

        collect f.body

        let mutables =
            let rec go (e: CExpr) =
                (match e.k with
                 | CLetMut(x, _, _) -> [ x ]
                 | _ -> [])
                @ (children e.k |> List.collect go)

            Set.ofList (go f.body)

        let heapVar x = heap vtypes[x]

        // a task's state machine (task.suspend, task.abandon): what's held across a wait, which a
        // cancelled task drops when its coroutine is destroyed there. held: the owned variables
        // the code after the current subexpression consumes; muts: the heap `mutable`s in scope
        let held = ref Set.empty
        let muts = ref Set.empty

        let holding (extra: Set<string>) (f: unit -> CExpr) =
            let saved = held.Value
            held.Value <- Set.union saved extra

            try
                f ()
            finally
                held.Value <- saved

        /// The layout of the cell a constructor builds (or a matched case is): with a tag?, and
        /// the field types. None when the case isn't a cell (no fields, or a niche).
        let layoutOf (t: Ty) tag (fields: Ty list) =
            cellShape types t tag |> Option.map (fun (tagged, _) -> tagged, fields)

        let fieldTypes (t: Ty) tag =
            match prune t with
            | TCon(u, args) ->
                match types[u].def with
                | UnionDef cs -> snd cs[tag] |> List.map (substGen args)
                | RecordDef _ -> []
            | _ -> []

        // join points whose body builds a cell: their reuse-token parameter and the cell's layout
        let joinTok = System.Collections.Generic.Dictionary<string, string * (bool * Ty list)>()
        let tokenTy = tcon "cptr"

        /// Rewrites one constructor with the given field layout, on every path of e that ends in
        /// one, to build in the token's cell; paths without one free the token. None = no site.
        let rec place (tok: string) (layout: bool * Ty list) (e: CExpr) : CExpr option =
            let re k = Some(mk k e.ty)
            let free (b: CExpr) = mk (CFreeToken(tok, b)) b.ty

            match e.k with
            | CCtor(u, tag, args) when heap e.ty && layoutOf e.ty tag (args |> List.map (fun a -> a.ty)) = Some layout -> re (CCtorAt(tok, u, tag, args))
            | CWhile _
            | CFor _ -> None // runs repeatedly
            | CJump(j, args) ->
                // a jump to a join point that builds a cell alike passes the token on, unless
                // the jump passes another token already
                let free' =
                    match (List.last args).k with
                    | CPrim("token.null", _) -> true
                    | _ -> false

                match joinTok.TryGetValue j with
                | true, (_, l) when l = layout && free' -> re (CJump(j, List.take (args.Length - 1) args @ [ mk (CLocal tok) tokenTy ]))
                | _ -> None
            | CJoin(j, ps, body, rest) -> place tok layout rest |> Option.map (fun r -> mk (CJoin(j, ps, body, r)) e.ty) // the token isn't in the body's scope
            | CIf(c, t, f) ->
                match place tok layout t, place tok layout f with
                | None, None -> None
                | t', f' -> re (CIf(c, defaultArg t' (free t), defaultArg f' (free f)))
            | CMatch(s, cases) ->
                let placed = cases |> List.map (fun (p, g, b) -> p, g, b, place tok layout b)

                if placed |> List.forall (fun (_, _, _, b) -> b.IsNone) then
                    None
                else
                    re (CMatch(s, placed |> List.map (fun (p, g, b, b') -> p, g, defaultArg b' (free b))))
            | k ->
                // every other node evaluates each child exactly once: use the first child that can
                let found = ref false

                let k' =
                    k
                    |> mapChildren (fun c ->
                        if found.Value then
                            c
                        else
                            match place tok layout c with
                            | Some c' ->
                                found.Value <- true
                                c'
                            | None -> c)

                if found.Value then re k' else None

        let drops (vars: Set<string>) (e: CExpr) =
            vars |> Set.fold (fun acc x -> mk (CDrop(x, vtypes[x], acc)) acc.ty) e

        let dups (vars: string seq) (e: CExpr) =
            vars |> Seq.fold (fun acc x -> mk (CDup(x, vtypes[x], acc)) acc.ty) e

        /// Whether a path of e ends in a jump to a join point.
        let rec jumps (e: CExpr) =
            match e.k with
            | CJump _ -> true
            | CLet(_, _, b)
            | CLetMut(_, _, b)
            | CSeq(_, b)
            | CLine(_, b)
            | CDup(_, _, b)
            | CDrop(_, _, b)
            | CDropFields(_, _, _, _, _, b)
            | CFreeToken(_, b)
            | CJoin(_, _, _, b) -> jumps b
            | CIf(_, t, f) -> jumps t || jumps f
            | CMatch(_, cases) -> cases |> List.exists (fun (_, _, b) -> jumps b)
            | _ -> false

        // ---- borrowed projections (as in Lean 4's RC): the fields a match takes from a value that
        // stays alive past it are borrowed from it, not dup'ed, and dup'ed only where something
        // takes them. The value then counts as used wherever its fields are, so it's consumed
        // only after their last use.
        let parentOf = System.Collections.Generic.Dictionary<string, string>()

        /// The variables e needs alive: its free variables, and the values their borrowed fields
        /// come from.
        let live (e: CExpr) =
            let rec up (acc: Set<string>) (x: string) =
                match parentOf.TryGetValue x with
                | true, p when not (acc.Contains p) -> up (acc.Add p) p
                | _ -> acc

            let fv = freeVars e
            if parentOf.Count = 0 then fv else fv |> Set.fold up fv

        /// e must consume every variable in `owned`; `borrowed` variables stay alive throughout.
        let rec rc (owned: Set<string>) (borrowed: Set<string>) (e: CExpr) : CExpr =
            let fv = freeVars e
            let lv = live e
            let dead = Set.difference owned lv
            // what e reaches only through borrowed fields: borrowed by e, dropped after it
            let viaFields = Set.difference (Set.intersect owned lv) fv
            let e' = rc' (Set.intersect owned fv) (Set.union borrowed viaFields) e

            // the drops go where e ends: after its value, or before a jump (which doesn't come
            // back), after the jump's arguments
            let rec after (e: CExpr) =
                let re k = { e with k = k }

                match e.k with
                | CJump(j, args) ->
                    let ts = args |> List.map (fun a -> a, tmp ())

                    for a, t in ts do
                        vtypes[t] <- a.ty

                    let jump = mk (CJump(j, ts |> List.map (fun (a, t) -> mk (CLocal t) a.ty))) e.ty
                    List.foldBack (fun (a: CExpr, t) acc -> mk (CLet(t, a, acc)) acc.ty) ts (drops viaFields jump)
                | _ when not (jumps e) ->
                    let r = tmp ()
                    vtypes[r] <- e.ty
                    mk (CLet(r, e, drops viaFields (mk (CLocal r) e.ty))) e.ty
                | CLet(x, v, b) -> re (CLet(x, v, after b))
                | CLetMut(x, v, b) -> re (CLetMut(x, v, after b))
                | CSeq(a, b) -> re (CSeq(a, after b))
                | CLine(l, b) -> re (CLine(l, after b))
                | CIf(c, t, f) -> re (CIf(c, after t, after f))
                | CMatch(s, cases) -> re (CMatch(s, cases |> List.map (fun (p, g, b) -> p, g, after b)))
                | CDup(x, t, b) -> re (CDup(x, t, after b))
                | CDrop(x, t, b) -> re (CDrop(x, t, after b))
                | CDropFields(x, t, tag, keep, tok, b) -> re (CDropFields(x, t, tag, keep, tok, after b))
                | CFreeToken(t, b) -> re (CFreeToken(t, after b))
                | CJoin(j, ps, body, rest) -> re (CJoin(j, ps, body, after rest)) // the jumps to it dropped them
                | _ -> failwith "unreachable"

            let e' = if viaFields.IsEmpty then e' else after e'

            drops dead e'

        /// Ordered subexpressions: each owned variable goes to the last one that uses it.
        and rcList (owned: Set<string>) (borrowed: Set<string>) (es: CExpr list) =
            let fvs = es |> List.map live |> Array.ofList

            es
            |> List.mapi (fun i ei ->
                let later = fvs[i + 1 ..] |> Array.fold Set.union Set.empty
                let mine = Set.intersect owned fvs[i]
                let oi = Set.difference mine later
                holding (Set.intersect owned later) (fun () -> rc oi (Set.union borrowed (Set.difference mine oi)) ei))

        /// let-binds a non-variable subexpression so it can be inspected by name.
        and viaTemp (owned: Set<string>) (borrowed: Set<string>) (sub: CExpr) (build: CExpr -> CExpr) =
            let t = tmp ()
            vtypes[t] <- sub.ty
            rc' owned borrowed (mk (CLet(t, sub, build (mk (CLocal t) sub.ty))) (build (mk (CLocal t) sub.ty)).ty)

        and isVar (e: CExpr) =
            match e.k with
            | CLocal x -> not (mutables.Contains x)
            | _ -> false

        and rc' (owned: Set<string>) (borrowed: Set<string>) (e: CExpr) : CExpr =
            let re k = mk k e.ty

            match e.k with
            | CPerform _
            | CHandle _ -> failwith "Rc: an effect's node after Evidence"
            | CLocal x ->
                if owned.Contains x then e
                elif heap e.ty then mk (CDup(x, e.ty, e)) e.ty
                else e
            | CInt _
            | CFloat _
            | CBool _
            | CStr _
            | CUnit -> e
            | CLine(l, a) -> re (CLine(l, rc owned borrowed a))
            | CJoin(j, ps, body, rest) ->
                // a join point's body owns its parameters, as a function's does; jumps pass them.
                // A body that builds a cell also takes a reuse token (null, or a cell the jump's
                // path took apart), so that cell can be built in after the jump
                // and borrows the function's borrowed parameters it uses, as the function does
                let mine = ps |> List.map fst |> List.filter heapVar |> Set.ofList
                let body' = rc mine lent body

                // the cell it builds, or the one a join point it jumps to builds
                let rec layoutIn (e: CExpr) =
                    match e.k with
                    | CCtor(_, tag, args) when heap e.ty && (layoutOf e.ty tag []).IsSome -> layoutOf e.ty tag (args |> List.map (fun a -> a.ty))
                    | CJump(j2, _) when joinTok.ContainsKey j2 -> Some(snd joinTok[j2])
                    | k -> children k |> List.tryPick layoutIn

                match layoutIn body' with
                | Some l ->
                    let tp = tmp ()
                    vtypes[tp] <- tokenTy
                    joinTok[j] <- (tp, l)

                    let body'' =
                        match place tp l body' with
                        | Some b -> b
                        | None -> mk (CFreeToken(tp, body')) body'.ty

                    re (CJoin(j, ps @ [ tp, tokenTy ], body'', rc owned borrowed rest))
                | None -> re (CJoin(j, ps, body', rc owned borrowed rest))
            | CJump(j, args) ->
                let args' = rcList owned borrowed args

                if joinTok.ContainsKey j then
                    re (CJump(j, args' @ [ mk (CPrim("token.null", [])) tokenTy ]))
                else
                    re (CJump(j, args'))
            | CLet(x, v, body) ->
                let fb = live body
                let fvv = live v
                let ov = Set.difference (Set.intersect owned fvv) fb
                let v' = holding (Set.difference owned ov) (fun () -> rc ov (Set.union borrowed (Set.difference (Set.intersect owned fvv) ov)) v)
                let ob = Set.difference owned ov
                let ob = if heap v.ty then ob.Add x else ob
                re (CLet(x, v', rc ob borrowed body))
            | CLetMut(x, v, body) ->
                let fb = live body
                let fvv = live v
                let ov = Set.difference (Set.intersect owned fvv) fb
                let v' = holding (Set.difference owned ov) (fun () -> rc ov (Set.union borrowed (Set.difference (Set.intersect owned fvv) ov)) v)
                let saved = muts.Value

                if heap v.ty then
                    muts.Value <- muts.Value.Add x

                let body' =
                    try
                        rc (Set.difference owned ov) borrowed body
                    finally
                        muts.Value <- saved

                re (CLetMut(x, v', body'))
            | CSeq(a, b) when heap a.ty ->
                let t = tmp ()
                vtypes[t] <- a.ty
                rc' owned borrowed (re (CLet(t, a, b)))
            | CSeq(a, b) ->
                match rcList owned borrowed [ a; b ] with
                | [ a'; b' ] -> re (CSeq(a', b'))
                | _ -> failwith "unreachable"
            | CIf(c, t, f) ->
                let fc = live c
                let fr = Set.union (live t) (live f)
                let mine = Set.intersect owned fc
                let oc = Set.difference mine fr
                let c' = rc oc (Set.union borrowed (Set.difference mine oc)) c
                let rest = Set.difference owned oc
                re (CIf(c', rc rest borrowed t, rc rest borrowed f))
            | CMatch(s, cases) when isVar s ->
                let x =
                    match s.k with
                    | CLocal x -> x
                    | _ -> failwith "unreachable"

                let xOwned = owned.Contains x

                let cases' =
                    cases
                    |> List.map (fun (p, g, body) ->
                        let pvars = patVars p |> List.map fst |> List.filter heapVar |> Set.ofList
                        let all = Set.unionMany [ borrowed; owned; pvars ]
                        let g' = g |> Option.map (rc Set.empty all)

                        let used = Set.intersect pvars (freeVars body)

                        match p with
                        | CPCtor(_, tag, fps) when xOwned && not (fps.IsEmpty || (live body).Contains x) ->
                            // x dies here: specialize its drop, and reuse its cell if the body builds one alike
                            let direct =
                                fps
                                |> List.indexed
                                |> List.choose (fun (i, fp) ->
                                    match fp with
                                    | CPVar(v, _)
                                    | CPAs(_, v, _) when used.Contains v -> Some(i, v)
                                    | _ -> None)

                            let keep = direct |> List.map fst |> Set.ofList
                            let nested = Set.difference used (direct |> List.map snd |> Set.ofList)
                            let body' = rc (Set.union (owned.Remove x) used) borrowed body
                            let tok = tmp ()

                            let node =
                                match layoutOf s.ty tag (fieldTypes s.ty tag) |> Option.bind (fun l -> place tok l body') with
                                | Some b -> CDropFields(x, s.ty, tag, keep, Some tok, b)
                                | None -> CDropFields(x, s.ty, tag, keep, None, body')

                            p, g', dups nested (mk node body.ty)
                        | _ ->
                            // x stays alive past this case (or is borrowed): its fields are
                            // borrowed from it, and x, or whatever owns it, lives as long as
                            // they're used
                            for v in pvars do
                                parentOf[v] <- x

                            p, g', rc owned (Set.union borrowed pvars) body)

                re (CMatch(s, cases'))
            | CMatch({ k = CTuple xs } as s, cases) when xs |> List.forall isVar ->
                // match (a, b) with …: the tuple only borrows its parts, which stay with their
                // variables (owned as before); the pattern variables borrow from the part they
                // come from, which lives as long as they're used
                let cases' =
                    cases
                    |> List.map (fun (p, g, body) ->
                        let pvars = patVars p |> List.map fst |> List.filter heapVar |> Set.ofList
                        let g' = g |> Option.map (rc Set.empty (Set.unionMany [ borrowed; owned; pvars ]))

                        match p with
                        | CPTuple ps ->
                            List.zip xs ps
                            |> List.iter (fun (x, q) ->
                                match x.k with
                                | CLocal xv ->
                                    for v, _ in patVars q do
                                        if heapVar v then parentOf[v] <- xv
                                | _ -> ())

                            p, g', rc owned (Set.union borrowed pvars) body
                        | _ ->
                            // an or-pattern may take a variable from a different part in each
                            // alternative: no one part to keep alive, so the ones used are dup'ed
                            let used = Set.intersect pvars (freeVars body)
                            p, g', dups used (rc (Set.union owned used) borrowed body))

                re (CMatch(s, cases'))
            | CMatch(s, cases) -> viaTemp owned borrowed s (fun v -> re (CMatch(v, cases)))
            | CField(r, i) when isVar r ->
                let x =
                    match r.k with
                    | CLocal x -> x
                    | _ -> failwith "unreachable"

                let f = tmp ()
                vtypes[f] <- e.ty
                let res = mk (CLocal f) e.ty
                let res = if owned.Contains x then mk (CDrop(x, vtypes[x], res)) e.ty else res
                let res = if heap e.ty then mk (CDup(f, e.ty, res)) e.ty else res
                re (CLet(f, e, res))
            | CField(r, i) -> viaTemp owned borrowed r (fun v -> re (CField(v, i)))
            | CApplyClo(fe, args) when isVar fe ->
                let x =
                    match fe.k with
                    | CLocal x -> x
                    | _ -> failwith "unreachable"

                // the closure stays alive across the arguments and the call, then is released
                let args' = rcList (owned.Remove x) (borrowed.Add x) args

                if owned.Contains x then
                    let r = tmp ()
                    vtypes[r] <- e.ty
                    re (CLet(r, re (CApplyClo(fe, args')), mk (CDrop(x, vtypes[x], mk (CLocal r) e.ty)) e.ty))
                else
                    re (CApplyClo(fe, args'))
            | CApplyClo(fe, args) -> viaTemp owned borrowed fe (fun v -> re (CApplyClo(v, args)))
            | CWhile _
            | CFor _ ->
                // loop parts run repeatedly, so they only borrow; owned variables die after the loop
                let all = Set.union owned borrowed
                let loop = re (mapChildren (rc Set.empty all) e.k)
                mk (CSeq(loop, drops owned (mk CUnit tUnit))) tUnit
            | CAssign(x, v) when heapVar x ->
                // x <- f … x …: when x is a direct argument of the call (once, and nowhere else
                // in it), the call gets x's own reference and the old value isn't dropped, so a
                // unique value stays unique (copy-on-write updates in place)
                let direct (args: CExpr list) =
                    let hits = args |> List.filter (fun a -> a.k = CLocal x)
                    let others = args |> List.filter (fun a -> a.k <> CLocal x)

                    hits.Length = 1 && others |> List.forall (fun a -> not ((freeVars a).Contains x))

                let take (args: CExpr list) =
                    args |> List.map (fun a -> if a.k = CLocal x then mk (CPrim("slot.take", [ a ])) a.ty else a)

                // x <- (let p = x in …), as an inlined call is: p gets x's own reference
                let rec viaLets (e: CExpr) =
                    match e.k with
                    | CLet(p, ({ k = CLocal y } as a), body) when y = x && not ((freeVars body).Contains x) ->
                        Some(mk (CLet(p, mk (CPrim("slot.take", [ a ])) a.ty, body)) e.ty)
                    | CLet(p, pv, body) when not ((freeVars pv).Contains x) -> viaLets body |> Option.map (fun b -> mk (CLet(p, pv, b)) e.ty)
                    | _ -> None

                let moved =
                    match v.k with
                    | CCallDirect(f, args) when direct args -> Some(mk (CCallDirect(f, take args)) v.ty)
                    | CPrim(op, args) when direct args -> Some(mk (CPrim(op, take args)) v.ty)
                    | CLet _ -> viaLets v
                    | _ -> None

                match moved with
                | Some v -> re (CAssign(x, mk (CPrim("slot.moved", [ rc owned borrowed v ])) v.ty))
                | None -> re (CAssign(x, rc owned borrowed v))
            | CPrim("slot.take", _) -> e // the variable's own reference, moved out
            | CGlobalVal _ when heap e.ty ->
                // a top-level value keeps its reference; a read takes one of its own
                let t = tmp ()
                vtypes[t] <- e.ty
                re (CLet(t, e, mk (CDup(t, e.ty, mk (CLocal t) e.ty)) e.ty))
            | CGlobalVal _ -> e
            | CPrim(("array.get" | "Array.length" | "String.length" | "String.byte" | "vec.load" | "fixed.get" | "fixed.length") as op, a :: rest) when
                (match rootLocal a with
                 | Some x -> not (rest |> List.exists (fun r -> (live r).Contains x))
                 | None -> false)
                ->
                // reading an element or the length borrows the array (or string), a variable or
                // a record field of one: no dup before, no drop inside; if this was x's last use,
                // x is dropped after
                let x = (rootLocal a).Value
                let rest' = rcList (owned.Remove x) (borrowed.Add x) rest
                let read = re (CPrim(op + "#b", a :: rest'))

                if owned.Contains x then
                    let r = tmp ()
                    vtypes[r] <- e.ty
                    re (CLet(r, read, mk (CDrop(x, vtypes[x], mk (CLocal r) e.ty)) e.ty))
                else
                    read
            | CAssign(x, v) -> re (CAssign(x, rc owned borrowed v))
            | CArraySet(x, i, v) ->
                match rcList owned borrowed [ i; v ] with
                | [ i'; v' ] -> re (CArraySet(x, i', v'))
                | _ -> failwith "unreachable"
            | CTuple xs -> re (CTuple(rcList owned borrowed xs))
            | CCtor(u, tag, xs) -> re (CCtor(u, tag, rcList owned borrowed xs))
            | CCallDirect(n, xs) when (match borrowedParams.TryGetValue n with
                                       | true, bs -> not bs.IsEmpty
                                       | _ -> false) ->
                // borrowed positions: a variable passed once is lent (and dropped after the call
                // if this was its last use); anything else goes through a temporary dropped after
                let bs = borrowedParams[n]

                let lentArg (j: int) (a: CExpr) =
                    bs.Contains j
                    && (match a.k with
                        | CLocal x -> (xs |> List.filter (fun b -> b.k = CLocal x)).Length = 1
                        | _ -> false)

                let needsTemp (j: int) (a: CExpr) = bs.Contains j && not (lentArg j a)

                if xs |> List.indexed |> List.exists (fun (j, a) -> needsTemp j a) then
                    // bind the others' temporaries first, then retry with variables in their place
                    let temps = xs |> List.mapi (fun j a -> if needsTemp j a then Some(tmp (), a) else None)

                    for t in temps do
                        match t with
                        | Some(v, (a: CExpr)) -> vtypes[v] <- a.ty
                        | None -> ()

                    let call = re (CCallDirect(n, List.map2 (fun t (a: CExpr) -> match t with Some(v, _) -> mk (CLocal v) a.ty | None -> a) temps xs))
                    let body = temps |> List.choose id |> List.rev |> List.fold (fun acc (v, a) -> mk (CLet(v, a, acc)) e.ty) call
                    rc' owned borrowed body
                else
                    let lentVars = xs |> List.indexed |> List.choose (fun (j, a) -> match a.k with | CLocal x when lentArg j a -> Some x | _ -> None) |> Set.ofList
                    let others = xs |> List.indexed |> List.filter (fun (j, _) -> not (lentArg j xs[j])) |> List.map snd
                    let others' = rcList (Set.difference owned lentVars) (Set.union borrowed lentVars) others
                    let mutable k = 0

                    let args =
                        xs
                        |> List.mapi (fun j a ->
                            if lentArg j a then
                                a
                            else
                                let r = others'[k]
                                k <- k + 1
                                r)

                    let call = re (CCallDirect(n, args))
                    let dying = Set.intersect owned lentVars

                    if dying.IsEmpty then
                        call
                    else
                        let r = tmp ()
                        vtypes[r] <- e.ty
                        re (CLet(r, call, drops dying (mk (CLocal r) e.ty)))
            | CCallDirect(n, xs) -> re (CCallDirect(n, rcList owned borrowed xs))
            | CExtern(n, xs) -> re (CExtern(n, rcList owned borrowed xs))
            | CPrim(("task.suspend" | "task.abandon") as n, xs) ->
                // a wait: what the task holds across it (dropped if it's cancelled there) goes
                // with it, after its arguments, as task.held (variables and mutables)
                let xs' = rcList owned borrowed xs
                let vars = Set.union held.Value muts.Value |> Set.filter heapVar |> Set.toList
                let heldNode = mk (CPrim("task.held", vars |> List.map (fun v -> mk (CLocal v) vtypes[v]))) e.ty
                re (CPrim(n, xs' @ [ heldNode ]))
            | CPrim(n, xs) -> re (CPrim(n, rcList owned borrowed xs))
            | CMkClosure(n, xs) -> re (CMkClosure(n, rcList owned borrowed xs))
            | CBin(op, a, b) ->
                match rcList owned borrowed [ a; b ] with
                | [ a'; b' ] -> re (CBin(op, a', b'))
                | _ -> failwith "unreachable"
            | CNeg a -> re (CNeg(rc owned borrowed a))
            | CNot a -> re (CNot(rc owned borrowed a))
            | CGlobal _
            | CApp _
            | CLam _
            | CLetFun _
            | CLetRec _
            | CDup _
            | CDrop _
            | CDropFields _
            | CCtorAt _
            | CFreeToken _ -> failwithf "Rc: unexpected node %A" e.k

        // ---- moving out of mutable variables: `let r = f … x …` (or a match or statement on such a
        // call) where x is a `let mutable` passed directly, and x is reassigned before it is
        // read again on every path after it. The call gets x's own reference (so a unique value
        // stays unique, and Perceus can reuse its cell), and that reassignment drops nothing.
        let rec firstUse (x: string) (e: CExpr) : int = // 0: not used, 1: read first, 2: assigned first
            let inOrder (es: CExpr list) =
                es |> List.fold (fun u c -> if u <> 0 then u else firstUse x c) 0

            let join (us: int list) =
                if us |> List.forall ((=) 2) then 2
                elif us |> List.forall ((=) 0) then 0
                else 1 // a path that reads it, or that might not reassign it

            match e.k with
            | CLocal y when y = x -> 1
            | CAssign(y, v) when y = x -> if firstUse x v = 1 then 1 else 2
            | CIf(c, t, f) ->
                match firstUse x c with
                | 0 -> join [ firstUse x t; firstUse x f ]
                | u -> u
            | CMatch(sc, cases) ->
                match firstUse x sc with
                | 0 -> join (cases |> List.map (fun (_, g, b) -> inOrder ((Option.toList g) @ [ b ])))
                | u -> u
            | CWhile _
            | CFor _ -> if (freeVars e).Contains x || (refs e |> List.exists (fun (y, _) -> y = x)) then 1 else 0
            | CLam _ -> 0
            | k -> inOrder (children k)

        /// The first assignment to x on every path, marked as taking a moved-out variable.
        let rec markAssign (x: string) (e: CExpr) : CExpr =
            match e.k with
            | CAssign(y, v) when y = x -> mk (CAssign(x, mk (CPrim("slot.moved", [ v ])) v.ty)) e.ty
            | CIf(c, t, f) -> mk (CIf(c, markAssign x t, markAssign x f)) e.ty
            | CMatch(sc, cases) -> mk (CMatch(sc, cases |> List.map (fun (p, g, b) -> p, g, markAssign x b))) e.ty
            | CSeq(a, b) -> if firstUse x a = 2 then mk (CSeq(markAssign x a, b)) e.ty else mk (CSeq(a, markAssign x b)) e.ty
            | CLet(y, v, b) -> if firstUse x v = 2 then mk (CLet(y, markAssign x v, b)) e.ty else mk (CLet(y, v, markAssign x b)) e.ty
            | CLine(l, a) -> mk (CLine(l, markAssign x a)) e.ty
            | _ -> e

        let rec moves (e: CExpr) : CExpr =
            let re k = mk k e.ty

            /// h followed by continuations: move what every continuation reassigns first
            let rec split (h: CExpr) (conts: CExpr list) (build: CExpr -> CExpr list -> CExpr) =
              match h.k with
              | CLine(l, inner) -> split inner conts (fun inner' cs -> build (mk (CLine(l, inner')) h.ty) cs)
              | _ ->
                let args =
                    match h.k with
                    | CCallDirect(_, a)
                    | CCtor(_, _, a)
                    | CTuple a -> a
                    | CPrim(op, a) when not (op.StartsWith "slot.") -> a
                    | _ -> []

                let ok =
                    args
                    |> List.choose (fun a ->
                        match a.k with
                        | CLocal x when mutables.Contains x && heapVar x && conts |> List.forall (fun c -> firstUse x c = 2) -> Some x
                        | _ -> None)
                    |> List.filter (fun x ->
                        (args |> List.filter (fun a -> a.k = CLocal x)).Length = 1
                        && args |> List.forall (fun a -> a.k = CLocal x || not ((freeVars a).Contains x)))

                if ok.IsEmpty then
                    build (moves h) (List.map moves conts)
                else
                    let take (a: CExpr) = match a.k with | CLocal x when List.contains x ok -> mk (CPrim("slot.take", [ a ])) a.ty | _ -> a

                    let h' =
                        match h.k with
                        | CCallDirect(n, a) -> mk (CCallDirect(n, List.map take a)) h.ty
                        | CCtor(u, t, a) -> mk (CCtor(u, t, List.map take a)) h.ty
                        | CTuple a -> mk (CTuple(List.map take a)) h.ty
                        | CPrim(op, a) -> mk (CPrim(op, List.map take a)) h.ty
                        | _ -> h

                    build h' (conts |> List.map (fun c -> ok |> List.fold (fun c x -> markAssign x c) c |> moves))

            match e.k with
            | CLet(y, v, b) -> split v [ b ] (fun v' bs -> re (CLet(y, v', List.head bs)))
            | CSeq(a, b) -> split a [ b ] (fun a' bs -> re (CSeq(a', List.head bs)))
            | CMatch(sc, cases) when cases |> List.forall (fun (_, g, _) -> g.IsNone) ->
                split sc (cases |> List.map (fun (_, _, b) -> b)) (fun sc' bs -> re (CMatch(sc', List.map2 (fun (p, g, _) b -> p, g, b) cases bs)))
            | k -> re (mapChildren moves k)

        let owned = f.pars |> List.map fst |> List.filter heapVar |> Set.ofList |> fun o -> Set.difference o lent
        { f with body = rc owned lent (moves f.body) }

    // each function on its own, on every core
    try
        funs |> Array.ofList |> Array.Parallel.map rcFun |> List.ofArray
    with :? System.AggregateException as e ->
        raise e.InnerExceptions[0]

let run types (entries: Set<string>) (funs: MFun list) = lower types (borrowing types entries funs) funs
