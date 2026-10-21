/// Match lowering: a match whose patterns nest, or that takes a tuple apart, becomes a tree of
/// one-level matches on variables (a decision tree). No subterm is tested twice, no tuple is
/// built for the scrutinee, and every cell the match takes apart is matched on its own, which
/// is where reference counting specializes the drop and reuses the cell.
///
/// A part of the tree reached on several paths (the same rows left, reading the same columns)
/// is built once: a small one is copied to each path, a larger one becomes a join point that
/// the paths jump to, so the tree's size stays close to the match's.
module Decide

open System.Collections.Generic
open Core
open Mono

let private mk k ty = { k = k; ty = ty }
let private counter = ref 0

let private fresh (x: string) =
    counter.Value <- counter.Value + 1
    sprintf "%s.d%d" x counter.Value

/// Node counts, remembered per node (subtrees are measured again as the tree grows).
let private sizes = Dictionary<CExpr, int>(HashIdentity.Reference)

let rec private size (e: CExpr) =
    match sizes.TryGetValue e with
    | true, n -> n
    | _ ->
        let mutable n = 1
        mapChildren (fun c -> n <- n + size c; c) e.k |> ignore
        sizes[e] <- n
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

/// e with variables renamed: binders in `bound` get fresh names (a body copied to a second
/// place keeps names unique), and free variables in `m` take the mapped name.
let private rename (m: Map<string, string>) (fresh': bool) (e: CExpr) : CExpr =
    let m =
        if fresh' then
            binders e |> List.distinct |> List.fold (fun (acc: Map<string, string>) x -> acc.Add(x, fresh x)) m
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
                | CJoin(j, ps, b, r) -> CJoin(j, pars ps, go b, go r)
                | k -> mapChildren go k

            { e with k = k }

        go e

let rec private irrefutable (p: CPat) =
    match p with
    | CPWild
    | CPVar _ -> true
    | CPAs(q, _, _) -> irrefutable q
    | CPTuple ps -> List.forall irrefutable ps
    | CPRecord(_, fs) -> fs |> List.forall (snd >> irrefutable)
    | _ -> false

/// A pattern that tests something below its top: Node (Red, Node _, …), x :: y :: rest.
let rec private nested (p: CPat) =
    let sub ps = ps |> List.exists (fun q -> not (irrefutable q))

    match p with
    | CPCtor(_, _, ps)
    | CPTuple ps -> sub ps
    | CPRecord(_, fs) -> sub (List.map snd fs)
    | CPAs(q, _, _) -> nested q
    | CPOr(a, b) -> nested a || nested b
    | _ -> false

type private Row =
    { id: int
      pats: CPat list
      guard: CExpr option
      body: CExpr
      ren: Map<string, string> } // pattern variables, as the columns that hold them

let private splice (j: int) (xs: 'a list) (l: 'a list) = List.take j l @ xs @ List.skip (j + 1) l
let private removeAt (j: int) (l: 'a list) = List.take j l @ List.skip (j + 1) l

/// The decision tree for one match: columns (variables holding the values still to test) and
/// rows (one per clause).
/// What a part of the tree already built becomes where it's needed again.
type private Shared =
    | Copy of tree: CExpr * vars: string list // a small one: copied, with its variables renamed
    | Join of name: string * outer: string list // a join point, jumped to with the variables, then what it reads from outside

let private lowerMatch (types: Dictionary<string, TypeInfo>) (resTy: Ty) (cols0: (string * Ty) list) (rows0: Row list) : CExpr =
    let emitted = HashSet<int>()
    let freeVars = cachedFreeVars ()
    let taken = HashSet<string>() // column names given out: a name is bound once
    let varTy = Dictionary<string, Ty>(dict cols0) // every column's type
    let fieldOf = Dictionary<string, string * string * int * int * Ty list>() // a constructor field's column: its value's column, union, case, position, and the case's field types
    let built = Dictionary<obj, Shared>(HashIdentity.Structural)
    // join points in the order they're made: parameters, body, and the parameters that are a
    // field of another (by position: the other's position, union, case, field, case fields)
    let joins = ResizeArray<string * (string * Ty) list * CExpr * (int * (int * string * int * int * Ty list)) list>()

    let fieldTypes (t: Ty) (tag: int) =
        match prune t with
        | TCon(u, args) ->
            match types[u].def with
            | UnionDef cs -> snd cs[tag] |> List.map (substGen args)
            | RecordDef fs -> fs |> List.map (snd >> substGen args)
        | TTuple ts -> ts
        | _ -> []

    let caseCount (t: Ty) =
        match prune t with
        | TCon(u, _) ->
            match types[u].def with
            | UnionDef cs -> cs.Length
            | RecordDef _ -> 1
        | _ -> 1

    // variables and as-patterns go into the row's renaming, leaving wildcards
    let rec norm (col: string) (p: CPat) (ren: Map<string, string>) =
        match p with
        | CPVar(x, _) -> CPWild, ren.Add(x, col)
        | CPAs(q, x, _) -> norm col q (ren.Add(x, col))
        | p -> p, ren

    // the names of the new columns: the first row's own variable where it has one there (and
    // it isn't a column elsewhere in the tree already)
    let names (pats: CPat list) =
        pats
        |> List.map (fun q ->
            match q with
            | CPVar(x, _)
            | CPAs(_, x, _) when taken.Add x -> x
            | _ -> fresh "$m")

    let normalize (cols: (string * Ty) list) (rows: Row list) =
        rows
        |> List.map (fun r ->
            let pats, ren = List.zip cols r.pats |> List.mapFold (fun ren ((c, _), p) -> norm c p ren) r.ren
            { r with pats = pats; ren = ren })

    // the tree for these columns and rows, or what an earlier copy of the same part becomes
    let rec compile (cols: (string * Ty) list) (rows: Row list) : CExpr =
        let rows = normalize cols rows

        // a column every row ignores decides nothing (its variable stays reachable through the
        // rows' renamings): without it, the same part reached on paths that took different
        // values apart is recognized as the same
        let keep = [ for j in 0 .. cols.Length - 1 do if rows |> List.exists (fun r -> r.pats[j] <> CPWild) then yield j ]
        let cols = keep |> List.map (fun j -> cols[j])
        let rows = rows |> List.map (fun r -> { r with pats = keep |> List.map (fun j -> r.pats[j]) })

        // a leaf without a guard depends only on its row; the variables the part reads from the
        // tree are its columns and its rows' pattern variables (as columns)
        let kcols, krows =
            match rows with
            | r :: _ when r.guard.IsNone && r.pats |> List.forall ((=) CPWild) -> [], [ r ]
            | _ -> cols, rows

        let vars = (List.map fst kcols @ (krows |> List.collect (fun r -> r.ren |> Map.toList |> List.map snd))) |> List.distinct
        let index = vars |> List.mapi (fun i v -> v, i) |> Map.ofList

        // which of the variables are fields of what (a join point takes those from their value):
        // another of them by position, or a variable from outside the part by name
        let prov =
            vars
            |> List.map (fun v ->
                match fieldOf.TryGetValue v with
                | true, (p, _, tag, i, _) ->
                    Some(
                        (match index.TryFind p with
                         | Some pi -> Choice1Of2 pi
                         | None -> Choice2Of2 p),
                        tag,
                        i
                    )
                | _ -> None)

        let key =
            box (
                List.map snd kcols,
                krows |> List.map (fun r -> r.id, r.pats, r.guard.IsSome, r.ren |> Map.toList |> List.map (fun (pv, c) -> pv, index[c])),
                prov
            )

        let local (v: string) = mk (CLocal v) varTy[v]

        match built.TryGetValue key with
        | true, Copy(tree, vars0) -> rename (Map.ofList (List.zip vars0 vars)) true tree
        | true, Join(j, outer) -> mk (CJump(j, List.map local vars @ (outer |> List.map local))) resTy
        | _ ->
            let tree = build cols rows

            if size tree <= 12 then
                built[key] <- Copy(tree, vars)
                tree
            else
                // a join point: parameters for the variables, and for what it reads from outside
                let fv = freeVars tree
                let outer = refs tree |> List.filter (fun (x, _) -> fv.Contains x && not (index.ContainsKey x)) |> List.distinctBy fst

                for x, t in outer do
                    varTy[x] <- t

                let ps = (vars @ List.map fst outer) |> List.map (fun v -> v, fresh v, varTy[v])
                let j = fresh "$join"

                // the variables that are fields of another parameter (one of them, or one from outside)
                let position = (vars @ List.map fst outer) |> List.mapi (fun i v -> v, i) |> Map.ofList

                let fields =
                    vars
                    |> List.indexed
                    |> List.choose (fun (i, v) ->
                        match fieldOf.TryGetValue v with
                        | true, (p, u, tag, fi, ftys) when position.ContainsKey p -> Some(i, (position[p], u, tag, fi, ftys))
                        | _ -> None)

                joins.Add(j, ps |> List.map (fun (_, p, t) -> p, t), rename (ps |> List.map (fun (v, p, _) -> v, p) |> Map.ofList) false tree, fields)
                built[key] <- Join(j, List.map fst outer)
                mk (CJump(j, ps |> List.map (fun (v, _, _) -> local v))) resTy

    and build (cols: (string * Ty) list) (rows: Row list) : CExpr =
        let rows = normalize cols rows

        match rows with
        | [] ->
            // only after a failed guard on the last clause: the type checker proved the rest
            mk (CPrim("panic", [ mk (CStr "match failure") tStr ])) resTy
        | r :: rest when r.pats |> List.forall ((=) CPWild) ->
            let copy = not (emitted.Add r.id)
            let body = rename r.ren copy r.body

            match r.guard with
            | None -> body
            | Some g -> mk (CIf(rename r.ren copy g, body, compile cols rest)) resTy
        | r :: _ ->
            let j = r.pats |> List.findIndex ((<>) CPWild)
            let col, colTy = cols[j]

            let isOr (r: Row) =
                match r.pats[j] with
                | CPOr _ -> true
                | _ -> false

            if rows |> List.exists isOr then
                // an or-pattern splits its row in two, sharing the body
                rows
                |> List.collect (fun r ->
                    match r.pats[j] with
                    | CPOr(a, b) -> [ { r with pats = splice j [ a ] r.pats }; { r with pats = splice j [ b ] r.pats } ]
                    | _ -> [ r ])
                |> compile cols
            else
                match r.pats[j] with
                | CPTuple _
                | CPRecord _ ->
                    // the parts become columns of their own
                    let parts (p: CPat) =
                        match p with
                        | CPTuple ps -> ps
                        | CPRecord(_, fs) -> List.map snd fs
                        | _ -> []

                    let ftys = fieldTypes colTy 0
                    let ns = names (parts r.pats[j])

                    for n, t in List.zip ns ftys do
                        varTy[n] <- t

                    let rows' =
                        rows
                        |> List.map (fun r ->
                            match r.pats[j] with
                            | CPWild -> { r with pats = splice j (List.replicate ftys.Length CPWild) r.pats }
                            | p -> { r with pats = splice j (parts p) r.pats })

                    let inner = compile (splice j (List.zip ns ftys) cols) rows'
                    let used = freeVars inner

                    List.foldBack
                        (fun (i, (n, t)) acc ->
                            if used.Contains n then
                                mk (CLet(n, mk (CField(mk (CLocal col) colTy, i)) t, acc)) acc.ty
                            else
                                acc)
                        (List.indexed (List.zip ns ftys))
                        inner
                | CPCtor(u, _, _) ->
                    let tags =
                        rows
                        |> List.choose (fun r ->
                            match r.pats[j] with
                            | CPCtor(_, t, _) -> Some t
                            | _ -> None)
                        |> List.distinct

                    let branch (tag: int) =
                        let ftys = fieldTypes colTy tag

                        let first =
                            rows
                            |> List.pick (fun r ->
                                match r.pats[j] with
                                | CPCtor(_, t, ps) when t = tag -> Some ps
                                | _ -> None)

                        let ns = names first

                        for n, t in List.zip ns ftys do
                            varTy[n] <- t

                        ns |> List.iteri (fun i n -> fieldOf[n] <- (col, u, tag, i, ftys))

                        let rows' =
                            rows
                            |> List.choose (fun r ->
                                match r.pats[j] with
                                | CPCtor(_, t, ps) when t = tag -> Some { r with pats = splice j ps r.pats }
                                | CPCtor _ -> None
                                | _ -> Some { r with pats = splice j (List.replicate ftys.Length CPWild) r.pats })

                        let inner = compile (splice j (List.zip ns ftys) cols) rows'
                        let used = freeVars inner
                        let fps = List.zip ns ftys |> List.map (fun (n, t) -> if used.Contains n then CPVar(n, t) else CPWild)
                        CPCtor(u, tag, fps), None, inner

                    let branches = tags |> List.map branch

                    let branches =
                        if tags.Length = caseCount colTy then
                            branches
                        else
                            let rest =
                                rows
                                |> List.filter (fun r -> r.pats[j] = CPWild)
                                |> List.map (fun r -> { r with pats = removeAt j r.pats })

                            branches @ [ CPWild, None, compile (removeAt j cols) rest ]

                    mk (CMatch(mk (CLocal col) colTy, branches)) resTy
                | lit ->
                    // integers, strings and bools: one case per value, and the rest
                    let lits =
                        rows
                        |> List.choose (fun r ->
                            match r.pats[j] with
                            | CPWild -> None
                            | p -> Some p)
                        |> List.distinct

                    let branch (v: CPat) =
                        let rows' =
                            rows
                            |> List.filter (fun r -> r.pats[j] = v || r.pats[j] = CPWild)
                            |> List.map (fun r -> { r with pats = removeAt j r.pats })

                        v, None, compile (removeAt j cols) rows'

                    let complete =
                        match lit with
                        | CPBool _ -> lits.Length = 2
                        | _ -> false

                    let rest =
                        rows
                        |> List.filter (fun r -> r.pats[j] = CPWild)
                        |> List.map (fun r -> { r with pats = removeAt j r.pats })

                    let branches = List.map branch lits @ (if complete then [] else [ CPWild, None, compile (removeAt j cols) rest ])
                    mk (CMatch(mk (CLocal col) colTy, branches)) resTy

    let tree = compile cols0 rows0

    // a join point jumped to once is just its body, there
    let uses = Dictionary<string, int>()

    let rec count (e: CExpr) =
        match e.k with
        | CJump(j, _) -> uses[j] <- uses.GetValueOrDefault j + 1
        | _ -> ()

        children e.k |> List.iter count

    count tree

    for _, _, b, _ in joins do
        count b

    let once = joins |> Seq.filter (fun (j, _, _, _) -> uses.GetValueOrDefault j = 1) |> Seq.map (fun (j, ps, b, _) -> j, (ps, b)) |> dict

    // a join point jumped to from several places takes a field of another parameter from it
    // (a borrowed projection), so the jumps pass the value alone, without a dup
    let kept = joins |> Seq.filter (fun (j, _, _, _) -> not (once.ContainsKey j) && uses.ContainsKey j) |> List.ofSeq
    let fieldPositions = kept |> List.map (fun (j, _, _, fields) -> j, fields |> List.map fst |> Set.ofList) |> dict

    let rec rewrite (e: CExpr) =
        match e.k with
        | CJump(j, args) when once.ContainsKey j ->
            let ps, b = once[j]

            let actual (a: CExpr) =
                match a.k with
                | CLocal v -> v
                | _ -> failwith "a jump passes variables"

            rewrite (rename (List.zip (List.map fst ps) (List.map actual args) |> Map.ofList) false b)
        | CJump(j, args) when fieldPositions.ContainsKey j ->
            let skip = fieldPositions[j]
            { e with k = CJump(j, args |> List.indexed |> List.filter (fun (i, _) -> not (skip.Contains i)) |> List.map snd) }
        | k -> { e with k = mapChildren rewrite k }

    let define (j, ps: (string * Ty) list, body: CExpr, fields: (int * (int * string * int * int * Ty list)) list) =
        let skip = fields |> List.map fst |> Set.ofList
        let byPos = dict fields

        let rec depth (i: int) =
            match byPos.TryGetValue i with
            | true, (pi, _, _, _, _) -> 1 + depth pi
            | _ -> 0

        // a value's own match outside the ones on its fields
        let body =
            fields
            |> List.groupBy (fun (_, (pi, _, _, _, _)) -> pi)
            |> List.sortByDescending (fst >> depth)
            |> List.fold
                (fun (acc: CExpr) (pi, fs) ->
                    let _, (_, u, tag, _, ftys) = List.head fs

                    let fps =
                        ftys
                        |> List.mapi (fun f t ->
                            match fs |> List.tryFind (fun (_, (_, _, _, fi, _)) -> fi = f) with
                            | Some(i, _) -> CPVar(fst ps[i], t)
                            | None -> CPWild)

                    mk (CMatch(mk (CLocal(fst ps[pi])) (snd ps[pi]), [ CPCtor(u, tag, fps), None, acc ])) acc.ty)
                (rewrite body)

        j, ps |> List.indexed |> List.filter (fun (i, _) -> not (skip.Contains i)) |> List.map snd, body

    // the rest wrap the tree, each defined outside the ones that jump to it (made after it)
    List.foldBack (fun def (acc: CExpr) -> (let j, ps, b = define def in mk (CJoin(j, ps, b, acc)) acc.ty)) kept (rewrite tree)

/// Lowers the matches of every function (inner ones first, so copied bodies are lowered already).
let run (types: Dictionary<string, TypeInfo>) (funs: MFun list) : MFun list =
    let rec lower (e: CExpr) : CExpr =
        let e = { e with k = mapChildren lower e.k }

        match e.k with
        | CMatch(s, cases) when cases |> List.exists (fun (p, _, _) -> nested p) ->
            // a clause per alternative of a top-level or-pattern, sharing its body (by id)
            let rec alts (p: CPat) =
                match p with
                | CPOr(a, b) -> alts a @ alts b
                | p -> [ p ]

            let clauses = cases |> List.mapi (fun i (p, g, b) -> alts p |> List.map (fun p -> i, p, g, b)) |> List.concat

            let rows (pats: CPat -> CPat list) =
                clauses |> List.map (fun (i, p, g, b) -> { id = i; pats = pats p; guard = g; body = b; ren = Map.empty })

            let tree =
                match s.k with
                | CTuple xs when clauses |> List.forall (fun (_, p, _, _) -> (match p with
                                                                                | CPTuple _
                                                                                | CPWild -> true
                                                                                | _ -> false)) ->
                    // match (a, b) with …: the parts are the columns, and no tuple is built
                    let cols = xs |> List.map (fun x -> (match x.k with
                                                         | CLocal v -> v
                                                         | _ -> fresh "$s"), x.ty)

                    let tree =
                        lowerMatch types e.ty cols (rows (fun p ->
                            match p with
                            | CPTuple ps -> ps
                            | _ -> List.replicate xs.Length CPWild))

                    List.foldBack2
                        (fun (x: CExpr) (v, t) acc -> (match x.k with
                                                        | CLocal _ -> acc
                                                        | _ -> mk (CLet(v, x, acc)) acc.ty))
                        xs
                        cols
                        tree
                | CLocal x -> lowerMatch types e.ty [ x, s.ty ] (rows (fun p -> [ p ]))
                | _ ->
                    let v = fresh "$s"
                    mk (CLet(v, s, lowerMatch types e.ty [ v, s.ty ] (rows (fun p -> [ p ])))) e.ty

            if size tree <= 8 * size e + 64 then tree else e
        | _ -> e

    let lowered = funs |> List.map (fun f -> { f with body = lower f.body })
    sizes.Clear()
    lowered
