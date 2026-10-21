/// Perceus reference counting (Reinking, Xie, de Moura, Leijen; PLDI 2021), base algorithm:
/// precise ownership. Every owned variable is consumed exactly once on every path: moved into
/// its last use, dup'ed before earlier uses, and dropped as soon as it is dead (at the start of
/// a branch that does not use it). Function arguments are owned by the callee; a closure being
/// applied is borrowed. Pattern variables borrow from the scrutinee and are dup'ed when used.
module Rc

open Core
open Mono

let run (types: System.Collections.Generic.Dictionary<string, TypeInfo>) (funs: MFun list) : MFun list =
    let heap t = needsRc types t
    let mk k ty = { k = k; ty = ty }
    let count = ref 0

    let tmp () =
        count.Value <- count.Value + 1
        sprintf "$rc%d" count.Value

    // ---- borrowed parameters (Perceus borrowing): a heap parameter the function only applies,
    // reads (a.[i], lengths) or passes on to a borrowed parameter is borrowed. The caller keeps
    // ownership and the callee neither dups nor drops it, so a closure or array threaded
    // through a loop costs no reference counting. Only for functions called directly (not
    // closures, which are called through code pointers, nor main).
    let borrowedParams =
        let asValues = System.Collections.Generic.HashSet<string>([ "main" ])

        let rec values (e: CExpr) =
            match e.k with
            | CMkClosure(n, _) -> asValues.Add n |> ignore
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

        while changed do
            changed <- false

            for KeyValue(name, set) in List.ofSeq borrowedOf do
                let f = fnOf[name]

                let ok i =
                    let p = fst f.pars[i]
                    let mutable bad = false

                    let rec walk (e: CExpr) =
                        match e.k with
                        | CLocal x when x = p -> bad <- true
                        | CApplyClo({ k = CLocal x }, arg) when x = p -> walk arg
                        | CPrim(("array.get" | "Array.length" | "String.length" | "String.byte"), { k = CLocal x } :: rest) when x = p ->
                            List.iter walk rest
                        | CCallDirect(g, args) ->
                            args
                            |> List.iteri (fun j a ->
                                match a.k with
                                | CLocal x when x = p ->
                                    let once = (args |> List.filter (fun b -> b.k = CLocal p)).Length = 1

                                    match borrowedOf.TryGetValue g with
                                    | true, bs when once && bs.Contains j -> ()
                                    | _ -> bad <- true
                                | _ -> walk a)
                        | CAssign(x, _)
                        | CArraySet(x, _, _) when x = p -> bad <- true
                        | k -> children k |> List.iter walk

                    walk f.body
                    not bad

                let kept = set |> Set.filter ok

                if kept <> set then
                    borrowedOf[name] <- kept
                    changed <- true

        borrowedOf

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
            | CBin("+", a, b) when isString a -> flatten a @ flatten b
            | _ -> [ e ]

        match e.k with
        | CPrim(("print" | "println") as op, [ ({ k = CBin("+", a, _) } as arg) ]) when isString a ->
            let temps = flatten arg |> List.map (fun p -> tmp (), printPieces p)
            let last = temps.Length - 1

            let prints =
                temps
                |> List.mapi (fun i (t, p) -> mk (CPrim((if i = last then op else "print"), [ mk (CLocal t) p.ty ])) tUnit)
                |> List.reduce (fun a b -> mk (CSeq(a, b)) tUnit)

            List.foldBack (fun (t, p) acc -> mk (CLet(t, p, acc)) tUnit) temps prints
        | k -> mk (mapChildren printPieces k) e.ty

    let rcFun (f: MFun) =
        let f = { f with body = printPieces f.body }
        // every variable's type, by unique name
        let vtypes = System.Collections.Generic.Dictionary<string, Ty>()

        for x, t in f.pars do
            vtypes[x] <- t

        let rec collect (e: CExpr) =
            match e.k with
            | CLet(x, v, _)
            | CLetMut(x, v, _) -> vtypes[x] <- v.ty
            | CFor(x, a, _, _, _) -> vtypes[x] <- a.ty
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

        let fieldTypes (t: Ty) tag =
            match prune t with
            | TCon(u, args) ->
                match types[u].def with
                | UnionDef cs -> snd cs[tag] |> List.map (substGen args)
                | RecordDef _ -> []
            | _ -> []

        /// Rewrites one constructor with the given field layout, on every path of e that ends in
        /// one, to build in the token's cell; paths without one free the token. None = no site.
        let rec place (tok: string) (layout: Ty list) (e: CExpr) : CExpr option =
            let re k = Some(mk k e.ty)
            let free (b: CExpr) = mk (CFreeToken(tok, b)) b.ty

            match e.k with
            | CCtor(u, tag, args) when heap e.ty && (args |> List.map (fun a -> a.ty)) = layout -> re (CCtorAt(tok, u, tag, args))
            | CWhile _
            | CFor _ -> None // runs repeatedly
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

        // ponytail: free variables are recomputed per node (quadratic); cache them if compile time matters
        /// e must consume every variable in `owned`; `borrowed` variables stay alive throughout.
        let rec rc (owned: Set<string>) (borrowed: Set<string>) (e: CExpr) : CExpr =
            let fv = freeVars e
            let dead = Set.difference owned fv
            drops dead (rc' (Set.intersect owned fv) borrowed e)

        /// Ordered subexpressions: each owned variable goes to the last one that uses it.
        and rcList (owned: Set<string>) (borrowed: Set<string>) (es: CExpr list) =
            let fvs = es |> List.map freeVars |> Array.ofList

            es
            |> List.mapi (fun i ei ->
                let later = fvs[i + 1 ..] |> Array.fold Set.union Set.empty
                let mine = Set.intersect owned fvs[i]
                let oi = Set.difference mine later
                rc oi (Set.union borrowed (Set.difference mine oi)) ei)

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
            | CLet(x, v, body) ->
                let fb = freeVars body
                let fvv = freeVars v
                let ov = Set.difference (Set.intersect owned fvv) fb
                let v' = rc ov (Set.union borrowed (Set.difference (Set.intersect owned fvv) ov)) v
                let ob = Set.difference owned ov
                let ob = if heap v.ty then ob.Add x else ob
                re (CLet(x, v', rc ob borrowed body))
            | CLetMut(x, v, body) ->
                let fb = freeVars body
                let fvv = freeVars v
                let ov = Set.difference (Set.intersect owned fvv) fb
                let v' = rc ov (Set.union borrowed (Set.difference (Set.intersect owned fvv) ov)) v
                re (CLetMut(x, v', rc (Set.difference owned ov) borrowed body))
            | CSeq(a, b) when heap a.ty ->
                let t = tmp ()
                vtypes[t] <- a.ty
                rc' owned borrowed (re (CLet(t, a, b)))
            | CSeq(a, b) ->
                match rcList owned borrowed [ a; b ] with
                | [ a'; b' ] -> re (CSeq(a', b'))
                | _ -> failwith "unreachable"
            | CIf(c, t, f) ->
                let fc = freeVars c
                let fr = Set.union (freeVars t) (freeVars f)
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
                        | CPCtor(_, tag, fps) when xOwned && not (fps.IsEmpty || (freeVars body).Contains x) ->
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
                            let layout = fieldTypes s.ty tag

                            let node =
                                match place tok layout body' with
                                | Some b -> CDropFields(x, s.ty, tag, keep, Some tok, b)
                                | None -> CDropFields(x, s.ty, tag, keep, None, body')

                            p, g', dups nested (mk node body.ty)
                        | _ when xOwned -> p, g', dups used (rc (Set.union owned used) borrowed body)
                        | _ -> p, g', rc owned (Set.union borrowed pvars) body)

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
            | CApplyClo(fe, arg) when isVar fe ->
                let x =
                    match fe.k with
                    | CLocal x -> x
                    | _ -> failwith "unreachable"

                // the closure stays alive across the argument and the call, then is released
                let arg' = rc (owned.Remove x) (borrowed.Add x) arg

                if owned.Contains x then
                    let r = tmp ()
                    vtypes[r] <- e.ty
                    re (CLet(r, re (CApplyClo(fe, arg')), mk (CDrop(x, vtypes[x], mk (CLocal r) e.ty)) e.ty))
                else
                    re (CApplyClo(fe, arg'))
            | CApplyClo(fe, arg) -> viaTemp owned borrowed fe (fun v -> re (CApplyClo(v, arg)))
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

                let moved =
                    match v.k with
                    | CCallDirect(f, args) when direct args -> Some(mk (CCallDirect(f, take args)) v.ty)
                    | CPrim(op, args) when direct args -> Some(mk (CPrim(op, take args)) v.ty)
                    | _ -> None

                match moved with
                | Some v -> re (CAssign(x, mk (CPrim("slot.moved", [ rc owned borrowed v ])) v.ty))
                | None -> re (CAssign(x, rc owned borrowed v))
            | CPrim("slot.take", _) -> e // the variable's own reference, moved out
            | CPrim(("array.get" | "Array.length" | "String.length" | "String.byte") as op, ({ k = CLocal x } as a) :: rest) when
                not (rest |> List.exists (fun r -> (freeVars r).Contains x))
                ->
                // reading an element or the length borrows the array (or string): no dup before,
                // no drop inside; if this was x's last use, x is dropped after
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

        let mine =
            match borrowedParams.TryGetValue f.name with
            | true, bs -> bs
            | _ -> Set.empty

        let lent = f.pars |> List.indexed |> List.filter (fun (i, _) -> mine.Contains i) |> List.map (snd >> fst) |> Set.ofList
        let owned = f.pars |> List.map fst |> List.filter heapVar |> Set.ofList |> fun o -> Set.difference o lent
        { f with body = rc owned lent (moves f.body) }

    List.map rcFun funs
