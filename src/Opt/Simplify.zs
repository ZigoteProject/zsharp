/// Simplification after inlining. A small function's body copied into its caller often builds a
/// value the caller then takes apart (`match Option.map f o with …`), or applies a lambda the
/// caller passed in. Done at compile time instead, no cell is allocated and no closure built.
///   - Known constructors: a match on a value whose case is known (built right there, bound by a
///     `let`, or taken by an enclosing case) takes its case at compile time.
///   - Case of case: a match on a match (or on an `if`) moves into the inner one's branches, where
///     those that end in a known value take their case at compile time. A case body reached from
///     several branches becomes a join point instead of being copied.
///   - Lambdas: a lambda bound by `let` and only called is applied where it's called.
/// Nothing is evaluated at another time, or more or less often: only matches, branches and
/// bindings move.
// ponytail: no node identity, so what's simplified already is gone through again where case of
// case moves it (the F# compiler remembers those nodes): quadratic at worst, which fuel bounds
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

let rec private joinNames (e: CExpr) : list<string> =
  let own =
    match e.k with
    | CJoin(j, _, _, _) -> [ j ]
    | _ -> []
  List.append own (List.collect joinNames (children e.k))

/// e with free variables renamed by m, and with freshNames, its binders and join points given new
/// names (a copy for another place: names stay unique per program).
let private rename (fresh: string -> string) (m0: Map<string, string>) (freshNames: bool) (e: CExpr) : CExpr =
  let m = if freshNames then List.fold (fun (acc: Map<string, string>) x -> Map.add x (fresh x) acc) m0 (List.distinct (List.append (binders e) (joinNames e))) else m0
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
          CJoin(rn j, pars ps, b2, go r)
        | CJump(j, args) -> CJump(rn j, List.map go args)
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

// what is known about a variable's value: its case, with the variables holding its fields where
// they're known, or a literal
type private Known =
  | KCtor of int * list<option<string>>
  | KLit of CPat

// whether a pattern matches a known value: yes (binding its variables, with their types, to these
// variables), no, or it can't be told at compile time
type private Static =
  | Yes of list<string * Ty * string>
  | No
  | Unknown

let private isNo (s: Static) : bool =
  match s with
  | No -> true
  | _ -> false

let private isUnknown (s: Static) : bool =
  match s with
  | Unknown -> true
  | _ -> false

let private yesBinds (s: Static) : list<string * Ty * string> =
  match s with
  | Yes bs -> bs
  | _ -> []

let private isLiteralPat (p: CPat) : bool =
  match p with
  | CPInt _
  | CPStr _
  | CPBool _ -> true
  | _ -> false

// a literal pattern's value equal to another's
let private sameLit (a: CPat) (b: CPat) : bool =
  match (a, b) with
  | (CPInt x, CPInt y) -> x = y
  | (CPStr x, CPStr y) -> x = y
  | (CPBool x, CPBool y) -> x = y
  | _ -> false

// k: what's known about the value in x (None: nothing); know: what's known about other variables
// (a constructor's fields)
let rec private staticMatch (know: string -> option<Known>) (k: option<Known>) (x: string) (p: CPat) : Static =
  match p with
  | CPWild -> Yes []
  | CPVar(v, t) -> Yes [ (v, t, x) ]
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
    match (k, p) with
    | (Some(KCtor(tag2, fields)), CPCtor(_, tag, ps)) when tag <> tag2 || List.length ps = List.length fields ->
      if tag <> tag2 then
        No
      else
        // every field must match: one that can't makes the pattern fail
        let part (q: CPat) (f: option<string>) : Static =
          match (f, q) with
          | (_, CPWild) -> Yes []
          | (Some fv, _) -> staticMatch know (know fv) fv q
          | (None, _) -> Unknown
        let parts = List.map2 part ps fields
        if List.exists isNo parts then No else if List.exists isUnknown parts then Unknown else Yes(List.collect yesBinds parts)
    | (Some(KLit l), _) -> if isLiteralPat p then (if sameLit p l then Yes [] else No) else Unknown
    | _ -> Unknown

let private literal (e: CExpr) : option<CPat> =
  match e.k with
  | CInt n -> Some(CPInt n)
  | CBool b -> Some(CPBool b)
  | CStr s -> Some(CPStr s)
  | _ -> None

// a value whose evaluation has no effect and can't fail, so it can be dropped when unused
let rec private pureValue (e: CExpr) : bool =
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

let rec private lambdaOf (e: CExpr) : option<list<string * Ty> * CExpr> =
  match e.k with
  | CLam(ps, b) -> Some(ps, b)
  | CLine(_, inner) -> lambdaOf inner
  | _ -> None

// the arguments bound to the parameters, in order, around the body
let private bindArgs (ps: list<string * Ty>) (args: list<CExpr>) (body: CExpr) : CExpr =
  List.fold (fun (acc: CExpr) (pa: (string * Ty) * CExpr) -> mk (CLet(fst (fst pa), snd pa, acc)) acc.ty) body (List.rev (List.zip ps args))

let private bodyOf (c: CPat * option<CExpr> * CExpr) : CExpr =
  match c with
  | (_, _, b) -> b

let private notLocal (a: CExpr) : bool =
  match a.k with
  | CLocal _ -> false
  | _ -> true

// a pattern's variable, the one a constructor's field binds
let private patVarName (q: CPat) : option<string> =
  match q with
  | CPVar(x, _)
  | CPAs(_, x, _) -> Some x
  | _ -> None

let run (types: Map<string, TypeInfo>) (funs: list<MFun>) : list<MFun> =
  let simplifyFun (f: MFun) : MFun =
    // tables of its own: the functions are simplified on the pool
    let v = Types.Vars.make ()
    let fieldTypes (t: Ty) (tag: int) : list<Ty> =
      match t with
      | TCon(u, args) ->
        match (Map.find u types).def with
        | UnionDef cs -> List.map (Types.Norm.substGen v args) (snd (List.item tag cs))
        | RecordDef _
        | CUnionDef _ -> []
      | _ -> []
    // numbered per function: a function's code doesn't depend on the others'
    let counter = ref 0
    let fresh (x: string) : string =
      counter.Value <- counter.Value + 1
      $"{x}.s{counter.Value}"
    let uses (x: string) (e: CExpr) = Set.contains x (freeVars e)
    // variables bound to local functions: a join point can't take one as a parameter (it would
    // become a closure), so a body calling one is copied instead; and mutable variables: a field
    // known to be one could have changed when it's read
    let localFuns = ref Set.empty
    let mutables = ref Set.empty
    let rec collect (e: CExpr) =
      match e.k with
      | CLetFun(n, _, _, _, _) -> localFuns.Value <- Set.add n localFuns.Value
      | CLetRec(fs, _) ->
        for (n, _, _) in fs do
          localFuns.Value <- Set.add n localFuns.Value
      | CLetMut(x, _, _) -> mutables.Value <- Set.add x mutables.Value
      | _ -> ()
      List.iter collect (children e.k)
    collect f.body
    let immutable (a: CExpr) : option<string> =
      match a.k with
      | CLocal y -> if Set.contains y mutables.Value then None else Some y
      | _ -> None
    // each rewrite that builds more code to simplify uses fuel, so the pass always ends
    let fuel = ref (100 + 4 * size f.body)
    let burn () =
      fuel.Value <- fuel.Value - 1
      fuel.Value > 0
    // every use of x in e is a call with n arguments: how many there are (None otherwise)
    let callsOnly (x: string) (n: int) (e: CExpr) : option<int> =
      let calls = ref 0
      let other = ref false
      let rec walk (e: CExpr) =
        match e.k with
        | CApp({ k = CLocal y }, args) when y = x ->
          if List.length args = n then calls.Value <- calls.Value + 1 else other.Value <- true
          List.iter walk args
        | CLocal y when y = x -> other.Value <- true
        | k -> List.iter walk (children k)
      walk e
      if other.Value then None else Some calls.Value
    // e with each call to x (a lambda's name) replaced by the lambda's body, its parameters bound
    // to the arguments; a copy for every call but the last
    let applyAt (x: string) (lam: CExpr) (e: CExpr) : CExpr =
      let arity = List.length (fst (Option.get (lambdaOf lam)))
      let left = ref (Option.defaultValue 0 (callsOnly x arity e))
      let rec go (e: CExpr) : CExpr =
        match e.k with
        | CApp({ k = CLocal y }, args0) when y = x ->
          let args = List.map go args0
          left.Value <- left.Value - 1
          let (ps, b) = Option.get (lambdaOf (if left.Value = 0 then lam else rename fresh Map.empty true lam))
          bindArgs ps args b
        | k -> { e with k = mapChildren go k }
      go e
    let rec simp (env: Map<string, Known>) (e: CExpr) : CExpr =
      match e.k with
      | CLet(x, w, body) ->
        match w.k with
        | CLocal y when not (Set.contains x mutables.Value) && not (Set.contains y mutables.Value) ->
          // let x = y, as an inlined call binds its parameters: y itself, so nothing takes a copy
          // of y (a borrowed parameter stays borrowed)
          simp env (rename fresh (Map.ofList [ (x, y) ]) false body)
        | _ -> simpLet env e x w body
      | CMatch(s, cases) -> matchOf env (simp env s) cases e.ty
      | CIf(c0, t, f) ->
        let c = simp env c0
        let asMatch = [ (CPBool true, None, t); (CPWild, None, f) ]
        match c.k with
        | CBool b -> simp env (if b then t else f)
        | CLocal x when Map.containsKey x env -> matchOf env c asMatch e.ty
        | CLocal x ->
          let t2 = simp (Map.add x (KLit(CPBool true)) env) t
          { e with k = CIf(c, t2, simp (Map.add x (KLit(CPBool false)) env) f) }
        | _ ->
          match (if fuel.Value > 0 then pushed env c asMatch true else None) with
          | Some r when burn () -> simp env r
          | _ ->
            let t2 = simp env t
            { e with k = CIf(c, t2, simp env f) }
      | CApp(h0, args0) ->
        let h = simp env h0
        let args = List.map (simp env) args0
        match lambdaOf h with
        | Some(ps, b) when List.length ps = List.length args -> simp env (bindArgs ps args b)
        | _ -> { e with k = CApp(h, args) }
      | CSeq(a0, b0) ->
        let a = simp env a0
        let b = simp env b0
        if pureValue a then b else { e with k = CSeq(a, b) }
      | k -> { e with k = mapChildren (simp env) k }
    and simpLet (env: Map<string, Known>) (e: CExpr) (x: string) (w0: CExpr) (body: CExpr) : CExpr =
      let w = simp env w0
      let applied =
        match lambdaOf w with
        | Some(ps, lb) ->
          match callsOnly x (List.length ps) body with
          | Some n -> if (n = 1 || (n > 1 && size lb <= 40)) && burn () then Some(simp env (applyAt x w body)) else None
          | None -> None
        | None -> None
      match applied with
      | Some r -> r
      | None ->
        // let x = v in match x with … (or through let y = x, as an inlined call binds its
        // parameters), where v is a match or an if: case of case
        let rec matchOnX (names: Set<string>) (b: CExpr) : option<list<CPat * option<CExpr> * CExpr>> =
          match b.k with
          | CMatch({ k = CLocal y }, cases) when Set.contains y names ->
            let mentions (c: CPat * option<CExpr> * CExpr) =
              let (_, g, cb) = c
              List.exists (fun n -> uses n cb || Option.exists (uses n) g) (Set.toList names)
            if List.exists mentions cases then None else Some cases
          | CLet(y, { k = CLocal z }, rest) when Set.contains z names -> matchOnX (Set.add y names) rest
          | CLine(_, inner) -> matchOnX names inner
          | _ -> None
        match (matchOnX (Set.ofList [ x ]) body, w.k) with
        | (Some cases, _) when Option.isSome (plan env w cases false) && burn () -> simp env (mk (CMatch(w, cases)) e.ty)
        | (_, CCtor(u, tag, args)) when List.exists notLocal args && burn () ->
          // the fields named, so a match on x knows them
          let nameArg (a: CExpr) : CExpr * option<string * CExpr> =
            match a.k with
            | CLocal _ -> (a, None)
            | _ ->
              let t = fresh "$f"
              (mk (CLocal t) a.ty, Some(t, a))
          let named = List.map nameArg args
          let inner = mk (CLet(x, mk (CCtor(u, tag, List.map fst named)) w.ty, body)) e.ty
          let bind (acc: CExpr) (nb: CExpr * option<string * CExpr>) : CExpr =
            match snd nb with
            | Some(t, a) -> mk (CLet(t, a, acc)) acc.ty
            | None -> acc
          simp env (List.fold bind inner (List.rev named))
        | _ ->
          let env2 =
            match w.k with
            | CCtor(_, tag, args) -> Map.add x (KCtor(tag, List.map immutable args)) env
            | CLocal y ->
              match Map.tryFind y env with
              | Some kn -> Map.add x kn env
              | None -> env
            | _ ->
              match literal w with
              | Some l -> Map.add x (KLit l) env
              | None -> env
          let body2 = simp env2 body
          // the body may have become such a match only now
          match matchOnX (Set.ofList [ x ]) body2 with
          | Some cases when Option.isSome (plan env w cases false) && burn () -> simp env (mk (CMatch(w, cases)) e.ty)
          | _ -> if pureValue w && not (uses x body2) then body2 else { e with k = CLet(x, w, body2) }
    and matchOf (env: Map<string, Known>) (s: CExpr) (cases: list<CPat * option<CExpr> * CExpr>) (ty: Ty) : CExpr =
      match s.k with
      | CLocal x when Map.containsKey x env ->
        match select env x s.ty cases ty with
        | Some r -> simp env r
        | None -> plain env s cases ty
      | CCtor(u, tag, args) when burn () ->
        // the fields bound in order, and the value, then the match is on a known variable
        let temp (a: CExpr) : string * option<CExpr> =
          match immutable a with
          | Some w -> (w, None)
          | None -> (fresh "$f", Some a)
        let temps = List.map temp args
        let kv = fresh "$k"
        let value = mk (CCtor(u, tag, List.map2 (fun (a: CExpr) (tv: string * option<CExpr>) -> mk (CLocal(fst tv)) a.ty) args temps)) s.ty
        let inner = mk (CLet(kv, value, mk (CMatch(mk (CLocal kv) s.ty, cases)) ty)) ty
        let bind (acc: CExpr) (tv: string * option<CExpr>) : CExpr =
          match snd tv with
          | Some a -> mk (CLet(fst tv, a, acc)) ty
          | None -> acc
        simp env (List.fold bind inner (List.rev temps))
      | _ when Option.isSome (literal s) && burn () ->
        let kv = fresh "$k"
        simp env (mk (CLet(kv, s, mk (CMatch(mk (CLocal kv) s.ty, cases)) ty)) ty)
      | _ ->
        match (if fuel.Value > 0 then pushed env s cases false else None) with
        | Some r when burn () -> simp env r
        | _ -> plain env s cases ty
    // the match as it is, each case knowing what it took
    and plain (env: Map<string, Known>) (s: CExpr) (cases: list<CPat * option<CExpr> * CExpr>) (ty: Ty) : CExpr =
      let caseEnv (p: CPat) : Map<string, Known> =
        match (s.k, p) with
        | (CLocal x, CPCtor(_, tag, ps)) -> Map.add x (KCtor(tag, List.map patVarName ps)) env
        | (CLocal x, _) -> if isLiteralPat p then Map.add x (KLit p) env else env
        | _ -> env
      match cases with
      | [ (CPBool true, None, t); (CPWild, None, f) ] ->
        let (envT, envF) =
          match s.k with
          | CLocal x -> (Map.add x (KLit(CPBool true)) env, Map.add x (KLit(CPBool false)) env)
          | _ -> (env, env)
        let t2 = simp envT t
        mk (CIf(s, t2, simp envF f)) ty
      | _ ->
        let one (c: CPat * option<CExpr> * CExpr) =
          let (p, g, b) = c
          let env2 = caseEnv p
          let g2 = Option.map (simp env2) g
          (p, g2, simp env2 b)
        mk (CMatch(s, List.map one cases)) ty
    // the cases a value known to be k takes at compile time: the body of the first case it
    // matches, a test of its guard, or (where a case can't be told) the cases left; None when
    // nothing is decided
    and select (env: Map<string, Known>) (x: string) (xty: Ty) (cases: list<CPat * option<CExpr> * CExpr>) (ty: Ty) : option<CExpr> =
      let rec go (cs: list<CPat * option<CExpr> * CExpr>) (dropped: bool) : option<CExpr> =
        match cs with
        | [] -> None
        | (p, g, b) :: rest ->
          match staticMatch (fun w -> Map.tryFind w env) (Map.tryFind x env) x p with
          | No -> go rest true
          | Yes binds ->
            // the pattern's variables bound to what they match (the guard can't see the other
            // cases, so the bindings may enclose them)
            let bind (e: CExpr) = List.fold (fun (acc: CExpr) (w, t, fv) -> mk (CLet(w, mk (CLocal fv) t, acc)) acc.ty) e (List.rev binds)
            match g with
            | None -> Some(bind b)
            | Some gd ->
              let otherwise =
                match go rest true with
                | Some e2 -> e2
                | None -> mk (CMatch(mk (CLocal x) xty, rest)) ty
              Some(bind (mk (CIf(gd, b, otherwise)) ty))
          | Unknown ->
            match fieldMatch env x xty cs ty with
            | Some e2 -> Some e2
            | None -> if dropped then Some(mk (CMatch(mk (CLocal x) xty, cs)) ty) else None
      go cases false
    // a match on a value whose case is known, with patterns that test inside its fields: the same
    // match on the fields themselves, so the value needn't exist
    and fieldMatch (env: Map<string, Known>) (x: string) (xty: Ty) (cases: list<CPat * option<CExpr> * CExpr>) (ty: Ty) : option<CExpr> =
      match Map.tryFind x env with
      | Some(KCtor(tag, fields)) when not (List.isEmpty fields) && List.forall Option.isSome fields ->
        let fs = List.map Option.get fields
        let ftys = fieldTypes xty tag
        let wild = List.map (fun _ -> CPWild) fs
        // a variable for the whole value: the guard renamed, the body binding it
        let whole (w: string) (wt: Ty) (g: option<CExpr>) (b: CExpr) : option<CExpr> * CExpr =
          let g2 = Option.map (rename fresh (Map.ofList [ (w, x) ]) false) g
          (g2, mk (CLet(w, mk (CLocal x) wt, b)) b.ty)
        let rec conv (c: CPat * option<CExpr> * CExpr) : option<option<list<CPat> * option<CExpr> * CExpr>> =
          let (p, g, b) = c
          match p with
          | CPCtor(_, t, ps) -> Some(if t = tag then Some(ps, g, b) else None)
          | CPWild -> Some(Some(wild, g, b))
          | CPVar(w, wt) ->
            let (g2, b2) = whole w wt g b
            Some(Some(wild, g2, b2))
          | CPAs(q, w, wt) ->
            let (g2, b2) = whole w wt g b
            conv (q, g2, b2)
          | _ -> None
        let converted = List.map conv cases
        if List.exists Option.isNone converted || List.length ftys <> List.length fs then
          None
        else
          let cs = List.choose (fun c -> c) (List.choose (fun c -> c) converted)
          let locals = List.map2 (fun fv t -> mk (CLocal fv) t) fs ftys
          match locals with
          | [ one ] -> Some(mk (CMatch(one, List.map (fun (ps, g, b) -> (List.head ps, g, b)) cs)) ty)
          | _ -> Some(mk (CMatch(mk (CTuple locals) (TTuple ftys), List.map (fun (ps, g, b) -> (CPTuple ps, g, b)) cs)) ty)
      | _ -> None
    // whether case of case applies: how many paths of s reach each case; None when no path ends in
    // a value the match resolves
    and plan (env: Map<string, Known>) (s: CExpr) (cases: list<CPat * option<CExpr> * CExpr>) (isIf: bool) : option<list<int>> =
      // the value s ends with on each path (a local function's or mutable's scope isn't entered)
      let rec tails (e: CExpr) : list<CExpr> =
        match e.k with
        | CLet(_, _, b)
        | CSeq(_, b)
        | CLine(_, b) -> tails b
        | CIf(_, t, f) -> List.append (tails t) (tails f)
        | CMatch(_, cs) -> List.collect bodyTails cs
        | _ -> [ e ]
      and bodyTails (c: CPat * option<CExpr> * CExpr) : list<CExpr> = tails (bodyOf c)
      let shape (t: CExpr) : option<Known> =
        match t.k with
        | CCtor(_, tag, args) -> Some(KCtor(tag, List.map (fun _ -> Some "$") args))
        | CLocal y -> Map.tryFind y env
        | _ ->
          match literal t with
          | Some l -> Some(KLit l)
          | None -> None
      let n = List.length cases
      // the cases each path can take
      let reach (t: CExpr) : list<int> =
        match shape t with
        | None -> List.init n (fun i -> i)
        | Some kn ->
          let rec go (i: int) (cs: list<CPat * option<CExpr> * CExpr>) : list<int> =
            match cs with
            | [] -> []
            | (p, g, _) :: rest ->
              match staticMatch (fun w -> Map.tryFind w env) (Some kn) "$" p with
              | No -> go (i + 1) rest
              | Yes _ -> if Option.isNone g then [ i ] else i :: go (i + 1) rest
              | Unknown -> List.init (n - i) (fun d -> i + d)
          go 0 cases
      // a match or a branch to move into (else no paths inside s)
      let inside =
        match s.k with
        | CLet _
        | CSeq _
        | CLine _
        | CIf _
        | CMatch _ -> true
        | _ -> false
      let ts = tails s
      if not inside || List.forall (fun t -> Option.isNone (shape t)) ts then
        None
      else
        let reaches = List.map reach ts
        let usesOf = List.init n (fun i -> List.length (List.filter (fun (r: list<int>) -> List.contains i r) reaches))
        // a body reached more than once: copied when small, else a join point, which takes the
        // pattern's variables and whatever else the body reads
        let shared (i: int) = List.item i usesOf > 1 && size (bodyOf (List.item i cases)) > 16
        let joinable (i: int) : bool =
          let (p, _, b) = List.item i cases
          let own = Set.ofList (List.append (binders b) (List.map fst (patVars p)))
          let rec assigns (e: CExpr) : bool =
            match e.k with
            | CAssign(y, _)
            | CArraySet(y, _, _) when not (Set.contains y own) -> true
            | k -> List.exists assigns (children k)
          not (assigns b) && not (List.exists (fun x -> Set.contains x localFuns.Value) (Set.toList (freeVars b)))
        if (isIf && List.exists (fun u -> u > 1) usesOf) || List.exists (fun i -> shared i && not (joinable i)) (List.init n (fun i -> i)) then None else Some usesOf
    // case of case: the match moved into each path of s, with join points for the bodies reached
    // on several paths
    and pushed (env: Map<string, Known>) (s: CExpr) (cases: list<CPat * option<CExpr> * CExpr>) (isIf: bool) : option<CExpr> =
      match plan env s cases isIf with
      | None -> None
      | Some usesOf ->
        let n = List.length cases
        let shared (i: int) = List.item i usesOf > 1 && size (bodyOf (List.item i cases)) > 16
        let joins = Buffer.empty
        let jumpOf (i: int) : option<int * (string * list<string * Ty> * list<string * Ty>)> =
          if shared i then
            let (p, _, b) = List.item i cases
            let pvs = patVars p
            let fv = freeVars b
            let names = Set.ofList (List.map fst pvs)
            let candidates = List.filter (fun (x, _) -> Set.contains x fv && not (Set.contains x names)) (refs b)
            let outer = List.fold (fun (acc: list<string * Ty>) (c: string * Ty) -> if List.exists (fun (y, _) -> y = fst c) acc then acc else List.append acc [ c ]) [] candidates
            let ps = List.map (fun (x, t) -> (x, fresh x, t)) (List.append pvs outer)
            let j = fresh "$join"
            let body = rename fresh (Map.ofList (List.map (fun (x, x2, _) -> (x, x2)) ps)) false b
            Buffer.push (j, List.map (fun (_, x2, t) -> (x2, t)) ps, body) joins
            Some(i, (j, pvs, outer))
          else
            None
        let jumps = Map.ofList (List.choose jumpOf (List.init n (fun i -> i)))
        let copied = ref Set.empty
        // the cases for one path: the first copy of a body keeps its names
        let instance () : list<CPat * option<CExpr> * CExpr> =
          let one (i: int) (c: CPat * option<CExpr> * CExpr) =
            let (p, g, b) = c
            match Map.tryFind i jumps with
            | Some(j, pvs, outer) ->
              let m = Map.ofList (List.map (fun (x, _) -> (x, fresh x)) pvs)
              let args = List.append (List.map (fun (x, t) -> mk (CLocal(Map.find x m)) t) pvs) (List.map (fun (x, t) -> mk (CLocal x) t) outer)
              let rn (x: string) = Option.defaultValue x (Map.tryFind x m)
              let g2 = Option.map (rename fresh m true) g
              (renamePat rn p, g2, mk (CJump(j, args)) b.ty)
            | None ->
              if not (Set.contains i copied.Value) then
                copied.Value <- Set.add i copied.Value
                (p, g, b)
              else
                let m = Map.ofList (List.map (fun (x, _) -> (x, fresh x)) (patVars p))
                let rn (x: string) = Option.defaultValue x (Map.tryFind x m)
                let g2 = Option.map (rename fresh m true) g
                (renamePat rn p, g2, rename fresh m true b)
          List.mapi one cases
        let ty = (bodyOf (List.head cases)).ty
        let rec into (e: CExpr) : CExpr =
          match e.k with
          | CLet(x, w, b) -> mk (CLet(x, w, into b)) ty
          | CSeq(a, b) -> mk (CSeq(a, into b)) ty
          | CLine(l, b) -> mk (CLine(l, into b)) ty
          | CIf(c, t, f) ->
            let t2 = into t
            mk (CIf(c, t2, into f)) ty
          | CMatch(s2, cs) -> mk (CMatch(s2, List.map (fun (p, g, b) -> (p, g, into b)) cs)) ty
          | _ -> mk (CMatch(e, instance ())) ty
        let body = into s
        Some(List.fold (fun (acc: CExpr) (j, ps, b) -> mk (CJoin(j, ps, b, acc)) ty) body (List.rev (Array.toList (Buffer.toArray joins))))
    { f with body = simp Map.empty f.body }
  // each function on the pool (decision 76)
  Array.toList (Array.Parallel.map simplifyFun (Array.ofList funs))
