/// Match lowering: a match whose patterns nest, or that takes a tuple apart, becomes a tree of
/// one-level matches on variables (a decision tree). No subterm is tested twice, no tuple is built
/// for the scrutinee, and every cell the match takes apart is matched on its own, which is where
/// reference counting specializes the drop and reuses the cell.
///
/// A part of the tree reached on several paths (the same rows left, reading the same columns) is
/// built once: a small one is copied to each path, a larger one becomes a join point that the
/// paths jump to, so the tree's size stays close to the match's.
open Types.Ty
open Core.Ir
open Core.Program

let rec private size (e: CExpr) : int = 1 + List.sumBy size (children e.k)

let rec private renamePat (rn: string -> string) (p: CPat) : CPat =
  match p with
  | CPVar(x, t) -> CPVar(rn x, t)
  | CPAs(q, x, t) -> CPAs(renamePat rn q, rn x, t)
  | CPTuple ps -> CPTuple(List.map (renamePat rn) ps)
  | CPRecord(r, fs) -> CPRecord(r, List.map (fun (n, q) -> (n, renamePat rn q)) fs)
  | CPCtor(u, tag, ps) -> CPCtor(u, tag, List.map (renamePat rn) ps)
  | CPOr(a, b) -> CPOr(renamePat rn a, renamePat rn b)
  | q -> q

/// e with variables renamed: with freshNames, its binders get fresh names (a body copied to a
/// second place keeps names unique); free variables in m take the mapped name.
let private rename (fresh: string -> string) (m0: Map<string, string>) (freshNames: bool) (e: CExpr) : CExpr =
  let m = if freshNames then List.fold (fun (acc: Map<string, string>) x -> Map.add x (fresh x) acc) m0 (List.distinct (binders e)) else m0
  if Map.isEmpty m then
    e
  else
    let rn (x: string) = Option.defaultValue x (Map.tryFind x m)
    let pars (ps: list<string * Ty>) = List.map (fun (x, t) -> (rn x, t)) ps
    let rec go (e: CExpr) : CExpr =
      let k =
        match e.k with
        | CLocal x -> CLocal(rn x)
        | CLam(ps, b) -> CLam(pars ps, go b)
        | CLetFun(n, r, ps, b, rest) ->
          let b2 = go b
          CLetFun(rn n, r, pars ps, b2, go rest)
        | CLetRec(fs, rest) ->
          let fs2 = List.map (fun (n, ps, b) -> (rn n, pars ps, go b)) fs
          CLetRec(fs2, go rest)
        | CLet(x, v, b) ->
          let v2 = go v
          CLet(rn x, v2, go b)
        | CLetMut(x, v, b) ->
          let v2 = go v
          CLetMut(rn x, v2, go b)
        | CFor(x, a, s, b, body) ->
          let a2 = go a
          let s2 = go s
          let b2 = go b
          CFor(rn x, a2, s2, b2, go body)
        | CAssign(x, v) -> CAssign(rn x, go v)
        | CArraySet(x, i, v) ->
          let i2 = go i
          CArraySet(rn x, i2, go v)
        | CMatch(s, cases) ->
          let s2 = go s
          CMatch(s2, List.map (fun (p, g, b) -> (renamePat rn p, Option.map go g, go b)) cases)
        | CJoin(j, ps, b, r) ->
          let b2 = go b
          CJoin(j, pars ps, b2, go r)
        | other -> mapChildren go other
      { e with k = k }
    go e

let rec private irrefutable (p: CPat) : bool =
  match p with
  | CPWild
  | CPVar _ -> true
  | CPAs(q, _, _) -> irrefutable q
  | CPTuple ps -> List.forall irrefutable ps
  | CPRecord(_, fs) -> List.forall (fun (_, q) -> irrefutable q) fs
  | _ -> false

// a pattern that tests something below its top: Node (Red, Node _, …), x :: y :: rest
let rec private nested (p: CPat) : bool =
  let sub (ps: list<CPat>) = List.exists (fun q -> not (irrefutable q)) ps
  match p with
  | CPCtor(_, _, ps)
  | CPTuple ps -> sub ps
  | CPRecord(_, fs) -> sub (List.map snd fs)
  | CPAs(q, _, _) -> nested q
  | CPOr(a, b) -> nested a || nested b
  | _ -> false

let private isWild (p: CPat) : bool =
  match p with
  | CPWild -> true
  | _ -> false

// a literal pattern's value equal to another's
let private sameLit (a: CPat) (b: CPat) : bool =
  match (a, b) with
  | (CPInt x, CPInt y) -> x = y
  | (CPStr x, CPStr y) -> x = y
  | (CPBool x, CPBool y) -> x = y
  | _ -> false

// a pattern as text, for the key of a part of the tree (patterns there are normalized: no
// variables, no as-patterns)
let rec private patKey (p: CPat) : string =
  match p with
  | CPWild -> "_"
  | CPVar(x, _) -> "v" + x
  | CPInt n -> $"i{n}"
  | CPStr s -> $"s{String.length s}:{s}"
  | CPBool b -> if b then "T" else "F"
  | CPTuple ps -> "(" + String.join "," (List.map patKey ps) + ")"
  | CPRecord(r, fs) -> "{" + r + ":" + String.join "," (List.map (fun (n, q) -> n + "=" + patKey q) fs) + "}"
  | CPCtor(u, tag, ps) -> $"#{u}.{tag}(" + String.join "," (List.map patKey ps) + ")"
  | CPOr(a, b) -> "[" + patKey a + "|" + patKey b + "]"
  | CPAs(q, x, _) -> patKey q + "@" + x

// a clause as the tree has it: its patterns for the columns left, its guard and body, and its
// pattern variables as the columns that hold them
type private Row = { id: int; pats: list<CPat>; guard: option<CExpr>; body: CExpr; ren: Map<string, string> }

let private splice (j: int) (xs: list<'a>) (l: list<'a>) : list<'a> = List.concat [ List.take j l; xs; List.skip (j + 1) l ]

let private dropAt (j: int) (l: list<'a>) : list<'a> = List.append (List.take j l) (List.skip (j + 1) l)

// what a part of the tree already built becomes where it's needed again: a small one copied (with
// its variables renamed), or a join point jumped to with the variables, then what it reads from
// outside
type private Shared =
  | Copy of CExpr * list<string>
  | Join of string * list<string>

// a join point made for a part of the tree: its name, parameters and body, and the parameters
// that are a field of another (by position: the other's position, union, case, field, case
// fields)
type private JoinDef = { name: string; ps: list<string * Ty>; body: CExpr; fields: list<int * (int * string * int * int * list<Ty>)> }

// groups by key, the keys in the order first seen
let private groupBy (key: 'a -> int) (xs: list<'a>) : list<int * list<'a>> =
  let keys = List.distinct (List.map key xs)
  List.map (fun k -> (k, List.filter (fun x -> key x = k) xs)) keys

// the decision tree for one match: columns (variables holding the values still to test) and rows
// (one per clause)
let private lowerMatch (types: Map<string, TypeInfo>) (fresh: string -> string) (resTy: Ty) (cols0: list<string * Ty>) (rows0: list<Row>) : CExpr =
  let v = Types.Vars.make ()
  let emitted = ref Set.empty
  // column names given out: a name is bound once
  let taken = ref Set.empty
  // every column's type
  let varTy = ref (Map.ofList cols0)
  // a constructor field's column: its value's column, union, case, position, and the case's field
  // types
  let fieldOf = ref Map.empty
  let built = ref Map.empty
  // join points in the order they're made
  let joins = Buffer.empty
  let fieldTypes (t: Ty) (tag: int) : list<Ty> =
    match t with
    | TCon(u, args) ->
      match (Map.find u types).def with
      | UnionDef cs -> List.map (Types.Norm.substGen v args) (snd (List.item tag cs))
      | RecordDef fs -> List.map (fun (_, ft) -> Types.Norm.substGen v args ft) fs
    | TTuple ts -> ts
    | _ -> []
  let caseCount (t: Ty) : int =
    match t with
    | TCon(u, _) ->
      match (Map.find u types).def with
      | UnionDef cs -> List.length cs
      | RecordDef _ -> 1
    | _ -> 1
  // variables and as-patterns go into the row's renaming, leaving wildcards
  let rec norm (col: string) (p: CPat) (ren: Map<string, string>) : CPat * Map<string, string> =
    match p with
    | CPVar(x, _) -> (CPWild, Map.add x col ren)
    | CPAs(q, x, _) -> norm col q (Map.add x col ren)
    | other -> (other, ren)
  // the names of the new columns: the first row's own variable where it has one there (and it
  // isn't a column elsewhere in the tree already)
  let names (pats: list<CPat>) : list<string> =
    let one (q: CPat) : string =
      match q with
      | CPVar(x, _)
      | CPAs(_, x, _) when not (Set.contains x taken.Value) ->
        taken.Value <- Set.add x taken.Value
        x
      | _ -> fresh "$m"
    List.map one pats
  let normalize (cols: list<string * Ty>) (rows: list<Row>) : list<Row> =
    let one (r: Row) : Row =
      let step (acc: list<CPat> * Map<string, string>) (cp: (string * Ty) * CPat) =
        let (ps, ren) = acc
        let ((c, _), p) = cp
        let (q, ren2) = norm c p ren
        (q :: ps, ren2)
      let (rev, ren) = List.fold step ([], r.ren) (List.zip cols r.pats)
      { r with pats = List.rev rev; ren = ren }
    List.map one rows
  let local (x: string) = mk (CLocal x) (Map.find x varTy.Value)
  // the tree for these columns and rows, or what an earlier copy of the same part becomes
  let rec compile (cols0: list<string * Ty>) (rows0: list<Row>) : CExpr =
    let rows1 = normalize cols0 rows0
    // a column every row ignores decides nothing (its variable stays reachable through the rows'
    // renamings): without it, the same part reached on paths that took different values apart is
    // recognized as the same
    let keep = List.filter (fun j -> List.exists (fun (r: Row) -> not (isWild (List.item j r.pats))) rows1) (List.init (List.length cols0) (fun j -> j))
    let cols = List.map (fun j -> List.item j cols0) keep
    let rows = List.map (fun (r: Row) -> { r with pats = List.map (fun j -> List.item j r.pats) keep }) rows1
    // a leaf without a guard depends only on its row; the variables the part reads from the tree
    // are its columns and its rows' pattern variables (as columns)
    let (kcols, krows) =
      match rows with
      | r :: _ when Option.isNone r.guard && List.forall isWild r.pats -> ([], [ r ])
      | _ -> (cols, rows)
    let vars = List.distinct (List.append (List.map fst kcols) (List.collect (fun (r: Row) -> List.map snd (Map.toList r.ren)) krows))
    let index = Map.ofList (List.mapi (fun i x -> (x, i)) vars)
    // which of the variables are fields of what (a join point takes those from their value):
    // another of them by position, or a variable from outside the part by name
    let provOf (x: string) : string =
      match Map.tryFind x fieldOf.Value with
      | Some(p, _, tag, i, _) ->
        match Map.tryFind p index with
        | Some pi -> $"p{pi}.{tag}.{i}"
        | None -> $"o{p}.{tag}.{i}"
      | None -> "-"
    let rowKey (r: Row) : string =
      let renKey = String.join "," (List.map (fun (pv, c) -> pv + "=" + $"{Map.find c index}") (Map.toList r.ren))
      $"{r.id}:" + String.join "," (List.map patKey r.pats) + (if Option.isSome r.guard then ":g:" else ":-:") + renKey
    let key = String.join ";" (List.map (fun (_, t) -> Types.Show.showFull v t) kcols) + "|" + String.join ";" (List.map rowKey krows) + "|" + String.join ";" (List.map provOf vars)
    match Map.tryFind key built.Value with
    | Some(Copy(tree, vars0)) -> rename fresh (Map.ofList (List.zip vars0 vars)) true tree
    | Some(Join(j, outer)) -> mk (CJump(j, List.append (List.map local vars) (List.map local outer))) resTy
    | None ->
      let tree = build cols rows
      if size tree <= 12 then
        built.Value <- Map.add key (Copy(tree, vars)) built.Value
        tree
      else
        // a join point: parameters for the variables, and for what it reads from outside
        let fv = freeVars tree
        // a `let mutable` the tree assigns stays itself: a parameter would be a copy
        let rec assigned (e: CExpr) : list<string> =
          match e.k with
          | CAssign(x, _)
          | CArraySet(x, _, _) -> x :: List.collect assigned (children e.k)
          | k -> List.collect assigned (children k)
        let assignedSet = Set.ofList (assigned tree)
        let candidates = List.filter (fun (x, _) -> Set.contains x fv && not (Map.containsKey x index) && not (Set.contains x assignedSet)) (refs tree)
        let outer = List.fold (fun (acc: list<string * Ty>) (c: string * Ty) -> if List.exists (fun (y, _) -> y = fst c) acc then acc else List.append acc [ c ]) [] candidates
        for (x, t) in outer do
          varTy.Value <- Map.add x t varTy.Value
        let all = List.append vars (List.map fst outer)
        let ps = List.map (fun x -> (x, fresh x, Map.find x varTy.Value)) all
        let j = fresh "$join"
        // the variables that are fields of another parameter (one of them, or one from outside)
        let position = Map.ofList (List.mapi (fun i x -> (x, i)) all)
        let fieldAt (ix: int * string) : option<int * (int * string * int * int * list<Ty>)> =
          let (i, x) = ix
          match Map.tryFind x fieldOf.Value with
          | Some(p, u, tag, fi, ftys) ->
            match Map.tryFind p position with
            | Some pp -> Some(i, (pp, u, tag, fi, ftys))
            | None -> None
          | None -> None
        let fields = List.choose fieldAt (List.indexed vars)
        let body = rename fresh (Map.ofList (List.map (fun (x, p, _) -> (x, p)) ps)) false tree
        Buffer.push { name = j; ps = List.map (fun (_, p, t) -> (p, t)) ps; body = body; fields = fields } joins
        built.Value <- Map.add key (Join(j, List.map fst outer)) built.Value
        mk (CJump(j, List.map (fun (x, _, _) -> local x) ps)) resTy
  and build (cols: list<string * Ty>) (rows0: list<Row>) : CExpr =
    let rows = normalize cols rows0
    match rows with
    | [] ->
      // only after a failed guard on the last clause: the type checker proved the rest
      mk (CPrim("panic", [ mk (CStr "match failure") tStr ])) resTy
    | r :: rest when List.forall isWild r.pats ->
      let copy = Set.contains r.id emitted.Value
      emitted.Value <- Set.add r.id emitted.Value
      let body = rename fresh r.ren copy r.body
      match r.guard with
      | None -> body
      | Some gd ->
        let g2 = rename fresh r.ren copy gd
        mk (CIf(g2, body, compile cols rest)) resTy
    | r :: _ ->
      let j = List.findIndex (fun p -> not (isWild p)) r.pats
      let (col, colTy) = List.item j cols
      let isOr (row: Row) : bool =
        match List.item j row.pats with
        | CPOr _ -> true
        | _ -> false
      if List.exists isOr rows then
        // an or-pattern splits its row in two, sharing the body
        let split (row: Row) : list<Row> =
          match List.item j row.pats with
          | CPOr(a, b) -> [ { row with pats = splice j [ a ] row.pats }; { row with pats = splice j [ b ] row.pats } ]
          | _ -> [ row ]
        compile cols (List.collect split rows)
      else
        match List.item j r.pats with
        | CPTuple _
        | CPRecord _ ->
          // the parts become columns of their own
          let parts (p: CPat) : list<CPat> =
            match p with
            | CPTuple ps -> ps
            | CPRecord(_, fs) -> List.map snd fs
            | _ -> []
          let ftys = fieldTypes colTy 0
          let ns = names (parts (List.item j r.pats))
          for (n, t) in List.zip ns ftys do
            varTy.Value <- Map.add n t varTy.Value
          let widen (row: Row) : Row =
            match List.item j row.pats with
            | CPWild -> { row with pats = splice j (List.replicate (List.length ftys) CPWild) row.pats }
            | p -> { row with pats = splice j (parts p) row.pats }
          let inner = compile (splice j (List.zip ns ftys) cols) (List.map widen rows)
          let used = freeVars inner
          let bind (acc: CExpr) (ix: int * (string * Ty)) : CExpr =
            let (i, (n, t)) = ix
            if Set.contains n used then mk (CLet(n, mk (CField(mk (CLocal col) colTy, i)) t, acc)) acc.ty else acc
          List.fold bind inner (List.rev (List.indexed (List.zip ns ftys)))
        | CPCtor(u, _, _) ->
          let tagOf (row: Row) : option<int> =
            match List.item j row.pats with
            | CPCtor(_, t, _) -> Some t
            | _ -> None
          let tags = List.distinct (List.choose tagOf rows)
          let branch (tag: int) : CPat * option<CExpr> * CExpr =
            let ftys = fieldTypes colTy tag
            let fieldsOf (row: Row) : option<list<CPat>> =
              match List.item j row.pats with
              | CPCtor(_, t, ps) -> if t = tag then Some ps else None
              | _ -> None
            let first = Option.get (List.tryPick fieldsOf rows)
            let ns = names first
            for (n, t) in List.zip ns ftys do
              varTy.Value <- Map.add n t varTy.Value
            List.iteri (fun i n -> fieldOf.Value <- Map.add n (col, u, tag, i, ftys) fieldOf.Value) ns
            let narrow (row: Row) : option<Row> =
              match List.item j row.pats with
              | CPCtor(_, t, ps) -> if t = tag then Some { row with pats = splice j ps row.pats } else None
              | _ -> Some { row with pats = splice j (List.replicate (List.length ftys) CPWild) row.pats }
            let inner = compile (splice j (List.zip ns ftys) cols) (List.choose narrow rows)
            let used = freeVars inner
            let fps = List.map (fun (n, t) -> if Set.contains n used then CPVar(n, t) else CPWild) (List.zip ns ftys)
            (CPCtor(u, tag, fps), None, inner)
          let branches = List.map branch tags
          let all =
            if List.length tags = caseCount colTy then
              branches
            else
              let rest = List.map (fun (row: Row) -> { row with pats = dropAt j row.pats }) (List.filter (fun (row: Row) -> isWild (List.item j row.pats)) rows)
              List.append branches [ (CPWild, None, compile (dropAt j cols) rest) ]
          mk (CMatch(mk (CLocal col) colTy, all)) resTy
        | lit ->
          // integers, strings and bools: one case per value, and the rest
          let litOf (row: Row) : option<CPat> =
            match List.item j row.pats with
            | CPWild -> None
            | p -> Some p
          let addLit (acc: list<CPat>) (p: CPat) = if List.exists (sameLit p) acc then acc else List.append acc [ p ]
          let lits = List.fold addLit [] (List.choose litOf rows)
          let branch (value: CPat) : CPat * option<CExpr> * CExpr =
            let keepRow (row: Row) = sameLit (List.item j row.pats) value || isWild (List.item j row.pats)
            let rows2 = List.map (fun (row: Row) -> { row with pats = dropAt j row.pats }) (List.filter keepRow rows)
            (value, None, compile (dropAt j cols) rows2)
          let complete =
            match lit with
            | CPBool _ -> List.length lits = 2
            | _ -> false
          let rest = List.map (fun (row: Row) -> { row with pats = dropAt j row.pats }) (List.filter (fun (row: Row) -> isWild (List.item j row.pats)) rows)
          let branches = List.map branch lits
          let all = if complete then branches else List.append branches [ (CPWild, None, compile (dropAt j cols) rest) ]
          mk (CMatch(mk (CLocal col) colTy, all)) resTy
  let tree = compile cols0 rows0
  // a join point jumped to once is just its body, there
  let uses = ref Map.empty
  let rec count (e: CExpr) =
    match e.k with
    | CJump(j, _) -> uses.Value <- Map.add j (Option.defaultValue 0 (Map.tryFind j uses.Value) + 1) uses.Value
    | _ -> ()
    List.iter count (children e.k)
  count tree
  let defs = Array.toList (Buffer.toArray joins)
  for d in defs do
    count d.body
  let usesOf (j: string) = Option.defaultValue 0 (Map.tryFind j uses.Value)
  let once = Map.ofList (List.map (fun (d: JoinDef) -> (d.name, d)) (List.filter (fun (d: JoinDef) -> usesOf d.name = 1) defs))
  // a join point jumped to from several places takes a field of another parameter from it (a
  // borrowed projection), so the jumps pass the value alone, without a dup
  let kept = List.filter (fun (d: JoinDef) -> not (Map.containsKey d.name once) && Map.containsKey d.name uses.Value) defs
  let fieldPositions = Map.ofList (List.map (fun (d: JoinDef) -> (d.name, Set.ofList (List.map fst d.fields))) kept)
  let rec rewrite (e: CExpr) : CExpr =
    match e.k with
    | CJump(j, args) when Map.containsKey j once ->
      let d = Map.find j once
      let actual (a: CExpr) : string =
        match a.k with
        | CLocal x -> x
        | _ -> panic "Decide: a jump passes variables"
      rewrite (rename fresh (Map.ofList (List.zip (List.map fst d.ps) (List.map actual args))) false d.body)
    | CJump(j, args) when Map.containsKey j fieldPositions ->
      let skip = Map.find j fieldPositions
      { e with k = CJump(j, List.map snd (List.filter (fun (i, _) -> not (Set.contains i skip)) (List.indexed args))) }
    | k -> { e with k = mapChildren rewrite k }
  let define (d: JoinDef) : string * list<string * Ty> * CExpr =
    let skip = Set.ofList (List.map fst d.fields)
    let byPos = Map.ofList d.fields
    let rec depth (i: int) : int =
      match Map.tryFind i byPos with
      | Some(pi, _, _, _, _) -> 1 + depth pi
      | None -> 0
    // a value's own match outside the ones on its fields
    let groups = groupBy (fun (_, (pi, _, _, _, _)) -> pi) d.fields
    let sorted = List.sortBy (fun (pi, _) -> -(depth pi)) groups
    let wrap (acc: CExpr) (gr: int * list<int * (int * string * int * int * list<Ty>)>) : CExpr =
      let (pi, fs) = gr
      let (_, (_, u, tag, _, ftys)) = List.head fs
      let fpOf (f: int) (t: Ty) : CPat =
        match List.tryFind (fun (_, (_, _, _, fi, _)) -> fi = f) fs with
        | Some(i, _) -> CPVar(fst (List.item i d.ps), t)
        | None -> CPWild
      let fps = List.mapi fpOf ftys
      let (pv, pt) = List.item pi d.ps
      mk (CMatch(mk (CLocal pv) pt, [ (CPCtor(u, tag, fps), None, acc) ])) acc.ty
    let body = List.fold wrap (rewrite d.body) sorted
    (d.name, List.map snd (List.filter (fun (i, _) -> not (Set.contains i skip)) (List.indexed d.ps)), body)
  // the rest wrap the tree, each defined outside the ones that jump to it (made after it)
  let wrapJoin (acc: CExpr) (d: JoinDef) : CExpr =
    let (j, ps, b) = define d
    mk (CJoin(j, ps, b, acc)) acc.ty
  List.fold wrapJoin (rewrite tree) (List.rev kept)

// a pattern a tuple's match takes apart as columns: a tuple's, or a wildcard
let private tupleOrWild (p: CPat) : bool =
  match p with
  | CPTuple _
  | CPWild -> true
  | _ -> false

/// Lowers the matches of every function (inner ones first, so copied bodies are lowered already).
let run (types: Map<string, TypeInfo>) (funs: list<MFun>) : list<MFun> =
  let one (f: MFun) : MFun =
    // fresh names numbered per function: a function's code doesn't depend on the others'
    let counter = ref 0
    let fresh (x: string) : string =
      counter.Value <- counter.Value + 1
      $"{x}.d{counter.Value}"
    let rec lower (e0: CExpr) : CExpr =
      let e = { e0 with k = mapChildren lower e0.k }
      match e.k with
      | CMatch(s, cases) when List.exists (fun (p, _, _) -> nested p) cases ->
        // a clause per alternative of a top-level or-pattern, sharing its body (by id)
        let rec alts (p: CPat) : list<CPat> =
          match p with
          | CPOr(a, b) -> List.append (alts a) (alts b)
          | q -> [ q ]
        let clauses = List.concat (List.mapi (fun i (p, g, b) -> List.map (fun q -> (i, q, g, b)) (alts p)) cases)
        let rows (pats: CPat -> list<CPat>) : list<Row> = List.map (fun (i, p, g, b) -> { id = i; pats = pats p; guard = g; body = b; ren = Map.empty }) clauses
        let tree =
          match s.k with
          | CTuple xs when List.forall (fun (_, p, _, _) -> tupleOrWild p) clauses ->
            // match (a, b) with …: the parts are the columns, and no tuple is built
            let column (x: CExpr) : string * Ty =
              match x.k with
              | CLocal name -> (name, x.ty)
              | _ -> (fresh "$s", x.ty)
            let cols = List.map column xs
            let partsOf (p: CPat) : list<CPat> =
              match p with
              | CPTuple ps -> ps
              | _ -> List.replicate (List.length xs) CPWild
            let t = lowerMatch types fresh e.ty cols (rows partsOf)
            let bind (acc: CExpr) (xc: CExpr * (string * Ty)) : CExpr =
              let (x, (name, _)) = xc
              match x.k with
              | CLocal _ -> acc
              | _ -> mk (CLet(name, x, acc)) acc.ty
            List.fold bind t (List.rev (List.zip xs cols))
          | CLocal x -> lowerMatch types fresh e.ty [ (x, s.ty) ] (rows (fun p -> [ p ]))
          | _ ->
            let name = fresh "$s"
            mk (CLet(name, s, lowerMatch types fresh e.ty [ (name, s.ty) ] (rows (fun p -> [ p ])))) e.ty
        if size tree <= 8 * size e + 64 then tree else e
      | _ -> e
    { f with body = lower f.body }
  // each function on the pool (decision 76)
  Array.toList (Array.Parallel.map one (Array.ofList funs))
