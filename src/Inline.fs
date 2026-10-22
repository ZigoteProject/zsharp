/// Inlining: a call to a small function that doesn't call itself becomes a copy of its body,
/// its parameters bound to the arguments. The caller's reference counting then sees the
/// callee's constructors next to the cells the caller takes apart, and builds them in place
/// (Perceus reuse): an insert into a unique tree allocates nothing on its way down.
// ponytail: one level, by size alone; a cost model (size x call sites) when code size matters
module Inline

open Core
open Mono

let private mk k ty = { k = k; ty = ty }

let rec private size (e: CExpr) = 1 + (children e.k |> List.sumBy size)

let rec private renamePat (rn: string -> string) (p: CPat) =
    match p with
    | CPVar(x, t) -> CPVar(rn x, t)
    | CPAs(q, x, t) -> CPAs(renamePat rn q, rn x, t)
    | CPTuple ps -> CPTuple(List.map (renamePat rn) ps)
    | CPRecord(r, fs) -> CPRecord(r, fs |> List.map (fun (n, q) -> n, renamePat rn q))
    | CPCtor(u, tag, ps) -> CPCtor(u, tag, List.map (renamePat rn) ps)
    | CPOr(a, b) -> CPOr(renamePat rn a, renamePat rn b)
    | p -> p

/// A copy of e for another place: what it binds gets fresh names (names stay unique in the
/// function it goes into), the parameters in m their arguments' names, and line marks go
/// (they would point into the callee's file).
let private copy (fresh: string -> string) (m: Map<string, string>) (e: CExpr) : CExpr =
    let m = binders e |> List.distinct |> List.fold (fun (acc: Map<string, string>) x -> acc.Add(x, fresh x)) m
    let rn x = defaultArg (m.TryFind x) x
    let pars ps = ps |> List.map (fun (x, t) -> rn x, t)

    let rec go (e: CExpr) =
        match e.k with
        | CLine(_, inner) -> go inner
        | k ->
            let k =
                match k with
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
                | k -> mapChildren go k

            { e with k = k }

    go e

/// Uncurrying: a function whose body is a lambda takes the lambda's parameters too, so
/// `let add x = fun y -> x + y` has two parameters and `add 1 2` is one call (the closure it
/// returned only held x: nothing runs at another time). A lambda returning a lambda merges
/// the same way. Functions called from outside (main, tests, C exports) keep their signatures.
let uncurry (fixedNames: Set<string>) (funs: MFun list) : MFun list =
    let rec lambda (e: CExpr) =
        match e.k with
        | CLam(ps, b) -> Some(ps, b)
        | CLine(_, inner) -> lambda inner
        | _ -> None

    let rec merge (ps: (string * Ty) list, body: CExpr) =
        match lambda body with
        | Some(more, b) -> merge (ps @ more, b)
        | None -> ps, body

    let rec go (e: CExpr) : CExpr =
        let k =
            match mapChildren go e.k with
            | CLam(ps, b) -> CLam(merge (ps, b))
            | CLetFun(n, r, ps, b, rest) ->
                let ps, b = merge (ps, b)
                CLetFun(n, r, ps, b, rest)
            | CLetRec(fs, rest) -> CLetRec(fs |> List.map (fun (n, ps, b) -> (let ps, b = merge (ps, b) in n, ps, b)), rest)
            | k -> k

        { e with k = k }

    funs
    |> List.map (fun f ->
        let body = go f.body

        if f.pars.IsEmpty || fixedNames.Contains f.name then
            { f with body = body }
        else
            let ps, b = merge (f.pars, body)
            { f with pars = ps; ret = b.ty; body = b })

/// Functions never inlined into others: [<Target>] and [<Multiversion>] ones, whose code is for
/// CPU features their callers may not have (the driver sets it).
let mutable kept: string -> bool = fun _ -> false

/// Inlines calls to small functions that don't call themselves. Callees are done first, so a
/// copy carries what was inlined into it. mayInline caller callee: whether this callee may be
/// (a module's code holds none of another module's functions, the driver says).
let runWith (mayInline: string -> string -> bool) (funs: MFun list) : MFun list =
    let byName = funs |> List.map (fun f -> f.name, f) |> dict

    let rec calls (e: CExpr) =
        (match e.k with
         | CGlobal(g, _) -> [ g ]
         | _ -> [])
        @ (children e.k |> List.collect calls)

    // a local function in the body would be copied (and lifted) once per call site
    let rec localFunctions (e: CExpr) =
        match e.k with
        | CLetFun _
        | CLetRec _ -> true
        | k -> children k |> List.exists localFunctions

    let candidates =
        funs
        |> List.filter (fun f -> f.name <> "main" && not (kept f.name) && size f.body <= 60 && not (localFunctions f.body))
        |> List.map (fun f -> f.name, calls f.body |> List.distinct)
        |> dict

    // not one that can reach itself through others: what a copy carried would depend on which
    // of them was done first, and a function's code must depend on its own callees only
    let small =
        candidates.Keys
        |> Seq.filter (fun f ->
            let seen = System.Collections.Generic.HashSet<string>()

            let rec back (g: string) =
                candidates[g] |> List.exists (fun h -> h = f || (candidates.ContainsKey h && seen.Add h && back h))

            not (back f))
        |> Set.ofSeq

    let done' = System.Collections.Generic.Dictionary<string, CExpr>()
    let visiting = System.Collections.Generic.HashSet<string>()

    // fresh names numbered per function, so a function's code doesn't depend on others' (a
    // build reuses the compiled code of modules that didn't change)
    let counters = System.Collections.Generic.Dictionary<string, int ref>()

    let freshIn (f: string) (x: string) =
        let c =
            match counters.TryGetValue f with
            | true, c -> c
            | _ ->
                let c = ref 0
                counters[f] <- c
                c

        c.Value <- c.Value + 1
        sprintf "%s.i%d" x c.Value

    // a function's body with its calls to small functions inlined (no small one is in a cycle)
    let rec bodyOf (name: string) : CExpr =
        match done'.TryGetValue name with
        | true, b -> b
        | _ when not (visiting.Add name) -> byName[name].body // in a cycle: as written
        | _ ->
            let b = inlineIn name byName[name].body
            done'[name] <- b
            b

    and inlineIn (caller: string) (e: CExpr) =
        let e = { e with k = mapChildren (inlineIn caller) e.k }

        match e.k with
        | CApp({ k = CGlobal(g, _) }, args) when small.Contains g && g <> caller && args.Length = byName[g].pars.Length && mayInline caller g ->
            let fresh = freshIn caller
            let ps = byName[g].pars |> List.map (fun (p, t) -> p, fresh p, t)
            let body = copy fresh (ps |> List.map (fun (p, p', _) -> p, p') |> Map.ofList) (bodyOf g)
            // the arguments in order, each bound to its parameter
            List.foldBack2 (fun (_, p', _) (a: CExpr) (acc: CExpr) -> mk (CLet(p', a, acc)) acc.ty) ps args body
        | _ -> e

    funs |> List.map (fun f -> { f with body = bodyOf f.name })

let run (funs: MFun list) : MFun list = runWith (fun _ _ -> true) funs
