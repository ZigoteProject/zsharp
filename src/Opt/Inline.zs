/// Inlining: a call to a small function that doesn't call itself becomes a copy of its body, its
/// parameters bound to the arguments. The caller's reference counting then sees the callee's
/// constructors next to the cells the caller takes apart, and builds them in place (Perceus
/// reuse): an insert into a unique tree allocates nothing on its way down.
// ponytail: one level, by size alone; a cost model (size x call sites) when code size matters
open Types.Ty
open Core.Ir
open Core.Program

let rec private size (e: CExpr) : int = 1 + List.sumBy size (children e.k)

let rec private renamePat (rn: string -> string / <>) (p: CPat) : CPat =
  match p with
  | CPVar(x, t) -> CPVar(rn x, t)
  | CPAs(q, x, t) -> CPAs(renamePat rn q, rn x, t)
  | CPTuple ps -> CPTuple(List.map (renamePat rn) ps)
  | CPRecord(r, fs) -> CPRecord(r, List.map (fun (n, q) -> (n, renamePat rn q)) fs)
  | CPCtor(u, tag, ps) -> CPCtor(u, tag, List.map (renamePat rn) ps)
  | CPOr(a, b) -> CPOr(renamePat rn a, renamePat rn b)
  | q -> q

/// A copy of e for another place: what it binds gets new names (names stay unique in the function
/// it goes into), the parameters in m their arguments' names, and line marks go (they would point
/// into the callee's file).
let private copy (fresh: string -> string / <>) (m0: Map<string, string>) (e: CExpr) : CExpr =
  let m = List.fold (fun (acc: Map<string, string>) x -> Map.add x (fresh x) acc) m0 (List.distinct (binders e))
  let rn (x: string) = Option.defaultValue x (Map.tryFind x m)
  let pars (ps: list<string * Ty>) = List.map (fun (x, t) -> (rn x, t)) ps
  let rec go (e: CExpr) : CExpr =
    match e.k with
    | CLine(_, inner) -> go inner
    | k0 ->
      let k =
        match k0 with
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
        | CHandle(l, b, cls, (r, rt), rb) ->
          let b2 = go b
          let clause (c: int * list<string * Ty> * (string * Ty) * CExpr) =
            match c with
            | (op, ps, (kn, kt), body) -> (op, pars ps, (rn kn, kt), go body)
          let cls2 = List.map clause cls
          CHandle(l, b2, cls2, (rn r, rt), go rb)
        | other -> mapChildren go other
      { e with k = k }
  go e

/// Uncurrying: a function whose body is a lambda takes the lambda's parameters too, so `let add x =
/// fun y -> x + y` has two parameters and `add 1 2` is one call (the closure it returned only held
/// x: nothing runs at another time). A lambda returning a lambda merges the same way. Functions
/// called from outside (main, tests, C exports) keep their signatures. A function with effects
/// keeps its own parameters: its call is where it performs them.
let uncurry (fixedNames: Set<string>) (funs: list<MFun>) : list<MFun> =
  let v = Types.Vars.make ()
  let rec lambda (e: CExpr) : option<list<string * Ty> * CExpr * Ty> =
    match e.k with
    | CLam(ps, b) -> Some(ps, b, e.ty)
    | CLine(_, inner) -> lambda inner
    | _ -> None
  // the row of a function type's n-th arrow
  let rec rowAt (n: int) (t: Ty) : Ty =
    match t with
    | TFun(_, r, row) -> if n <= 1 then row else rowAt (n - 1) r
    | _ -> rowEmpty
  // the parameters and body after merging, and the row of the body
  let rec merge (ps: list<string * Ty>) (body: CExpr) (row: Ty) : list<string * Ty> * CExpr * Ty =
    match lambda body with
    | Some(more, b, t) ->
      if Types.Norm.isRowEmpty v row then merge (List.append ps more) b (rowAt (List.length more) t) else (ps, body, row)
    | None -> (ps, body, row)
  let inside (f: MFun) : CExpr =
    let localTypes = localTypesIn f.body
    let rowOf (n: string) (arity: int) =
      match Map.tryFind n localTypes with
      | Some t -> rowAt arity t
      | None -> rowEmpty
    let rec go (e: CExpr) : CExpr =
      let k =
        match mapChildren go e.k with
        | CLam(ps, b) ->
          match merge ps b (rowAt (List.length ps) e.ty) with
          | (ps2, b2, _) -> CLam(ps2, b2)
        | CLetFun(n, r, ps, b, rest) ->
          match merge ps b (rowOf n (List.length ps)) with
          | (ps2, b2, _) -> CLetFun(n, r, ps2, b2, rest)
        | CLetRec(fs, rest) ->
          let one (fd: string * list<string * Ty> * CExpr) =
            match fd with
            | (n, ps, b) ->
              match merge ps b (rowOf n (List.length ps)) with
              | (ps2, b2, _) -> (n, ps2, b2)
          CLetRec(List.map one fs, rest)
        | other -> other
      { e with k = k }
    go f.body
  let one (f: MFun) : MFun =
    let body = inside f
    if List.isEmpty f.pars || Set.contains f.name fixedNames then
      { f with body = body }
    else
      match merge f.pars body f.row with
      | (ps, b, row) -> { f with pars = ps; ret = b.ty; row = row; body = b }
  List.map one funs

/// Inlines calls to small functions that don't call themselves. Callees are done first, so a copy
/// carries what was inlined into it. mayInline caller callee: whether this callee may be (a
/// module's code holds none of another module's functions, the driver says); kept: functions never
/// inlined into others ([<Target>] and [<Multiversion>] ones, whose code is for CPU features their
/// callers may not have).
let runWith (kept: string -> bool / <>) (mayInline: string -> string -> bool / <>) (funs: list<MFun>) : list<MFun> =
  let byName = Map.ofList (List.map (fun (f: MFun) -> (f.name, f)) funs)
  let rec calls (e: CExpr) : list<string> =
    let own =
      match e.k with
      | CGlobal(g, _) -> [ g ]
      | _ -> []
    List.append own (List.collect calls (children e.k))
  // a local function in the body would be copied (and lifted) once per call site
  let rec localFunctions (e: CExpr) : bool =
    match e.k with
    | CLetFun _
    | CLetRec _ -> true
    | k -> List.exists localFunctions (children k)
  // an Iter impl's forEach is inlined whatever its size (0017): a for loop over the type is then
  // one loop, its body applied in place by Simplify
  let forEach (name: string) = String.startsWith "Iter<" name && String.contains ">#forEach" name
  let candidate (f: MFun) = f.name <> "main" && not (kept f.name) && (size f.body <= 60 || forEach f.name) && not (localFunctions f.body)
  let candidates = Map.ofList (List.map (fun (f: MFun) -> (f.name, List.distinct (calls f.body))) (List.filter candidate funs))
  // not one that can reach itself through others: what a copy carried would depend on which of
  // them was done first, and a function's code must depend on its own callees only
  let reachesItself (f: string) : bool =
    let seen = ref Set.empty
    let rec back (g: string) : bool =
      let step (h: string) =
        if h = f then
          true
        else if Map.containsKey h candidates && not (Set.contains h seen.Value) then
          seen.Value <- Set.add h seen.Value
          back h
        else
          false
      List.exists step (Map.find g candidates)
    back f
  let small = Set.ofList (List.filter (fun f -> not (reachesItself f)) (List.map fst (Map.toList candidates)))
  let finished = ref Map.empty
  let visiting = ref Set.empty
  // new names numbered per function, so a function's code doesn't depend on others' (a build
  // reuses the compiled code of modules that didn't change)
  let counters = ref Map.empty
  let freshIn (f: string) (x: string) : string =
    let c =
      match Map.tryFind f counters.Value with
      | Some c -> c
      | None ->
        let c = ref 0
        counters.Value <- Map.add f c counters.Value
        c
    c.Value <- c.Value + 1
    $"{x}.i{c.Value}"
  // a function's body with its calls to small functions inlined (no small one is in a cycle)
  let rec bodyOf (name: string) : CExpr =
    match Map.tryFind name finished.Value with
    | Some b -> b
    | None ->
      if Set.contains name visiting.Value then
        // in a cycle: as written
        (Map.find name byName).body
      else
        visiting.Value <- Set.add name visiting.Value
        let b = inlineIn name (Map.find name byName).body
        finished.Value <- Map.add name b finished.Value
        b
  and inlineIn (caller: string) (e0: CExpr) : CExpr =
    let e = { e0 with k = mapChildren (inlineIn caller) e0.k }
    match e.k with
    | CApp({ k = CGlobal(g, _) }, args) ->
      if Set.contains g small && g <> caller && List.length args = List.length (Map.find g byName).pars && mayInline caller g then
        let fresh = freshIn caller
        let ps = List.map (fun (p, t) -> (p, fresh p, t)) (Map.find g byName).pars
        let body = copy fresh (Map.ofList (List.map (fun (p, p2, _) -> (p, p2)) ps)) (bodyOf g)
        // the arguments in order, each bound to its parameter
        let bindArg (acc: CExpr) (pa: (string * string * Ty) * CExpr) =
          match pa with
          | ((_, p2, _), a) -> mk (CLet(p2, a, acc)) acc.ty
        List.fold bindArg body (List.rev (List.zip ps args))
      else
        e
    | _ -> e
  List.map (fun (f: MFun) -> { f with body = bodyOf f.name }) funs

let run (kept: string -> bool / <>) (funs: list<MFun>) : list<MFun> = runWith kept (fun _ _ -> true) funs
