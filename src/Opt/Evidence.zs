/// Effect handlers compiled by evidence passing with yield bubbling (Xie and Leijen, ICFP 2021, as
/// Koka does; DESIGN §6.1). After monomorphization each function's row is concrete:
///   - A function whose row isn't empty takes a frame per effect in it (its evidence) after its last
///     parameter; a call passes the caller's frames for the callee's effects (the k-th effect of a
///     name in the callee's row is the k-th in the caller's: the innermost first).
///   - A frame is a handler's: its marker, and a closure per operation. Performing an operation
///     calls its closure. A tail-resumptive clause (it resumes once, last) is that closure: it runs
///     where the operation is performed and returns the result, nothing captured. Any other
///     clause's closure records the clause in the thread's yield state and returns at once.
///   - After a call that may yield (its row isn't empty), a test of that state. When it's set, the
///     function adds the rest of itself to the continuation (a closure calling a local function the
///     code after the call went into, its mutable variables passed along) and returns too, up to the
///     handle whose marker it is, which runs the clause with that continuation as the resumption. A
///     clause that never resumes wants no continuation, and none is made. A call in tail position
///     needs no test: there's no rest.
///   - A loop with such calls becomes a local function taking its mutable variables, and the code
///     after it goes into the loop's exit.
/// Functions without effects and without handles compile exactly as before.
open Types.Ty
open Core.Ir
open Core.Program

let private labelsOf (v: Types.Vars.Vars) (row: Ty) : list<Ty> = fst (Types.Norm.rowParts v row)

/// A handler's frame for an effect: a boxed union of one case, its marker and its operations.
let frameName (v: Types.Vars.Vars) (label: Ty) : string = "$frame:" + Types.Show.showFull v label

let private frameTy (v: Types.Vars.Vars) (label: Ty) : Ty = TCon(frameName v label, [])

/// A type with evidence: a function type's effects become frame parameters after its parameter, and
/// rows are gone.
let rec evTy (v: Types.Vars.Vars) (t: Ty) : Ty =
  match t with
  | TFun(a, b, row) -> TFun(evTy v a, List.fold (fun acc l -> tfun (frameTy v l) acc) (evTy v b) (List.rev (labelsOf v row)), rowEmpty)
  | TCon("$ext", _)
  | TCon("$total", _) -> rowEmpty
  | TCon(n, args) -> TCon(n, List.map (evTy v) args)
  | TTuple ts -> TTuple(List.map (evTy v) ts)
  | other -> other

/// Whether a type has a function with effects anywhere in it (else evTy changes nothing).
let rec private effectful (v: Types.Vars.Vars) (t: Ty) : bool =
  match t with
  | TFun(a, b, row) -> not (Types.Norm.isRowEmpty v row) || effectful v a || effectful v b
  | TCon("$ext", _)
  | TCon("$total", _) -> false
  | TCon(_, args) -> List.exists (effectful v) args
  | TTuple ts -> List.exists (effectful v) ts
  | _ -> false

/// The rows of the arrows a call with n arguments goes through.
let rec private rowsOf (n: int) (t: Ty) : list<Ty> =
  match (n, t) with
  | (0, _) -> []
  | (_, TFun(_, r, row)) -> row :: rowsOf (n - 1) r
  | _ -> []

let rec private resultAfter (n: int) (t: Ty) : Ty =
  match (n, t) with
  | (0, x) -> x
  | (_, TFun(_, r, _)) -> resultAfter (n - 1) r
  | _ -> panic "Evidence: not a function type"

let private tState : Ty = tInt

let private state () : CExpr = mk (CPrim("eff.state", [])) tState

let private intE (n: int) : CExpr = mk (CInt(i64 n)) tInt

let private isState (n: int) : CExpr = mk (CBin("=", state (), intE n)) tBool

let private unitE () : CExpr = mk CUnit tUnit

let private seqE (a: CExpr) (b: CExpr) : CExpr = mk (CSeq(a, b)) b.ty

let private local (x: string) (t: Ty) : CExpr = mk (CLocal x) t

/// Code made by this pass, put among code still to lower: it goes through as it is.
let private lowered (x: CExpr) : CExpr = mk (CPrim("eff.lowered", [ x ])) x.ty

// a function type of these parameters to a result
let private arrows (ps: list<string * Ty>) (ret: Ty) : Ty = List.fold (fun acc (_, t) -> tfun t acc) ret (List.rev ps)

// the index of the last element for which f is true
let private lastIndexWhere (f: 'a -> bool / 'e) (xs: list<'a>) : option<int> / 'e =
  let rec go (i: int) (found: option<int>) (rest: list<'a>) =
    match rest with
    | [] -> found
    | x :: more -> go (i + 1) (if f x then Some i else found) more
  go 0 None xs

/// What follows an expression being lowered: it's the function's result (in tail position), or the
/// rest, given the value (an atom: a variable, or an expression evaluated where it's put) in the
/// context there.
type private K =
  | Tail
  | Then of (Ctx -> CExpr -> CExpr)

/// The function being lowered: its frames in scope (labels in canonical order, each with the
/// expression holding its frame), its mutable variables in scope (the name in Core, the name in the
/// block being made, the type), its result's type, and the joins of Simplify's that became local
/// functions (their function, the mutable variables they take).
and private Ctx = { ev: list<Ty * CExpr>; muts: list<string * string * Ty>; ret: Ty; joins: Map<string, string * list<string>> }

let private cur (ctx: Ctx) (x: string) : string =
  match List.tryFind (fun (o, _, _) -> o = x) ctx.muts with
  | Some(_, n, _) -> n
  | None -> x

/// The frames for a callee's row: the k-th effect of a name gets the k-th frame of it here.
let private framesFor (v: Types.Vars.Vars) (ctx: Ctx) (row: Ty) : list<CExpr> =
  let used = ref Map.empty
  let one (l: Ty) =
    let n = Types.Norm.labelName v l
    let k = Option.defaultValue 0 (Map.tryFind n used.Value)
    used.Value <- Map.add n (k + 1) used.Value
    match List.tryItem k (List.filter (fun (m, _) -> Types.Norm.labelName v m = n) ctx.ev) with
    | Some(_, f) -> f
    | None -> panic $"Evidence: no frame for {Types.Show.show v l}"
  List.map one (labelsOf v row)

/// The frames in scope with a handler's added: in front of the others of its effect.
let private withFrame (v: Types.Vars.Vars) (ev: list<Ty * CExpr>) (label: Ty) (frame: CExpr) : list<Ty * CExpr> =
  let n = Types.Norm.labelName v label
  match List.tryFindIndex (fun (m, _) -> Types.Norm.labelName v m = n || Types.Norm.labelName v m > n) ev with
  | Some i -> List.concat [ List.take i ev; [ (label, frame) ]; List.skip i ev ]
  | None -> List.append ev [ (label, frame) ]

// the program's functions lowered, the types with the frames, and what it can't be lowered for
let private lowerAll (types0: Map<string, TypeInfo>) (effects: Map<string, EffectInfo>) (funs: list<MFun>) : Map<string, TypeInfo> * list<MFun> * option<string> =
  let v = Types.Vars.make ()
  let types = ref types0
  // ---- the frames' types, made before the functions are lowered
  let opTypes (label: Ty) : list<Ty> =
    match label with
    | TCon(n, targs) ->
      let one (o: EffectOp) =
        let own = List.init o.own (fun _ -> tUnit)
        let inst = List.append targs own
        List.fold (fun acc p -> tfun (evTy v (Types.Norm.substGen v inst p)) acc) (evTy v (Types.Norm.substGen v inst o.ret)) (List.rev o.pars)
      List.map one (Map.find n effects).ops
    | _ -> []
  let rec register (label: Ty) =
    let name = frameName v label
    if not (Map.containsKey name types.Value) then
      let ops = opTypes label
      types.Value <- Map.add name { npars = 0; def = UnionDef [ ("$frame", tInt :: ops) ] } types.Value
      for t in ops do
        labelsIn t
  and labelsIn (t: Ty) =
    match t with
    | TFun(a, b, row) ->
      labelsIn a
      labelsIn b
      for l in labelsOf v row do
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
      for (_, ps, (_, kt), _) in cls do
        labelsIn kt
        for (_, t) in ps do
          labelsIn t
    | CLam(ps, _)
    | CLetFun(_, _, ps, _, _) -> List.iter (fun (_, t) -> labelsIn t) ps
    | CLetRec(fs, _) -> List.iter (fun (_, ps, _) -> List.iter (fun (_, t) -> labelsIn t) ps) fs
    | CMatch(_, cases) -> List.iter (fun (p, _, _) -> List.iter (fun (_, t) -> labelsIn t) (patVars p)) cases
    | _ -> ()
    List.iter labelsInExpr (children e.k)
  /// Whether a function has anything to lower: effects in its row or types, a perform, a handle,
  /// or an opened function.
  let rec touches (e: CExpr) : bool =
    let own =
      match e.k with
      | CPerform _
      | CHandle _ -> true
      | CPrim("eff.open", _) -> true
      | CLam(ps, _)
      | CLetFun(_, _, ps, _, _) -> List.exists (fun (_, t) -> effectful v t) ps
      | CLetRec(fs, _) -> List.exists (fun (_, ps, _) -> List.exists (fun (_, t) -> effectful v t) ps) fs
      | _ -> false
    effectful v e.ty || own || List.exists touches (children e.k)
  let needs (f: MFun) = not (Types.Norm.isRowEmpty v f.row) || effectful v f.ret || List.exists (fun (_, t) -> effectful v t) f.pars || touches f.body
  let marked = List.map (fun (f: MFun) -> (f, needs f)) funs
  for (f, lower) in marked do
    if lower then
      labelsIn f.row
      labelsIn f.ret
      List.iter (fun (_, t) -> labelsIn t) f.pars
      labelsInExpr f.body
  let opIsPolymorphic (label: Ty) (op: int) = (List.item op (Map.find (Types.Norm.labelName v label) effects).ops).own > 0
  let tagOf (u: string) (case: string) : int =
    match (Map.find u types.Value).def with
    | UnionDef cs -> List.findIndex (fun (c, _) -> c = case) cs
    | _ -> panic "tagOf"
  // ---- lowering one function
  // what the program can't be lowered for (stopped at once the functions are done)
  let failure = ref None
  let lowerFun (f: MFun) : MFun =
    let fname = f.name
    // numbered per function: a function's code doesn't depend on the others'
    let counter = ref 0
    let fresh (x: string) =
      counter.Value <- counter.Value + 1
      $"{x}.e{counter.Value}"
    let localTypes = localTypesIn f.body
    // a local function's row: the one of its type where it's used (unused: none)
    let localRow (n: string) (arity: int) : Ty =
      match Map.tryFind n localTypes with
      | Some t -> Option.defaultValue rowEmpty (List.tryLast (rowsOf arity t))
      | None -> rowEmpty
    let ev (t: Ty) = evTy v t
    let frameT (l: Ty) = frameTy v l
    /// A call's or an operation's code that may yield, k given its value: a tail call as it is,
    /// else the test, the rest in a local function the continuation calls too.
    let rec yieldPoint (ctx: Ctx) (callE: CExpr) (k: K) : CExpr =
      match k with
      | Tail -> callE
      | Then _ ->
        let made (ctx: Ctx) (k: K) : CExpr =
          match k with
          | Then jump ->
            let contTy = tfun tCPtr callE.ty
            let resumeTy = tfun tCPtr ctx.ret
            let yielding () = mk (CBin("<>", state (), intE 0)) tBool
            let dummy () = mk (CPrim("eff.dummy", [])) ctx.ret
            // this frame's continuation, made when the call yields: the continuation so far (c),
            // then the rest; when that yields again, this frame is added to the new continuation
            // the same way (a local function: it calls itself)
            let resume = fresh "$resume"
            let c = fresh "$c"
            let p = fresh "$p"
            let y = fresh "$y"
            let snaps = List.map (fun (o, n, t) -> (o, fresh n, n, t)) ctx.muts
            let rctx = { ctx with muts = List.map (fun (o, s, _, t) -> (o, s, t)) snaps }
            let rpars = List.concat [ [ (c, contTy) ]; List.map (fun (_, s, _, t) -> (s, t)) snaps; [ (p, tCPtr) ] ]
            let rty = arrows rpars ctx.ret
            let rlocal = local resume rty
            // the continuation of this frame: resume applied to all but p
            let contOf (cv: CExpr) (vals: list<CExpr>) = mk (CApp(rlocal, cv :: vals)) resumeTy
            let extendWith (vals: Ctx -> list<CExpr>) (cx: Ctx) =
              let inner = fresh "$inner"
              mk (CLet(inner, mk (CPrim("eff.takeCont", [])) contTy, mk (CPrim("eff.setCont", [ contOf (local inner contTy) (vals cx) ])) tUnit)) tUnit
            let bubble (x: CExpr) (extend: CExpr) = seqE (mk (CIf(isState 1, extend, unitE ())) tUnit) (seqE (mk (CPrim("eff.forget", [ x ])) tUnit) (dummy ()))
            let snapVals (cx: Ctx) = List.map (fun (o, _, _, t) -> local (cur cx o) t) snaps
            let rbody =
              let yv = local y callE.ty
              let again = extendWith snapVals rctx
              mk (CLet(y, mk (CApp(local c contTy, [ local p tCPtr ])) callE.ty, mk (CIf(yielding (), bubble yv again, jump rctx yv)) ctx.ret)) ctx.ret
            let x = fresh "$r"
            let xv = local x callE.ty
            // the mutable variables' values now, for the continuation
            let snapshot = extendWith (fun _ -> List.map (fun (_, s, _, t) -> local s t) snaps) ctx
            let first = List.fold (fun (acc: CExpr) (snap: string * string * string * Ty) -> match snap with (_, s, n, t) -> mk (CLet(s, local n t, acc)) acc.ty) snapshot (List.rev snaps)
            let main = mk (CLet(x, callE, mk (CIf(yielding (), bubble xv first, jump ctx xv)) ctx.ret)) ctx.ret
            mk (CLetRec([ (resume, rpars, rbody) ], main)) ctx.ret
          | Tail -> panic "unreachable"
        withJoin ctx k callE.ty made
    /// k as a local function when it's Then (so the code after a branch or a call is made once):
    /// body gets the context and a K that jumps to it (the mutable variables passed).
    and withJoin (ctx: Ctx) (k: K) (vty: Ty) (body: Ctx -> K -> CExpr) : CExpr =
      match k with
      | Tail -> body ctx Tail
      | Then rest ->
        let j = fresh "$join"
        let x = fresh "$v"
        let ms = ctx.muts
        let inner = List.map (fun (o, n, t) -> (o, fresh n, t)) ms
        let ps = (x, vty) :: List.map (fun (_, n, t) -> (n + "p", t)) inner
        let jctx = { ctx with muts = inner }
        let declared = rest jctx (local x vty)
        let jbody = List.fold (fun (acc: CExpr) (m: string * string * Ty) -> match m with (_, n, t) -> mk (CLetMut(n, local (n + "p") t, acc)) acc.ty) declared (List.rev inner)
        let jty = arrows ps ctx.ret
        let jump (c: Ctx) (a: CExpr) = mk (CApp(local j jty, a :: List.map (fun (o, _, t) -> local (cur c o) t) ms)) ctx.ret
        let code = body ctx (Then jump)
        mk (CLetFun(j, false, ps, jbody, code)) code.ty
    /// Whether e has a yield point of this function's (not in its lambdas and local functions,
    /// which are functions of their own, nor in a handle's body and clauses).
    and yields (ctx: Ctx) (e: CExpr) : bool =
      match e.k with
      | CPerform _ -> true
      // a jump to a join point lowered as a local function: that function runs the rest, so the
      // jump goes through lower, where nothing follows it
      | CJump(j, _) when Map.containsKey j ctx.joins -> true
      | CApp(h, args) -> List.exists (fun r -> not (Types.Norm.isRowEmpty v r)) (rowsOf (List.length args) h.ty) || yields ctx h || List.exists (yields ctx) args
      | CHandle _ -> not (List.isEmpty ctx.ev)
      | CLam _ -> false
      | CLetFun(_, _, _, _, rest) -> yields ctx rest
      | CLetRec(_, rest) -> yields ctx rest
      | k -> List.exists (yields ctx) (children k)
    /// e without yield points, rebuilt: types with evidence, mutable variables renamed, and its
    /// lambdas, local functions and handles lowered.
    and plain (ctx: Ctx) (e: CExpr) : CExpr =
      let ty = ev e.ty
      match e.k with
      | CLocal x -> mk (CLocal(cur ctx x)) ty
      | CAssign(x, w) -> mk (CAssign(cur ctx x, plain ctx w)) ty
      | CArraySet(x, i, w) ->
        let i2 = plain ctx i
        mk (CArraySet(cur ctx x, i2, plain ctx w)) ty
      | CLam(ps, b) -> lambda ctx e ps b
      | CLetFun(n, r, ps, b, rest) ->
        let (ps2, b2) = localFun ctx n ps b
        mk (CLetFun(n, r, ps2, b2, plain ctx rest)) ty
      | CLetRec(fs, rest) ->
        let one (fd: string * list<string * Ty> * CExpr) =
          match fd with
          | (n, ps, b) ->
            let (ps2, b2) = localFun ctx n ps b
            (n, ps2, b2)
        let fs2 = List.map one fs
        mk (CLetRec(fs2, plain ctx rest)) ty
      | CHandle(l, b, cls, r, rb) -> lowerHandle ctx l b cls r rb ty
      | CPrim("eff.open", [ g ]) -> adapter ctx g e.ty
      | CPrim("eff.lowered", [ x ]) -> x
      | CJoin(j, ps, b, r) ->
        let r2 = plain ctx r
        mk (CJoin(j, List.map (fun (x, t) -> (x, ev t)) ps, plain ctx b, r2)) ty
      | CMatch(s, cases) ->
        let s2 = plain ctx s
        mk (CMatch(s2, List.map (fun (p, g, b) -> (mapPatTypes ev p, Option.map (plain ctx) g, plain ctx b)) cases)) ty
      | CApp(h, args) ->
        let h2 = plain ctx h
        mk (CApp(h2, List.map (plain ctx) args)) ty
      | CJump(j, args) when Map.containsKey j ctx.joins ->
        let (fn, ms) = Map.find j ctx.joins
        let args2 = List.map (plain ctx) args
        let fty = List.fold (fun acc (a: CExpr) -> tfun a.ty acc) ctx.ret (List.rev args2)
        mk (CApp(local fn fty, List.append args2 (List.map (fun o -> local (cur ctx o) (mutTy ctx o)) ms))) ctx.ret
      | k -> mk (mapChildren (plain ctx) k) ty
    and mutTy (ctx: Ctx) (o: string) : Ty =
      match List.tryFind (fun (x, _, _) -> x = o) ctx.muts with
      | Some(_, _, t) -> t
      | None -> panic "mutTy"
    /// A lambda with evidence: its frames after its parameters, its body lowered.
    and lambda (ctx: Ctx) (e: CExpr) (ps: list<string * Ty>) (b: CExpr) : CExpr =
      let row = Option.defaultValue rowEmpty (List.tryLast (rowsOf (List.length ps) e.ty))
      let evs = List.map (fun l -> (l, fresh "$ev")) (labelsOf v row)
      let body = lowerBody { ev = List.map (fun (l, x) -> (l, local x (frameT l))) evs; muts = []; ret = ev (resultAfter (List.length ps) e.ty); joins = Map.empty } b
      mk (CLam(List.append (List.map (fun (x, t) -> (x, ev t)) ps) (List.map (fun (l, x) -> (x, frameT l)) evs), body)) (ev e.ty)
    and localFun (ctx: Ctx) (n: string) (ps: list<string * Ty>) (b: CExpr) : list<string * Ty> * CExpr =
      let row = localRow n (List.length ps)
      let evs = List.map (fun l -> (l, fresh "$ev")) (labelsOf v row)
      let body = lowerBody { ev = List.map (fun (l, x) -> (l, local x (frameT l))) evs; muts = []; ret = ev b.ty; joins = Map.empty } b
      (List.append (List.map (fun (x, t) -> (x, ev t)) ps) (List.map (fun (l, x) -> (x, frameT l)) evs), body)
    /// A global function opened to a larger row (Typer.opened): a lambda taking that row's frames,
    /// which calls it with those of its own row.
    and adapter (ctx: Ctx) (g: CExpr) (openTy: Ty) : CExpr =
      let rec arity (n: int) (a: Ty) (b: Ty) : int =
        match (a, b) with
        | (TFun(_, ra, rowA), TFun(_, rb, rowB)) -> if Types.Show.showFull v rowA <> Types.Show.showFull v rowB then n + 1 else arity (n + 1) ra rb
        | _ -> n
      let n = arity 0 g.ty openTy
      let rec parsOf (k: int) (t: Ty) : list<Ty> =
        if k = 0 then
          []
        else
          match t with
          | TFun(a, r, _) -> a :: parsOf (k - 1) r
          | _ -> []
      let ps = List.map (fun t -> (fresh "$x", t)) (parsOf n openTy)
      let openRow = List.last (rowsOf n openTy)
      let evs = List.map (fun l -> (l, fresh "$ev")) (labelsOf v openRow)
      let actx = { ctx with ev = List.map (fun (l, x) -> (l, local x (frameT l))) evs; muts = [] }
      let ownRow = List.last (rowsOf n g.ty)
      let args = List.append (List.map (fun (x, t) -> local x (ev t)) ps) (framesFor v actx ownRow)
      let resTy = ev (resultAfter n g.ty)
      let callE = mk (CApp(plain ctx g, args)) resTy
      mk (CLam(List.append (List.map (fun (x, t) -> (x, ev t)) ps) (List.map (fun (l, x) -> (x, frameT l)) evs), callE)) (ev openTy)
    /// A call's arguments with the frames for the rows of the arrows they go through.
    and withEvidence (ctx: Ctx) (calleeTy: Ty) (args: list<CExpr>) : list<CExpr> =
      let rows = rowsOf (List.length args) calleeTy
      List.collect (fun (a, row) -> a :: framesFor v ctx row) (List.zip args rows)
    /// These expressions' values, in order, then f with them: those before the last one that yields
    /// are bound first (or are constants or variables that can't change).
    and lowerAtoms (ctx: Ctx) (es: list<CExpr>) (f: Ctx -> list<CExpr> -> CExpr) : CExpr =
      let lastY = lastIndexWhere (yields ctx) es
      let trivial (e: CExpr) : bool =
        match e.k with
        | CInt _
        | CFloat _
        | CBool _
        | CStr _
        | CUnit
        | CGlobal _
        | CGlobalVal _ -> true
        | CLocal x -> not (List.exists (fun (o, _, _) -> o = x) ctx.muts)
        | _ -> false
      let rec go (cx: Ctx) (i: int) (acc: list<CExpr>) (rest: list<CExpr>) : CExpr =
        match rest with
        | [] -> f cx (List.rev acc)
        | e :: more ->
          match lastY with
          | Some j when i <= j ->
            if yields cx e then
              lower cx e (Then(fun cx2 a -> go cx2 (i + 1) (a :: acc) more))
            else if trivial e then
              go cx (i + 1) (plain cx e :: acc) more
            else
              let t = fresh "$a"
              let pe = plain cx e
              let inner = go cx (i + 1) (local t pe.ty :: acc) more
              mk (CLet(t, pe, inner)) inner.ty
          | _ -> go cx (i + 1) (plain cx e :: acc) more
      go ctx 0 [] es
    and give (ctx: Ctx) (k: K) (x: CExpr) : CExpr =
      match k with
      | Tail -> x
      | Then f -> f ctx x
    /// e lowered, k given its value.
    and lower (ctx: Ctx) (e: CExpr) (k: K) : CExpr =
      if not (yields ctx e) then
        give ctx k (plain ctx e)
      else
        match e.k with
        | CLine(l, a) ->
          let inner = lower ctx a k
          mk (CLine(l, inner)) inner.ty
        | CLet(x, w, b) ->
          lower ctx w (Then(fun cx a ->
            let b2 = lower cx b k
            mk (CLet(x, a, b2)) b2.ty))
        | CSeq(a, b) ->
          lower ctx a (Then(fun cx a2 ->
            let b2 = lower cx b k
            mk (CSeq(a2, b2)) b2.ty))
        | CLetMut(x, w, b) ->
          lower ctx w (Then(fun cx a ->
            let b2 = lower { cx with muts = (x, x, a.ty) :: cx.muts } b k
            mk (CLetMut(x, a, b2)) b2.ty))
        | CAssign(x, w) -> lower ctx w (Then(fun cx a -> give cx k (mk (CAssign(cur cx x, a)) tUnit)))
        | CArraySet(x, i, w) ->
          lowerAtoms ctx [ i; w ] (fun cx args ->
            match args with
            | [ i2; w2 ] -> give cx k (mk (CArraySet(cur cx x, i2, w2)) tUnit)
            | _ -> panic "unreachable")
        | CLetFun(n, r, ps, b, rest) ->
          let (ps2, b2) = localFun ctx n ps b
          let rest2 = lower ctx rest k
          mk (CLetFun(n, r, ps2, b2, rest2)) rest2.ty
        | CLetRec(fs, rest) ->
          let one (fd: string * list<string * Ty> * CExpr) =
            match fd with
            | (n, ps, b) ->
              let (ps2, b2) = localFun ctx n ps b
              (n, ps2, b2)
          let fs2 = List.map one fs
          let rest2 = lower ctx rest k
          mk (CLetRec(fs2, rest2)) rest2.ty
        | CIf(c, t, f) ->
          lower ctx c (Then(fun cx c2 ->
            withJoin cx k (ev e.ty) (fun cx2 k2 ->
              let t2 = lower cx2 t k2
              let f2 = lower cx2 f k2
              mk (CIf(c2, t2, f2)) t2.ty)))
        | CMatch(s, cases) ->
          if List.exists (fun (_, g, _) -> Option.exists (yields ctx) g) cases && Option.isNone failure.Value then
            failure.Value <- Some $"a when guard can't perform an effect: match first, then perform in the case (in {baseFunName fname})"
          lower ctx s (Then(fun cx s2 ->
            withJoin cx k (ev e.ty) (fun cx2 k2 ->
              let cases2 = List.map (fun (p, g, b) -> (mapPatTypes ev p, Option.map (plain cx2) g, lower cx2 b k2)) cases
              let (_, _, b0) = List.head cases2
              mk (CMatch(s2, cases2)) b0.ty)))
        | CJoin(j, ps, body, rest) ->
          // a join point of Simplify's: a local function (its paths may yield)
          withJoin ctx k (ev e.ty) (fun cx k2 ->
            let fn = fresh "$jp"
            let ms = cx.muts
            let inner = List.map (fun (o, n, t) -> (o, fresh n, t)) ms
            let ps2 = List.append (List.map (fun (x, t) -> (x, ev t)) ps) (List.map (fun (_, n, t) -> (n + "p", t)) inner)
            let jctx = { cx with muts = inner }
            let lowered2 = lower jctx body k2
            let jbody = List.fold (fun (acc: CExpr) (m: string * string * Ty) -> match m with (_, n, t) -> mk (CLetMut(n, local (n + "p") t, acc)) acc.ty) lowered2 (List.rev inner)
            let rest2 = lower { cx with joins = Map.add j (fn, List.map (fun (o, _, _) -> o) ms) cx.joins } rest k2
            mk (CLetFun(fn, false, ps2, jbody, rest2)) rest2.ty)
        | CJump(j, args) when Map.containsKey j ctx.joins ->
          let (fn, ms) = Map.find j ctx.joins
          lowerAtoms ctx args (fun cx atoms ->
            let fty = List.fold (fun acc (a: CExpr) -> tfun a.ty acc) cx.ret (List.rev atoms)
            mk (CApp(local fn fty, List.append atoms (List.map (fun o -> local (cur cx o) (mutTy cx o)) ms))) cx.ret)
        | CWhile(c, b) ->
          loop ctx k [] (fun cx finish ->
            lower cx c (Then(fun cx2 cv ->
              let body = lower cx2 b (Then(fun cx3 x -> seqE x (finish cx3 true [])))
              mk (CIf(cv, body, finish cx2 false [])) (roundTy cx2 []))))
        | CFor(x, a, s, b, body) ->
          lowerAtoms ctx [ a; s; b ] (fun cx args ->
            match args with
            | [ a2; s2; b2 ] ->
              let sv = fresh "$step"
              let bv = fresh "$to"
              let down =
                match s.k with
                | CInt n -> n < i64 0
                | CNeg _ -> true
                | _ -> false
              let it = ev a.ty
              let iv = local x it
              let cond = mk (CBin((if down then ">=" else "<="), iv, local bv it)) tBool
              let next = mk (CPrim("wrap+", [ iv; local sv it ])) it
              let lp =
                loop cx k [ (x, it, a2) ] (fun cx2 finish ->
                  let inner = lower cx2 body (Then(fun cx3 w -> seqE w (finish cx3 true [ next ])))
                  mk (CIf(cond, inner, finish cx2 false [ iv ])) (roundTy cx2 [ it ]))
              mk (CLet(sv, s2, mk (CLet(bv, b2, lp)) lp.ty)) lp.ty
            | _ -> panic "unreachable")
        | CPerform(l, op, args) ->
          lowerAtoms ctx args (fun cx atoms ->
            let frame = List.head (framesFor v cx (rowExt l rowEmpty))
            let ops = opTypes l
            let o = fresh "$op"
            let fields = CPWild :: List.mapi (fun i t -> if i = op then CPVar(o, t) else CPWild) ops
            let opTy = List.item op ops
            let res = ev e.ty
            let callE =
              if opIsPolymorphic l op then
                // its result is its own type: no clause gives one (none resumes)
                seqE (mk (CApp(local o opTy, atoms)) tUnit) (mk (CPrim("eff.dummy", [])) res)
              else
                mk (CApp(local o opTy, atoms)) res
            let body = yieldPoint cx callE k
            mk (CMatch(frame, [ (CPCtor(frameName v l, 0, fields), None, body) ])) body.ty)
        | CApp(h, args) ->
          lowerAtoms ctx (h :: args) (fun cx atoms ->
            let h2 = List.head atoms
            let callE = mk (CApp(h2, withEvidence cx h.ty (List.tail atoms))) (ev e.ty)
            if List.forall (Types.Norm.isRowEmpty v) (rowsOf (List.length args) h.ty) then give cx k callE else yieldPoint cx callE k)
        | CHandle(l, b, cls, r, rb) -> yieldPoint ctx (lowerHandle ctx l b cls r rb (ev e.ty)) k
        | _ ->
          // anything else: its parts' values first, in order
          lowerAtoms ctx (children e.k) (fun cx atoms ->
            let q = ref atoms
            let take (_: CExpr) =
              match q.Value with
              | h :: rest ->
                q.Value <- rest
                h
              | [] -> panic "unreachable"
            give cx k (mk (mapChildren take e.k) (ev e.ty)))
    /// The type a loop's round gives: whether to go on, then the loop's state (the for loop's
    /// variable, then the mutable variables in scope).
    and roundTy (ctx: Ctx) (xs: list<Ty>) : Ty =
      match List.append xs (List.map (fun (_, _, t) -> t) ctx.muts) with
      | [] -> tBool
      | ts -> TTuple(tBool :: ts)
    /// A loop with yield points: a round function (the condition and the body once, giving whether
    /// to go on and the new state) and a driver running rounds in a while loop, so no round's code
    /// waits on another's: no stack grows with the rounds, at any optimization. When a round yields,
    /// the driver adds itself to the continuation (resume: the round's result once it's resumed,
    /// then driving on) and returns. round gets the context in the round and finish (the round's
    /// result: going on?, the for variable's next value). xs: the for loop's variable (its name,
    /// type, first value).
    and loop (ctx: Ctx) (k: K) (xs: list<string * Ty * CExpr>) (round: Ctx -> (Ctx -> bool -> list<CExpr> -> CExpr) -> CExpr) : CExpr =
      let ms = ctx.muts
      let xtys = List.map (fun (_, t, _) -> t) xs
      let stateTys = List.append xtys (List.map (fun (_, _, t) -> t) ms)
      let rty = roundTy ctx xtys
      let roundFn = fresh "$round"
      let driveFn = fresh "$drive"
      let resumeFn = fresh "$resume"
      let exitFn = fresh "$exit"
      let yielding () = mk (CBin("<>", state (), intE 0)) tBool
      let pack (more: bool) (vals: list<CExpr>) =
        match vals with
        | [] -> mk (CBool more) tBool
        | _ -> mk (CTuple(mk (CBool more) tBool :: vals)) rty
      // a round: the state as parameters (the mutable variables declared again)
      let inner = List.map (fun (o, n, t) -> (o, fresh n, t)) ms
      let rps = List.append (List.map (fun (x, t, _) -> (x, t)) xs) (List.map (fun (_, n, t) -> (n + "p", t)) inner)
      let rctx = { ctx with muts = inner; ret = rty }
      let finish (c: Ctx) (more: bool) (next: list<CExpr>) = pack more (List.append next (List.map (fun (o, _, t) -> local (cur c o) t) ms))
      let rounded = round rctx finish
      let rbody = List.fold (fun (acc: CExpr) (m: string * string * Ty) -> match m with (_, n, t) -> mk (CLetMut(n, local (n + "p") t, acc)) acc.ty) rounded (List.rev inner)
      let roundLocal = local roundFn (arrows rps rty)
      // after the loop: the rest, with the mutable variables' last values
      let outs = List.map (fun (o, n, t) -> (o, fresh n, t)) ms
      let eps = (fresh "$u", tUnit) :: List.map (fun (_, n, t) -> (n + "p", t)) outs
      let ectx = { ctx with muts = outs }
      let given = give ectx k (unitE ())
      let ebody = List.fold (fun (acc: CExpr) (m: string * string * Ty) -> match m with (_, n, t) -> mk (CLetMut(n, local (n + "p") t, acc)) acc.ty) given (List.rev outs)
      let exitLocal = local exitFn (arrows eps ctx.ret)
      let exitWith (mutVals: list<CExpr>) = mk (CApp(exitLocal, unitE () :: mutVals)) ctx.ret
      // the state's parts out of a round's result, then f with them
      let unpack (r: CExpr) (f: CExpr -> list<CExpr> -> CExpr) : CExpr =
        match stateTys with
        | [] -> f r []
        | _ ->
          let more = fresh "$more"
          let vs = List.map (fun t -> (fresh "$s", t)) stateTys
          let body = f (local more tBool) (List.map (fun (x, t) -> local x t) vs)
          mk (CMatch(r, [ (CPTuple(CPVar(more, tBool) :: List.map (fun (x, t) -> CPVar(x, t)) vs), None, body) ])) body.ty
      let nx = List.length xs
      let dps = List.map (fun t -> (fresh "$st", t)) stateTys
      let driveTy = arrows dps ctx.ret
      let driveLocal = local driveFn driveTy
      let contTy = tfun tCPtr rty
      let resumeTy = tfun contTy (tfun tCPtr ctx.ret)
      let extend () =
        let c = fresh "$inner"
        mk (CLet(c, mk (CPrim("eff.takeCont", [])) contTy, mk (CPrim("eff.setCont", [ mk (CApp(local resumeFn resumeTy, [ local c contTy ])) (tfun tCPtr ctx.ret) ])) tUnit)) tUnit
      // the driver: rounds while they go on, the state in mutable variables
      let driveBody =
        let cells = List.map (fun (p, t) -> (fresh "$cell", t, p)) dps
        let go = fresh "$go"
        let yielded = fresh "$yielded"
        let r = fresh "$r"
        let callE = mk (CApp(roundLocal, List.map (fun (c, t, _) -> local c t) cells)) rty
        let rv = local r rty
        let onYield = seqE (mk (CIf(isState 1, extend (), unitE ())) tUnit) (seqE (mk (CPrim("eff.forget", [ rv ])) tUnit) (seqE (mk (CAssign(yielded, mk (CBool true) tBool)) tUnit) (mk (CAssign(go, mk (CBool false) tBool)) tUnit)))
        let assignAll (more: CExpr) (vals: list<CExpr>) =
          let step (acc: CExpr) (cv: (string * Ty * string) * CExpr) =
            match cv with
            | ((c, _, _), x) -> seqE (mk (CAssign(c, x)) tUnit) acc
          List.fold step (mk (CAssign(go, more)) tUnit) (List.rev (List.zip cells vals))
        let onRound = unpack rv assignAll
        let roundOnce = mk (CLet(r, callE, mk (CIf(yielding (), onYield, onRound)) tUnit)) tUnit
        let loopCode = mk (CWhile(local go tBool, roundOnce)) tUnit
        let after = mk (CIf(local yielded tBool, mk (CPrim("eff.dummy", [])) ctx.ret, exitWith (List.map (fun (c, t, _) -> local c t) (List.skip nx cells)))) ctx.ret
        let body1 = seqE loopCode after
        let body2 = mk (CLetMut(go, mk (CBool true) tBool, mk (CLetMut(yielded, mk (CBool false) tBool, body1)) ctx.ret)) ctx.ret
        List.fold (fun (acc: CExpr) (cell: string * Ty * string) -> match cell with (c, t, p) -> mk (CLetMut(c, local p t, acc)) acc.ty) body2 (List.rev cells)
      // a round resumed: its result, then driving on (or, yielding again, this once more)
      let c = fresh "$c"
      let p = fresh "$p"
      let y = fresh "$y"
      let yv = local y rty
      let resumed = mk (CApp(local c contTy, [ local p tCPtr ])) rty
      let again = seqE (mk (CIf(isState 1, extend (), unitE ())) tUnit) (seqE (mk (CPrim("eff.forget", [ yv ])) tUnit) (mk (CPrim("eff.dummy", [])) ctx.ret))
      let goOn = unpack yv (fun more vals -> mk (CIf(more, mk (CApp(driveLocal, vals)) ctx.ret, exitWith (List.skip nx vals))) ctx.ret)
      let rpars = [ (c, contTy); (p, tCPtr) ]
      let rb = mk (CLet(y, resumed, mk (CIf(yielding (), again, goOn)) ctx.ret)) ctx.ret
      let start = mk (CApp(driveLocal, List.append (List.map (fun (_, _, w) -> w) xs) (List.map (fun (o, _, t) -> local (cur ctx o) t) ms))) ctx.ret
      let drive = mk (CLetRec([ (driveFn, dps, driveBody); (resumeFn, rpars, rb) ], start)) ctx.ret
      let withRound = mk (CLetFun(roundFn, false, rps, rbody, drive)) ctx.ret
      mk (CLetFun(exitFn, false, eps, ebody, withRound)) ctx.ret
    /// A body lowered as a function's: its mutable variables under handles boxed first.
    and lowerBody (ctx: Ctx) (b: CExpr) : CExpr = lower ctx (boxUnderHandles b) Tail
    /// handle body with clauses, as code: a frame for the effect (its marker, a closure per
    /// operation), the body run in a local function with the frame in front of the others, and its
    /// result given to the dispatch, a local function that applies the return clause, runs the
    /// clause of a yield to this marker with the continuation, or adds itself to the continuation
    /// of a yield to another (deep handlers: a resumption is handled again).
    and lowerHandle (ctx: Ctx) (label: Ty) (body: CExpr) (cls: list<int * list<string * Ty> * (string * Ty) * CExpr>) (rvt: string * Ty) (retBody: CExpr) (ansTy: Ty) : CExpr =
      let (rv, rt) = rvt
      let outer = { ctx with muts = []; joins = Map.empty }
      let bt = ev rt
      let marker = fresh "$marker"
      let disp = fresh "$dispatch"
      let bodyFn = fresh "$body"
      let frame = fresh "$frame"
      let mv = local marker tInt
      let dispTy = tfun bt ansTy
      let callDisp (x: CExpr) = mk (CApp(local disp dispTy, [ x ])) ansTy
      let contTy = tfun tCPtr bt
      let r = fresh "$res"
      // the dispatch: its own function (its return clause may yield to outer handlers)
      let dispBody =
        let mine =
          let cp = fresh "$cp"
          let ck = fresh "$ck"
          let ckTy = tfun tCPtr ansTy
          mk (CLet(cp, mk (CPrim("eff.takeCont", [])) tCPtr, mk (CLet(ck, mk (CPrim("eff.takeClause", [])) ckTy, mk (CApp(local ck ckTy, [ local cp tCPtr ])) ansTy)) ansTy)) ansTy
        let other =
          let c = fresh "$c"
          let p = fresh "$p"
          let again = mk (CLam([ (p, tCPtr) ], callDisp (mk (CApp(local c contTy, [ local p tCPtr ])) bt))) (tfun tCPtr ansTy)
          let extend = mk (CLet(c, mk (CPrim("eff.takeCont", [])) contTy, mk (CPrim("eff.setCont", [ again ])) tUnit)) tUnit
          seqE (mk (CIf(isState 1, extend, unitE ())) tUnit) (mk (CPrim("eff.dummy", [])) ansTy)
        let returned = lower { outer with ret = ansTy } (mk (CLet(rv, local r bt, boxUnderHandles retBody)) retBody.ty) Tail
        let forget = mk (CPrim("eff.forget", [ local r bt ])) tUnit
        let isMine = mk (CBin("=", mk (CPrim("eff.marker", [])) tInt, mv)) tBool
        mk (CIf(isState 0, returned, seqE forget (mk (CIf(isMine, mine, other)) ansTy))) ansTy
      // each operation's closure
      let ops = opTypes label
      let opClosure (op: int) (ps: list<string * Ty>) (kk: string * Ty) (cbody: CExpr) : CExpr =
        let (k, kty) = kk
        let opTy = List.item op ops
        let ps2 = List.map (fun (x, t) -> (x, ev t)) ps
        let resTy = if opIsPolymorphic label op then tUnit else resultAfter (List.length ps) opTy
        // a path that doesn't resume gives the handle its answer, by a yield that wants no
        // continuation (the clause, which the dispatch runs, is just that answer)
        let stopWith (answer: CExpr) =
          let cp = fresh "$cp"
          let clause = mk (CLam([ (cp, tCPtr) ], lowerBody { outer with ret = ansTy } answer)) (tfun tCPtr ansTy)
          lowered (seqE (mk (CPrim("eff.startFinal", [ mv; clause ])) tUnit) (mk (CPrim("eff.dummy", [])) resTy))
        // a path that does something else with k: a yield to the handle, whose clause is the path
        // with k the resumption (the continuation made on the way there, once)
        let control (path: CExpr) =
          let cp = fresh "$cp"
          let ckTy = tfun tCPtr ansTy
          let cont = fresh "$cont"
          let cell = fresh "$once"
          let x = fresh "$v"
          let c = fresh "$c"
          let optTy = TCon("option", [ contTy ])
          let cellTy = TCon("ref", [ optTy ])
          let some = tagOf "option" "Some"
          let none = tagOf "option" "None"
          let resumeArgTy =
            match kty with
            | TFun(a, _, _) -> ev a
            | _ -> tUnit
          let kRowT = List.head (rowsOf 1 kty)
          let kev = List.map (fun l -> (fresh "$ev", frameT l)) (labelsOf v kRowT)
          let boxed = if resumeArgTy = tUnit then mk (CPrim("eff.null", [])) tCPtr else mk (CPrim("eff.box", [ local x resumeArgTy ])) tCPtr
          let resetCell = mk (CPrim("ref.set", [ local cell cellTy; mk (CCtor("option", none, [])) optTy ])) tUnit
          let someCase = (CPCtor("option", some, [ CPVar(c, contTy) ]), None, seqE resetCell (callDisp (mk (CApp(local c contTy, [ boxed ])) bt)))
          let noneCase = (CPCtor("option", none, []), None, mk (CPrim("panic", [ mk (CStr "resumption called twice (one-shot)") tStr ])) ansTy)
          let resume = mk (CMatch(mk (CPrim("ref.get", [ local cell cellTy ])) optTy, [ someCase; noneCase ])) ansTy
          let kLam = mk (CLam((x, resumeArgTy) :: kev, resume)) (ev kty)
          let withK = mk (CLet(k, kLam, lowerBody { outer with ret = ansTy } path)) ansTy
          let made = mk (CLet(cell, mk (CPrim("ref", [ mk (CCtor("option", some, [ local cont contTy ])) optTy ])) cellTy, withK)) ansTy
          let clauseBody = mk (CLet(cont, mk (CPrim("eff.asClosure", [ local cp tCPtr ])) contTy, made)) ansTy
          let clause = mk (CLam([ (cp, tCPtr) ], clauseBody)) ckTy
          let p = fresh "$p"
          let initial = if resTy = tUnit then unitE () else mk (CPrim("eff.unbox", [ local p tCPtr ])) resTy
          let start = mk (CPrim("eff.start", [ mv; clause; mk (CLam([ (p, tCPtr) ], initial)) (tfun tCPtr resTy) ])) tUnit
          lowered (seqE start (mk (CPrim("eff.dummy", [])) resTy))
        // runs where it's performed: a path resuming last gives the result, the others stop or
        // yield
        mk (CLam(ps2, lowerBody { outer with ret = resTy } (direct k stopWith control cbody))) opTy
      let closureFor (i: int) =
        match List.tryFind (fun (op, _, _, _) -> op = i) cls with
        | Some(_, ps, kk, b) -> opClosure i ps kk b
        | None -> panic "Evidence: a clause missing"
      let closures = List.map closureFor (List.init (List.length ops) (fun i -> i))
      let frameV = local frame (frameT label)
      let bctx = { ev = withFrame v outer.ev label frameV; muts = []; ret = bt; joins = Map.empty }
      let bodyCode = lowerBody bctx body
      let runBody = callDisp (mk (CApp(local bodyFn (tfun tUnit bt), [ unitE () ])) bt)
      let withBody = mk (CLetFun(bodyFn, false, [ (fresh "$u", tUnit) ], bodyCode, runBody)) ansTy
      let withFrameV = mk (CLet(frame, mk (CCtor(frameName v label, 0, mv :: closures)) (frameT label), withBody)) ansTy
      let withDisp = mk (CLetRec([ (disp, [ (r, bt) ], dispBody) ], withFrameV)) ansTy
      mk (CLet(marker, mk (CPrim("eff.newMarker", [])) tInt, withDisp)) ansTy
    /// A clause's body as the closure performing the operation runs it: each path that resumes
    /// last (k v, k nowhere else on it) as v; each that doesn't mention k given to stop; each other
    /// one (k kept, or used before the end) given to control.
    and direct (k: string) (stopWith: CExpr -> CExpr) (control: CExpr -> CExpr) (e: CExpr) : CExpr =
      let free (x: CExpr) = not (Set.contains k (freeVars x))
      let rec go (e: CExpr) : CExpr =
        let resumed =
          match e.k with
          | CApp({ k = CLocal f }, [ x ]) -> if f = k && free x then Some x else None
          | _ -> None
        match resumed with
        | Some x -> x
        | None ->
          if free e then
            stopWith e
          else
            match e.k with
            | CLine(l, a) ->
              let a2 = go a
              mk (CLine(l, a2)) a2.ty
            | CLet(x, w, b) ->
              if free w then
                let b2 = go b
                mk (CLet(x, w, b2)) b2.ty
              else
                control e
            | CLetMut(x, w, b) ->
              if free w then
                let b2 = go b
                mk (CLetMut(x, w, b2)) b2.ty
              else
                control e
            | CSeq(a, b) ->
              if free a then
                let b2 = go b
                mk (CSeq(a, b2)) b2.ty
              else
                control e
            | CIf(c, t, f) ->
              if free c then
                let t2 = go t
                mk (CIf(c, t2, go f)) t2.ty
              else
                control e
            | CMatch(s, cases) ->
              if free s && List.forall (fun (_, g, _) -> Option.forall free g) cases then
                let cases2 = List.map (fun (p, g, b) -> (p, g, go b)) cases
                let (_, _, b0) = List.head cases2
                mk (CMatch(s, cases2)) b0.ty
              else
                control e
            | _ -> control e
      if k = "_" then stopWith e else go e
    /// Mutable variables declared outside a handle or a lambda and used inside it (its body runs in
    /// of its own, its clauses in closures) as ref cells.
    and boxUnderHandles (body: CExpr) : CExpr =
      let mutables = ref Set.empty
      let boxed = ref Set.empty
      let rec scan (e: CExpr) =
        match e.k with
        | CLetMut(x, _, _) -> mutables.Value <- Set.add x mutables.Value
        // a handle's body and a lambda's run as functions of their own: the mutable variables
        // they use are cells (a loop that yields passes the others' values from round to round,
        // which a closure's writes wouldn't reach)
        | CHandle _
        | CLam _ ->
          for x in Set.toList (freeVars e) do
            if Set.contains x mutables.Value then
              boxed.Value <- Set.add x boxed.Value
        | _ -> ()
        match e.k with
        // a function of its own
        | CLam _ -> ()
        | k -> List.iter scan (children k)
      scan body
      if Set.isEmpty boxed.Value then
        body
      else
        let rec go (e: CExpr) : CExpr =
          match e.k with
          | CLetMut(x, w, b) when Set.contains x boxed.Value ->
            let cellTy = TCon("ref", [ w.ty ])
            let b2 = go b
            mk (CLet(x, mk (CPrim("ref", [ go w ])) cellTy, b2)) b2.ty
          | CLocal x when Set.contains x boxed.Value -> mk (CPrim("ref.get", [ mk (CLocal x) (TCon("ref", [ e.ty ])) ])) e.ty
          | CAssign(x, w) when Set.contains x boxed.Value -> mk (CPrim("ref.set", [ mk (CLocal x) (TCon("ref", [ w.ty ])); go w ])) tUnit
          | CArraySet(x, i, w) when Set.contains x boxed.Value ->
            // the cell's array with the element changed (copied when shared)
            let at = TCon("array", [ w.ty ])
            let cell = mk (CLocal x) (TCon("ref", [ at ]))
            let changed = mk (CPrim("array.update", [ mk (CPrim("ref.get", [ cell ])) at; go i; go w ])) at
            mk (CPrim("ref.set", [ cell; changed ])) tUnit
          | k -> { e with k = mapChildren go k }
        go body
    // the function itself
    let evs = List.map (fun l -> (l, fresh "$ev")) (labelsOf v f.row)
    let ctx = { ev = List.map (fun (l, x) -> (l, local x (frameT l))) evs; muts = []; ret = ev f.ret; joins = Map.empty }
    let body = lowerBody ctx f.body
    { f with pars = List.append (List.map (fun (x, t) -> (x, ev t)) f.pars) (List.map (fun (l, x) -> (x, frameT l)) evs); ret = ev f.ret; row = rowEmpty; body = body }
  let lowered = List.map (fun (f, lower) -> if lower then lowerFun f else f) marked
  (types.Value, lowered, failure.Value)

/// Lowers a program's functions; effects: each effect's operations. The types get the frames.
let run (types: Map<string, TypeInfo>) (effects: Map<string, EffectInfo>) (funs: list<MFun>) : Map<string, TypeInfo> * list<MFun> / Stops =
  match lowerAll types effects funs with
  | (_, _, Some m) -> stop m
  | (t, fs, None) -> (t, fs)
