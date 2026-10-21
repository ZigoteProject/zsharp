/// Inlining: a call to a small function that doesn't call itself becomes a copy of its body,
/// its parameters bound to the arguments. The caller's reference counting then sees the
/// callee's constructors next to the cells the caller takes apart, and builds them in place
/// (Perceus reuse): an insert into a unique tree allocates nothing on its way down.
// ponytail: one level, by size alone; a cost model (size x call sites) when code size matters
module Inline

open Core
open Mono

let private mk k ty = { k = k; ty = ty }
let private counter = ref 0

let private fresh (x: string) =
    counter.Value <- counter.Value + 1
    sprintf "%s.i%d" x counter.Value

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

/// A copy of e for another place: what it binds gets fresh names (names stay unique per
/// program), the parameters in m their arguments' names, and line marks go (they would
/// point into the callee's file).
let private copy (m: Map<string, string>) (e: CExpr) : CExpr =
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

/// Inlines calls to small functions that don't call themselves. Callees are done first, so a
/// copy carries what was inlined into it.
let run (funs: MFun list) : MFun list =
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

    let small =
        funs
        |> List.filter (fun f ->
            f.name <> "main" && size f.body <= 60 && not (localFunctions f.body) && not (calls f.body |> List.contains f.name))
        |> List.map (fun f -> f.name)
        |> Set.ofList

    let done' = System.Collections.Generic.Dictionary<string, CExpr>()
    let visiting = System.Collections.Generic.HashSet<string>()

    // a function's body with its calls to small functions inlined
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
        | CApp({ k = CGlobal(g, _) }, args) when small.Contains g && g <> caller && args.Length = byName[g].pars.Length ->
            let ps = byName[g].pars |> List.map (fun (p, t) -> p, fresh p, t)
            let body = copy (ps |> List.map (fun (p, p', _) -> p, p') |> Map.ofList) (bodyOf g)
            // the arguments in order, each bound to its parameter
            List.foldBack2 (fun (_, p', _) (a: CExpr) (acc: CExpr) -> mk (CLet(p', a, acc)) acc.ty) ps args body
        | _ -> e

    funs |> List.map (fun f -> { f with body = bodyOf f.name })
