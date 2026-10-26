/// Monomorphization: each function reached from the program's entry points copied once per
/// concrete instantiation reached, trait methods dispatched to their impls; the output has no
/// type variables. Then the share check (a function crossing threads mustn't reach a top-level
/// value threads can't share) and fusion (a pipeline of maps and filters under a consumer is one
/// loop).
open Types.Ty
open Core.Ir
open Core.Program

// the text from an index on
let private after (n: int) (s: string) : string = String.sub s n (String.length s - n)

/// Units of measure are erased, so measure arguments don't distinguish instances, and an empty row
/// (a function's effects: none) isn't shown, so a pure instance has the name it always had.
let mangle (v: Types.Vars.Vars) (name: string) (inst: list<Ty>) : string =
  let shownArg (t: Ty) =
    match t with
    | TMeas _ -> false
    | _ -> not (Types.Norm.isRowEmpty v t)
  match List.filter shownArg inst with
  | [] -> name
  | shown -> name + "<" + String.join "," (List.map (Types.Show.showFull v) shown) + ">"

/// A concrete type: quantified variables replaced, units of measure erased, a span its window, a
/// Buffer its cell, a share<F> its function.
let rec private concrete (v: Types.Vars.Vars) (inst: list<Ty>) (t: Ty) : Ty =
  match t with
  | TGen i -> List.item i inst
  // units of measure are erased
  | TCon(n, _) when Set.contains n nums -> TCon(n, [])
  | TMeas _ -> measOne
  // a window: Core's windowType
  | TCon("span", a) -> TCon(windowType, List.map (concrete v inst) a)
  // a window that grows
  | TCon("Buffer", a) -> TCon("ref", [ TCon(bufferType, List.map (concrete v inst) a) ])
  // a function that may cross threads is a function
  | TCon("share", [ f ]) -> concrete v inst f
  | TCon("$ext", _)
  | TCon("$total", _) -> concreteRow v inst t
  // an operation's own type in its clause: no value has it
  | TCon(n, []) when String.startsWith "$sk" n -> tUnit
  | TCon(n, a) -> TCon(n, List.map (concrete v inst) a)
  | TFun(a, b, r) -> TFun(concrete v inst a, concrete v inst b, concreteRow v inst r)
  | TTuple ts -> TTuple(List.map (concrete v inst) ts)
  | other -> other

/// A concrete row: closed, its labels in canonical order (as resolveRow).
and private concreteRow (v: Types.Vars.Vars) (inst: list<Ty>) (r: Ty) : Ty =
  let (ls, tail) = Types.Norm.rowParts v r
  let more =
    match tail with
    | TGen i -> fst (Types.Norm.rowParts v (List.item i inst))
    | _ -> []
  mkRow (List.sortBy (Types.Norm.labelName v) (List.append (List.map (concrete v inst) ls) more)) rowEmpty

/// Binds TGen variables of a generic type so that it equals a concrete one.
let rec private matchTy (binds: Buffer<option<Ty>>) (pattern: Ty) (conc: Ty) =
  match (pattern, conc) with
  | (TGen i, c) -> binds.[i] <- Some c
  | (TCon(_, ps), TCon(_, cs))
  | (TTuple ps, TTuple cs) when List.length ps = List.length cs -> List.iter2 (matchTy binds) ps cs
  | (TFun(a, b, r), TFun(c, d, s)) ->
    matchTy binds a c
    matchTy binds b d
    matchTy binds r s
  | _ -> ()

// an operator's trait and method
let private opTrait (op: string) : string * string =
  match op with
  | "+" -> ("Add", "add")
  | "-" -> ("Num", "sub")
  | "*" -> ("Num", "mul")
  | "/" -> ("Num", "div")
  | "%" -> ("Num", "rem")
  | "="
  | "<>" -> ("Eq", "equal")
  | _ -> ("Ord", "compare")

/// A float, or a vector of floats: what [<FastMath>]'s fast operators are for.
let private isFloaty (t: Ty) : bool =
  match t with
  | TCon(n, []) ->
    match vectorInfo n with
    | Some(e, _) -> Set.contains e floats
    | None -> Set.contains n floats
  | _ -> false

let private isPrim (t: Ty) : bool =
  match t with
  | TCon(n, []) -> Set.contains n prims
  | _ -> false

let private isDyn (t: Ty) : bool =
  match t with
  | TCon(n, []) -> isDynName n
  | _ -> false

/// The program with its types' fields as monomorphization gives every other type: units of measure
/// erased, a Buffer as its cell, a span as its window. The passes after it read a field's type from
/// the table.
let lowered (prog: Program) : Program =
  let rec lower (t: Ty) : Ty =
    match t with
    | TCon(n, _) when Set.contains n nums -> TCon(n, [])
    | TMeas _ -> measOne
    | TCon("Buffer", a) -> TCon("ref", [ TCon(bufferType, List.map lower a) ])
    | TCon("span", a) -> TCon(windowType, List.map lower a)
    | TCon(n, a) -> TCon(n, List.map lower a)
    | TFun(a, b, r) -> TFun(lower a, lower b, r)
    | TTuple ts -> TTuple(List.map lower ts)
    | other -> other
  let one (info: TypeInfo) : TypeInfo =
    match info.def with
    | RecordDef fs -> { info with def = RecordDef(List.map (fun (f, t) -> (f, lower t)) fs) }
    | UnionDef cs -> { info with def = UnionDef(List.map (fun (c, ts) -> (c, List.map lower ts)) cs) }
    | CUnionDef cs -> { info with def = CUnionDef(List.map (fun (c, t) -> (c, lower t)) cs) }
  { prog with types = Map.map (fun _ info -> one info) prog.types }

/// Copies of each function reached from roots, at each instantiation reached: a generic function
/// once per type arguments, the others once. def: a function's checked definition; external: a
/// non-generic function another module has the code of, which isn't copied.
let runFrom (prog: Program) (def: string -> FunDef) (roots: list<string>) (external: string -> bool) : list<MFun> / Stops =
  let v = Types.Vars.make ()
  let seen = ref Set.empty
  let queue = Buffer.empty
  let next = ref 0
  let out = Buffer.empty
  let request (name: string) (inst: list<Ty>) : string =
    let m = mangle v name inst
    // an instance another module has the code of: a non-generic function's, or the pure instance
    // (its rows empty) of one generic only in its effects
    let erased (t: Ty) =
      match t with
      | TMeas _ -> true
      | _ -> Types.Norm.isRowEmpty v t
    let own = List.forall erased inst
    if not (Set.contains m seen.Value) then
      seen.Value <- Set.add m seen.Value
      if not (own && external name) then
        Buffer.push (name, inst) queue
    m
  let count = ref 0
  // the name an impl is kept under for a type, lowered already (concrete) or not: a span is a
  // window, a Buffer a cell over one
  let implHead (t: Ty) : string =
    match t with
    | TCon(n, _) when n = windowType -> "span"
    | TCon("ref", [ TCon(n, _) ]) when n = bufferType -> "Buffer"
    | TCon(n, _) -> n
    | TTuple ts -> tupleHead (List.length ts)
    | other -> Types.Show.showFull v other
  /// The impl function (instantiated) for trait method `tr.m` at concrete type t.
  let implFn (tr: string) (m: string) (t: Ty) (methodTy: Ty) : CExpr =
    match Map.tryFind (tr, implHead t) prog.impls with
    | Some table ->
      let fname = Map.find m table
      let fd = def fname
      let binds = Buffer.create fd.ngen None
      matchTy binds (List.fold (fun acc (_, p) -> tfun p acc) fd.ret (List.rev fd.pars)) methodTy
      let inst = List.map (fun (b: option<Ty>) -> Option.defaultValue tInt b) (Array.toList (Buffer.toArray binds))
      mk (CGlobal(request fname inst, Some [])) methodTy
    | None -> stop $"{Types.Show.show v t} does not implement {tr}"
  /// A trait method applied to (exactly its arity of) arguments, for a primitive type.
  let builtinMethod (q: string) (t: Ty) (args: list<CExpr>) (resTy: Ty) : CExpr =
    let a (i: int) = List.item i args
    let k =
      match q with
      | "Add.add" -> CBin("+", a 0, a 1)
      | "Add.zero" ->
        match t with
        | TCon("f64", [])
        | TCon("f32", []) -> CFloat 0.0
        | TCon("string", []) -> CStr ""
        | _ -> CInt(i64 0)
      | "Num.sub" -> CBin("-", a 0, a 1)
      | "Num.mul" -> CBin("*", a 0, a 1)
      | "Num.div" -> CBin("/", a 0, a 1)
      | "Num.rem" -> CBin("%", a 0, a 1)
      | "Num.neg" -> CNeg(a 0)
      | "Eq.equal" -> CBin("=", a 0, a 1)
      | "Ord.compare" -> CPrim("compare", args)
      | "Show.show" -> CPrim("string", args)
      // a number, a string, a char or a bool differs as a whole: the prelude's diffShown
      | "Diff.diff" -> CApp(mk (CGlobal(request "diffShown" [ t ], Some [])) (tfun t (tfun t resTy)), args)
      | "Format.format" -> CPrim("format", args)
      | "Hash.hash" -> CPrim("hash", args)
      | _ -> stop $"{Types.Show.show v t} has no built-in {q}"
    mk k resTy
  /// A trait's methods, in the order of a dyn Trait's vtable (by name).
  let methodLists = ref Map.empty
  let methodsOf (tr: string) : list<string> =
    match Map.tryFind tr methodLists.Value with
    | Some ms -> ms
    | None ->
      let owned = List.filter (fun (m: TraitMethod) -> m.owner = tr) (List.map snd (Map.toList prog.traitMethods))
      let ms = List.sort (List.map (fun (m: TraitMethod) -> m.name) owned)
      methodLists.Value <- Map.add tr ms methodLists.Value
      ms
  /// Trait method `q` at its instantiation, applied to args (possibly none).
  let rec dispatch (q: string) (inst: list<Ty>) (headTy: Ty) (args: list<CExpr>) (resTy: Ty) : CExpr =
    let tm = Map.find q prog.traitMethods
    let t = List.head inst
    let rec arityOf (x: Ty) : int =
      match x with
      | TFun(_, r, _) -> 1 + arityOf r
      | _ -> 0
    let arity = arityOf headTy
    let inlined (xs: list<CExpr>) (res: Ty) : CExpr =
      match t with
      | TTuple ts -> tupleMethod q ts xs res
      | _ ->
        if isDyn t then
          // a dyn value: the method its vtable has, given the value and the other arguments
          let index = List.findIndex (fun m -> m = tm.name) (methodsOf tm.owner)
          mk (CPrim($"dyn.call:{index}", xs)) res
        else
          builtinMethod q t xs res
    let isTuple =
      match t with
      | TTuple _ -> true
      | _ -> false
    let byImpl = Map.containsKey (tm.owner, Types.Show.showFull v t) prog.impls || Map.containsKey (tm.owner, implHead t) prog.impls
    if not (isPrim t || isTuple || isDyn t) || byImpl then
      let f = implFn tm.owner tm.name t headTy
      if List.isEmpty args then f else mk (CApp(f, args)) resTy
    else if List.length args = arity then
      inlined args resTy
    else
      // a built-in method used as a value: wrap it in a lambda
      let rec peelN (n: int) (x: Ty) : list<Ty> * Ty =
        match (n, x) with
        | (0, r) -> ([], r)
        | (_, TFun(p, r, _)) ->
          let (ps, res) = peelN (n - 1) r
          (p :: ps, res)
        | _ -> panic "dispatch: not a function"
      let (ptys, res) = peelN arity headTy
      let param (p: Ty) =
        count.Value <- count.Value + 1
        ($"$tm{count.Value}", p)
      let ps = List.map param ptys
      let lamE = mk (CLam(ps, inlined (List.map (fun (x, p) -> mk (CLocal x) p) ps) res)) headTy
      if List.isEmpty args then lamE else mk (CApp(lamE, args)) resTy
  /// Structural Eq/Ord/Show/Hash for tuples, component by component.
  and tupleMethod (q: string) (ts: list<Ty>) (args: list<CExpr>) (resTy: Ty) : CExpr =
    let temp (e: CExpr) =
      count.Value <- count.Value + 1
      ($"$tt{count.Value}", e)
    let bound = List.map temp args
    let comp (b: string * CExpr) (i: int) (t: Ty) = mk (CField(mk (CLocal(fst b)) (snd b).ty, i)) t
    let callM (m: string) (t: Ty) (cargs: list<CExpr>) (res: Ty) = dispatch m [ t ] (Types.Norm.substGen v [ t ] (Map.find m prog.traitMethods).ty) cargs res
    let indexed = List.indexed ts
    let body =
      match (q, bound) with
      | ("Show.show", [ a ]) ->
        let parts = List.map (fun (i, t) -> callM "Show.show" t [ comp a i t ] tStr) indexed
        let sep (x: CExpr) (y: CExpr) = mk (CBin("+", mk (CBin("+", x, mk (CStr ", ") tStr)) tStr, y)) tStr
        let inner = List.reduce sep parts
        mk (CBin("+", mk (CBin("+", mk (CStr "(") tStr, inner)) tStr, mk (CStr ")") tStr)) tStr
      | ("Eq.equal", [ a; b ]) ->
        let step (acc: CExpr) (it: int * Ty) =
          let (i, t) = it
          mk (CIf(callM "Eq.equal" t [ comp a i t; comp b i t ] tBool, acc, mk (CBool false) tBool)) tBool
        List.fold step (mk (CBool true) tBool) (List.rev indexed)
      | ("Ord.compare", [ a; b ]) ->
        // lexicographic: the first component that differs decides
        let step (acc: CExpr) (it: int * Ty) =
          let (i, t) = it
          count.Value <- count.Value + 1
          let c = $"$tc{count.Value}"
          let cv = mk (CLocal c) tInt
          let differs = mk (CBin("<>", cv, mk (CInt(i64 0)) tInt)) tBool
          mk (CLet(c, callM "Ord.compare" t [ comp a i t; comp b i t ] tInt, mk (CIf(differs, cv, acc)) tInt)) tInt
        List.fold step (mk (CInt(i64 0)) tInt) (List.rev indexed)
      | ("Hash.hash", [ a ]) ->
        let step (acc: CExpr) (it: int * Ty) =
          let (i, t) = it
          let h = callM "Hash.hash" t [ comp a i t ] tInt
          // wrapping: a hash may overflow on purpose
          mk (CPrim("wrap+", [ mk (CPrim("wrap*", [ acc; mk (CInt(i64 31)) tInt ])) tInt; h ])) tInt
        List.fold step (mk (CInt(i64 17)) tInt) indexed
      | _ -> stop $"tuples have no {q}"
    List.fold (fun (acc: CExpr) (b: string * CExpr) -> mk (CLet(fst b, snd b, acc)) acc.ty) body (List.rev bound)
  /// The functions in the vtable of a dyn Trait over type t, one per method: each takes the dyn
  /// value and the method's other arguments, and applies t's impl to the value it holds. They are
  /// ordinary functions, so the passes after this one see them (and call the impl with as many
  /// arguments as it takes).
  let entries = ref Set.empty
  let entryFor (tr: string) (m: string) (t: Ty) : string =
    let mangled = mangle v tr [ t ]
    let name = $"dyn:{mangled}#{m}"
    if not (Set.contains name entries.Value) then
      entries.Value <- Set.add name entries.Value
      let tm = Map.find (tr + "." + m) prog.traitMethods
      // through dyn, the ambient row is empty (0025)
      let methodTy = Types.Norm.substGen v [ t; rowEmpty ] tm.ty
      let rec split (x: Ty) : list<Ty> * Ty =
        match x with
        | TFun(a, r, _) ->
          let (ps, res) = split r
          (a :: ps, res)
        | r -> ([], r)
      let (ps, res) = split methodTy
      let dynTy = TCon("dyn:" + tr, [])
      let others = List.mapi (fun i p -> ($"$a{i}", p)) (List.tail ps)
      let value = mk (CPrim("dyn.unbox", [ mk (CLocal "$self") dynTy ])) t
      let body = dispatch (tr + "." + m) [ t ] methodTy (value :: List.map (fun (x, p) -> mk (CLocal x) p) others) res
      // where it is from, for debug info: the impl's file
      let key =
        match t with
        | TCon(n, _) -> n
        | other -> Types.Show.showFull v other
      let file =
        match Map.tryFind (tr, key) prog.impls with
        | Some table -> (def (Map.find m table)).file
        | None -> ""
      let entry : MFun = { name = name; pars = ("$self", dynTy) :: others; ret = res; row = rowEmpty; body = body; file = file; line = 1 }
      Buffer.push entry out
    name
  /// An operator on a non-primitive type calls the type's trait impl.
  let operator (op: string) (a: CExpr) (b: CExpr) (resTy: Ty) : CExpr =
    let (tr, m) = opTrait op
    let methodTy = Types.Norm.substGen v [ a.ty ] (Map.find (tr + "." + m) prog.traitMethods).ty
    let callE = dispatch (tr + "." + m) [ a.ty ] methodTy [ a; b ] (if tr = "Ord" then tInt else resTy)
    match op with
    | "<>" -> mk (CNot callE) tBool
    | "<"
    | ">"
    | "<="
    | ">=" -> mk (CBin(op, callE, mk (CInt(i64 0)) tInt)) tBool
    | _ -> callE
  // a root generic only in its effects is its pure instance
  for r in roots do
    request r (List.replicate (def r).ngen rowEmpty) |> ignore
  while next.Value < Buffer.length queue do
    let (name, inst) = queue.[next.Value]
    next.Value <- next.Value + 1
    let f = def name
    let ct (t: Ty) = concrete v inst t
    let pars (ps: list<string * Ty>) = List.map (fun (x, t) -> (x, ct t)) ps
    // names numbered per instance: its code doesn't depend on others'
    count.Value <- 0
    let rec ex (e: CExpr) : CExpr =
      match e.k with
      | CPrim(op, [ x ]) when String.startsWith "dyn.box:" op ->
        // a value made a dyn Trait: its vtable's functions at the value's type
        let tr = after 8 op
        let t = ct x.ty
        let refs = List.map (fun m -> mk (CPrim("fn:" + entryFor tr m t, [])) tUnit) (methodsOf tr)
        mk (CPrim(op, ex x :: refs)) (ct e.ty)
      | CApp({ k = CGlobal(q, Some gi); ty = hty }, args) when Map.containsKey q prog.traitMethods ->
        dispatch q (List.map ct gi) (ct hty) (List.map ex args) (ct e.ty)
      | CGlobal(q, Some gi) when Map.containsKey q prog.traitMethods -> dispatch q (List.map ct gi) (ct e.ty) [] (ct e.ty)
      // a global function opened to a row (Typer.opened) that came out its own: as it is
      | CPrim("eff.open", [ g ]) when concrete v inst g.ty = concrete v inst e.ty -> ex g
      | CBin(op, a, b) when not (isPrim (concrete v inst a.ty)) -> operator (String.replace (String.replace op "wrap" "") "fast" "") (ex a) (ex b) (ct e.ty)
      // [<FastMath>]'s mark is for floats
      | CBin(op, a, b) when String.startsWith "fast" op && not (isFloaty (concrete v inst a.ty)) -> ex { e with k = CBin(after 4 op, a, b) }
      | CNeg a when not (isPrim (concrete v inst a.ty)) ->
        let methodTy = Types.Norm.substGen v [ ct a.ty ] (Map.find "Num.neg" prog.traitMethods).ty
        mk (CApp(implFn "Num" "neg" (ct a.ty) methodTy, [ ex a ])) (ct e.ty)
      | _ ->
        let k =
          match e.k with
          | CGlobal(g, Some gi) -> CGlobal(request g (List.map ct gi), Some [])
          // self-recursion
          | CGlobal(g, None) -> CGlobal(request g inst, Some [])
          | CLam(ps, b) -> CLam(pars ps, ex b)
          | CLetFun(n, r, ps, b, rest) ->
            let ps2 = pars ps
            let b2 = ex b
            CLetFun(n, r, ps2, b2, ex rest)
          | CLetRec(fs, rest) ->
            let fs2 = List.map (fun (n, ps, b) -> (n, pars ps, ex b)) fs
            CLetRec(fs2, ex rest)
          | CMatch(s, cases) ->
            let s2 = ex s
            CMatch(s2, List.map (fun (p, g, b) -> (mapPatTypes ct p, Option.map ex g, ex b)) cases)
          | CPerform(l, op, args) -> CPerform(ct l, op, List.map ex args)
          | CHandle(l, b, cls, (r, rt), rb) ->
            let clause (c: int * list<string * Ty> * (string * Ty) * CExpr) =
              match c with
              | (op, ps, (kn, kt), body) -> (op, pars ps, (kn, ct kt), ex body)
            let cls2 = List.map clause cls
            let l2 = ct l
            let b2 = ex b
            CHandle(l2, b2, cls2, (r, ct rt), ex rb)
          | other -> mapChildren ex other
        { k = k; ty = ct e.ty; id = 0 }
    let instance : MFun = { name = mangle v name inst; pars = pars f.pars; ret = ct f.ret; row = ct f.row; body = ex f.body; file = f.file; line = f.line }
    Buffer.push instance out
  Array.toList (Buffer.toArray out)

/// The whole program from its entry points: main, the exported functions, the tests and the
/// values' initializers.
let run (prog: Program) : list<MFun> / Stops =
  let defs = Map.ofList (List.map (fun (f: FunDef) -> (f.name, f)) prog.funs)
  let mainRoot = if Map.containsKey "main" defs then [ "main" ] else []
  let roots = List.concat [ mainRoot; List.map (fun (e: Export) -> e.fname) prog.exports; prog.tests; List.map snd prog.values ]
  runFrom prog (fun n -> Map.find n defs) roots (fun _ -> false)

/// What a function reaches that threads can't share: the first top-level value of a type that
/// isn't Share it uses, following its calls (and the local functions it calls), with the functions
/// on the way there, its own first. external: what another module's code says of its functions
/// (the driver's ABI); unknown functions reach nothing.
let reaching (prog: Program) (funs: list<MFun>) (external: string -> option<string * list<string> * Ty>) : (string -> option<string * list<string> * Ty>) * (MFun -> CExpr -> option<string * list<string> * Ty>) =
  let v = Types.Vars.make ()
  let byName = Map.ofList (List.map (fun (f: MFun) -> (f.name, f)) funs)
  // the values of let-bound locals and local functions, by unique name, per function: one that
  // calls a function it captured runs that one's code
  let locals = ref Map.empty
  let localsOf (f: MFun) : Map<string, CExpr> =
    match Map.tryFind f.name locals.Value with
    | Some d -> d
    | None ->
      let d = ref Map.empty
      let rec collect (e: CExpr) =
        match e.k with
        | CLetFun(n, _, ps, b, _) -> d.Value <- Map.add n { k = CLam(ps, b); ty = e.ty; id = 0 } d.Value
        | CLetRec(fs, _) ->
          for (n, ps, b) in fs do
            d.Value <- Map.add n { k = CLam(ps, b); ty = e.ty; id = 0 } d.Value
        | CLet(x, w, _) -> d.Value <- Map.add x w d.Value
        | _ -> ()
        List.iter collect (children e.k)
      collect f.body
      locals.Value <- Map.add f.name d.Value locals.Value
      d.Value
  let memo = ref Map.empty
  let visiting = ref Set.empty
  // the functions the outermost walk has gone through and found nothing in: a walk that meets one
  // again doesn't walk it again (so a walk is linear, whatever cycles it meets), and when the
  // outermost walk ends with nothing, each of them reaches nothing. A walk meeting a function it's
  // inside of takes nothing from it: what that one reaches, that walk finds.
  let nothingYet = ref Set.empty
  /// What an expression of a function reaches (its locals, for the local functions it calls).
  let rec inExpr (mine: Map<string, CExpr>) (seen: ref<Set<string>>) (e: CExpr) : option<string * list<string> * Ty> =
    let here =
      match e.k with
      | CGlobalVal x ->
        match Types.Repr.shareBlocker v (fun _ -> ()) prog.types Set.empty e.ty with
        | Some _ -> Some(x, [], e.ty)
        | None -> None
      | CGlobal(g, _) -> through g
      | CPrim(p, _) when String.startsWith "fn:" p -> through (after 3 p)
      | CLocal x ->
        match (e.ty, Map.tryFind x mine) with
        | (TFun _, Some w) when not (Set.contains x seen.Value) ->
          seen.Value <- Set.add x seen.Value
          inExpr mine seen w
        | _ -> None
      | _ -> None
    match here with
    | Some r -> Some r
    | None -> List.tryPick (inExpr mine seen) (children e.k)
  /// What calling g reaches, g on the way.
  and through (g: string) : option<string * list<string> * Ty> =
    Option.map (fun (x, path, t) -> (x, List.head (String.split "<" g) :: path, t)) (reach g)
  and reach (g: string) : option<string * list<string> * Ty> =
    match Map.tryFind g memo.Value with
    | Some r -> r
    | None when Set.contains g nothingYet.Value -> None
    | None ->
      match Map.tryFind g byName with
      | Some f when not (Set.contains g visiting.Value) ->
        visiting.Value <- Set.add g visiting.Value
        let r = inExpr (localsOf f) (ref Set.empty) f.body
        visiting.Value <- Set.remove g visiting.Value
        match r with
        | Some _ -> memo.Value <- Map.add g r memo.Value
        | None -> nothingYet.Value <- Set.add g nothingYet.Value
        if Set.isEmpty visiting.Value then
          // the outermost walk: with nothing found, nothing was there to find
          if Option.isNone r then
            for h in Set.toList nothingYet.Value do
              memo.Value <- Map.add h None memo.Value
          nothingYet.Value <- Set.empty
        r
      | Some _ -> None
      | None -> external g
  (reach, (fun (f: MFun) (e: CExpr) -> inExpr (localsOf f) (ref Set.empty) e))

/// A function given to another thread (share.fn, from the checker) mustn't reach a top-level value
/// threads can't share, such as a `ref`: each thread would change it at once. Checked through what
/// the function calls, after monomorphization so that every trait method call has its impl (and
/// other modules' functions by what their code says, external); then the marks go.
let checkSharedWith (prog: Program) (external: string -> option<string * list<string> * Ty>) (funs: list<MFun>) : list<MFun> / Stops =
  let v = Types.Vars.make ()
  let (_, inExpr) = reaching prog funs external
  let check (f: MFun) (line: int) (start: CExpr) =
    match inExpr f start with
    | Some(x, path, t) ->
      let through = if List.isEmpty path then "" else " (through " + String.join ", " (List.map (fun p -> "'" + p + "'") path) + ")"
      let part = Option.defaultValue t (Types.Repr.shareBlocker v (fun _ -> ()) prog.types Set.empty t)
      let holds = if part = t then "" else $", which holds {Types.Show.show v part}"
      let message = $"this function crosses threads, but it uses the top-level value '{x}'{through} : {Types.Show.show v t}{holds}, which threads can't share; pass it what it needs instead"
      Stops.stop { file = f.file; line = line; message = message }
    | None -> ()
  let rec strip (f: MFun) (line: int) (e: CExpr) : CExpr =
    match e.k with
    | CLine(l, _) -> { e with k = mapChildren (strip f l) e.k }
    | CPrim("share.fn", [ g ]) ->
      check f line g
      strip f line g
    | CPrim("share.as", [ g ]) -> strip f line g
    | k -> { e with k = mapChildren (strip f line) k }
  List.map (fun (f: MFun) -> { f with body = strip f f.line f.body }) funs

let checkShared (prog: Program) (funs: list<MFun>) : list<MFun> / Stops = checkSharedWith prog (fun _ -> None) funs

// ---- fusion: a pipeline of maps and filters over a list or an array, ending in a consumer (sum,
// sumBy, length, fold, iter), becomes one loop that builds no intermediate list or array:
//   List.init n g, a list, Array.init n g or an array
//   |> map f |> filter p … (List's or Array's)
//   |> sum / sumBy f / length / fold f s / iter f
// A pipeline of several maps and filters that builds a list (or of maps building an array) is one
// pass building that list or array. The stages run per element instead of per list, so their
// functions must be pure lambdas (arithmetic, comparisons, local bindings, conditionals): running
// them in another order can't change what the program does. A consumer's function that does
// something else (iter's, usually) still sees the elements in order; the stages must then be
// unable to panic, so no effect of the consumer happens that a panic in a stage would have
// prevented.

type private Stage =
  | MapS of CExpr
  | FilterS of CExpr

type private Source =
  /// List.init n g, Array.init n g
  | Init of CExpr * CExpr
  | OfList of CExpr
  | OfArray of CExpr

let private isIntType (t: Ty) : bool =
  match t with
  | TCon(n, []) -> Set.contains n ints
  | _ -> false

let rec private isPure (e: CExpr) : bool =
  match e.k with
  | CInt _
  | CFloat _
  | CBool _
  | CUnit
  | CLocal _ -> true
  | CBin(_, a, b) -> isPure a && isPure b
  | CNeg a
  | CNot a
  | CLine(_, a) -> isPure a
  | CIf(c, t, f) -> isPure c && isPure t && isPure f
  | CLet(_, w, b) -> isPure w && isPure b
  | CPrim("conv", args)
  | CPrim("wrap+", args)
  | CPrim("wrap-", args)
  | CPrim("wrap*", args) -> List.forall isPure args
  | _ -> false

/// Pure, and can't panic: no checked integer arithmetic (it traps on overflow), no division that
/// could be by zero.
let rec private total (e: CExpr) : bool =
  let safe =
    match e.k with
    | CBin("+", a, _)
    | CBin("-", a, _)
    | CBin("*", a, _) when isIntType a.ty -> false
    | CBin("/", a, b)
    | CBin("%", a, b) when isIntType a.ty ->
      match b.k with
      | CInt d -> d <> i64 0 && d <> i64 (-1)
      | _ -> false
    | CNeg a when isIntType a.ty -> false
    | k -> List.forall total (children k)
  isPure e && safe

let private lambdaBody (e: CExpr) (arity: int) : option<CExpr> =
  match e.k with
  | CLam(ps, body) when List.length ps = arity -> Some body
  | _ -> None

let private pureLambda (e: CExpr) (arity: int) : bool = Option.exists isPure (lambdaBody e arity)

/// (lambda applied to args) as lets of its parameters around its body
let private beta (lam: CExpr) (args: list<CExpr>) : CExpr =
  match lam.k with
  | CLam(ps, body) -> List.fold (fun (acc: CExpr) (pa: (string * Ty) * CExpr) -> mk (CLet(fst (fst pa), snd pa, acc)) acc.ty) body (List.rev (List.zip ps args))
  | _ -> panic "beta"

let private numeric (t: Ty) : bool =
  match t with
  | TCon(n, []) -> Set.contains n nums
  | _ -> false

let private zeroOf (t: Ty) : CExpr =
  match t with
  | TCon(n, []) when Set.contains n floats -> mk (CFloat 0.0) t
  | _ -> mk (CInt(i64 0)) t

let private elemOf (t: Ty) : Ty =
  match t with
  | TCon("list", [ el ])
  | TCon("array", [ el ]) -> el
  // a span: read as an array is
  | TCon(n, [ el ]) when n = windowType -> el
  // a Buffer
  | TCon("ref", [ TCon(n, [ el ]) ]) when n = bufferType -> el
  | _ -> panic "fusion: a type that has no elements"

let private baseName (g: string) : string =
  match String.indexOf "<" g with
  | Some i -> String.sub g 0 i
  | None -> g

/// Pipelines fused, in each function.
let fuse (funs: list<MFun>) : list<MFun> =
  let v = Types.Vars.make ()
  let count = ref 0
  let fresh (p: string) =
    count.Value <- count.Value + 1
    $"$fuse{count.Value}.{p}"
  // a function with effects is called as it is: its stages would run inside a loop with none
  let rec pureFor (n: int) (t: Ty) : bool =
    if n = 0 then
      true
    else
      match t with
      | TFun(_, r, row) -> Types.Norm.isRowEmpty v row && pureFor (n - 1) r
      | _ -> false
  let call (e: CExpr) : option<string * list<CExpr>> =
    match e.k with
    | CApp({ k = CGlobal(g, _); ty = hty }, args) -> if pureFor (List.length args) hty then Some(baseName g, args) else None
    | _ -> None
  /// The pipeline under a consumer of a list (or an array): its stages, in order, and its source.
  let rec chain (isArray: bool) (xs: CExpr) (stages: list<Stage>) : Source * list<Stage> =
    let m = if isArray then "Collections.Array." else "Collections.List."
    let spanOf =
      match xs.k with
      | CPrim("span.ofArray", [ a ])
      | CPrim("span.ofBuffer", [ a ]) -> Some a
      | _ -> None
    match (call xs, spanOf) with
    // an array as a span: its elements are the span's
    | (_, Some a) when isArray -> chain isArray a stages
    | (Some(f, [ g; ys ]), _) when f = m + "map" && pureLambda g 1 -> chain isArray ys (MapS g :: stages)
    | (Some(f, [ p; ys ]), _) when f = m + "filter" && pureLambda p 1 -> chain isArray ys (FilterS p :: stages)
    | (Some(f, [ n; g ]), _) when f = m + "init" && pureLambda g 1 -> (Init(n, g), stages)
    | (Some("Collections.Array.toList", [ a ]), _) when not isArray -> (OfArray a, stages)
    | _ -> ((if isArray then OfArray xs else OfList xs), stages)
  /// Worth a loop of its own: a source that builds a list or array, or a stage to run.
  let fusible (src: Source) (stages: list<Stage>) : bool =
    match src with
    | Init _ -> true
    | OfArray _
    | OfList _ -> not (List.isEmpty stages)
  let stagesTotal (stages: list<Stage>) : bool =
    let one (s: Stage) =
      match s with
      | MapS f
      | FilterS f -> total (Option.get (lambdaBody f 1))
    List.forall one stages
  /// The stages applied to element x: `keep y` for an element that survives them, `skip ()` for
  /// one a filter drops.
  let rec pass (x: CExpr) (stages: list<Stage>) (keep: CExpr -> CExpr) (skip: unit -> CExpr) : CExpr =
    match stages with
    | [] -> keep x
    | MapS f :: rest ->
      let y = fresh "x"
      let fx = beta f [ x ]
      let inner = pass (mk (CLocal y) fx.ty) rest keep skip
      mk (CLet(y, fx, inner)) inner.ty
    | FilterS p :: rest ->
      let inner = pass x rest keep skip
      mk (CIf(beta p [ x ], inner, skip ())) inner.ty
  /// The surviving elements folded: acc starts as `start`, then acc <- step acc y for each.
  let foldOver (src: Source) (stages: list<Stage>) (start: CExpr) (step: CExpr -> CExpr -> CExpr) : CExpr =
    let accTy = start.ty
    match src with
    | OfList xs ->
      // a local function over the list's cells, as the library's own folds (a loop after
      // compilation): acc is a parameter, since a local function can't share a mutable
      let go = fresh "go"
      let acc = fresh "acc"
      let cur = fresh "xs"
      let rest = fresh "rest"
      let accRef = mk (CLocal acc) accTy
      let x = fresh "x"
      let el = elemOf xs.ty
      let goTy = tfun accTy (tfun xs.ty accTy)
      let again (a: CExpr) = mk (CApp(mk (CLocal go) goTy, [ a; mk (CLocal rest) xs.ty ])) accTy
      let consCase = (CPCtor("list", 1, [ CPVar(x, el); CPVar(rest, xs.ty) ]), None, pass (mk (CLocal x) el) stages (fun y -> again (step accRef y)) (fun () -> again accRef))
      let body = mk (CMatch(mk (CLocal cur) xs.ty, [ (CPCtor("list", 0, []), None, accRef); consCase ])) accTy
      mk (CLetRec([ (go, [ (acc, accTy); (cur, xs.ty) ], body) ], mk (CApp(mk (CLocal go) goTy, [ start; xs ])) accTy)) accTy
    | Init _
    | OfArray _ ->
      let acc = fresh "acc"
      let nv = fresh "n"
      let i = fresh "i"
      let accRef = mk (CLocal acc) accTy
      // the count, then (for an array) the array itself, in the order the program has them
      let (cnt, element, bind) =
        match src with
        | Init(n, g) -> (n, (fun (iv: CExpr) -> beta g [ iv ]), (fun (e: CExpr) -> e))
        | OfArray a ->
          let av = fresh "a"
          let aRef = mk (CLocal av) a.ty
          (mk (CPrim("Array.length", [ aRef ])) tInt, (fun (iv: CExpr) -> mk (CPrim("array.get", [ aRef; iv ])) (elemOf a.ty)), (fun (e: CExpr) -> mk (CLet(av, a, e)) e.ty))
        | OfList _ -> panic "unreachable"
      let x0 = fresh "x"
      let gi = element (mk (CLocal i) tInt)
      let body = mk (CLet(x0, gi, pass (mk (CLocal x0) gi.ty) stages (fun y -> mk (CAssign(acc, step accRef y)) tUnit) (fun () -> mk CUnit tUnit))) tUnit
      let last = mk (CBin("-", mk (CLocal nv) tInt, mk (CInt(i64 1)) tInt)) tInt
      let forLoop = mk (CFor(i, mk (CInt(i64 0)) tInt, mk (CInt(i64 1)) tInt, last, body)) tUnit
      bind (mk (CLet(nv, cnt, mk (CLetMut(acc, start, mk (CSeq(forLoop, accRef)) accTy)) accTy)) accTy)
  /// The surviving elements as a list, built in one pass.
  let listOf (src: Source) (stages: list<Stage>) (resTy: Ty) : CExpr =
    let el = elemOf resTy
    let nil = mk (CCtor("list", 0, [])) resTy
    let cons (y: CExpr) (tl: CExpr) = mk (CCtor("list", 1, [ y; tl ])) resTy
    match src with
    | Init(n, g) ->
      // from the last element down, so no reversing (the stages are pure)
      let acc = fresh "acc"
      let nv = fresh "n"
      let i = fresh "i"
      let x0 = fresh "x"
      let accRef = mk (CLocal acc) resTy
      let gi = beta g [ mk (CLocal i) tInt ]
      let body = mk (CLet(x0, gi, pass (mk (CLocal x0) gi.ty) stages (fun y -> mk (CAssign(acc, cons y accRef)) tUnit) (fun () -> mk CUnit tUnit))) tUnit
      let last = mk (CBin("-", mk (CLocal nv) tInt, mk (CInt(i64 1)) tInt)) tInt
      let forLoop = mk (CFor(i, last, mk (CInt(i64 (-1))) tInt, mk (CInt(i64 0)) tInt, body)) tUnit
      mk (CLet(nv, n, mk (CLetMut(acc, nil, mk (CSeq(forLoop, accRef)) resTy)) resTy)) resTy
    | _ ->
      // reversed as it's built, then reversed again: both in place when the cells are unique
      let reversed = foldOver src stages nil (fun acc y -> cons y acc)
      let rv = fresh "rev"
      let out = fresh "out"
      let cur = fresh "ys"
      let y = fresh "y"
      let rest = fresh "rest"
      let rvTy = tfun resTy (tfun resTy resTy)
      let again = mk (CApp(mk (CLocal rv) rvTy, [ cons (mk (CLocal y) el) (mk (CLocal out) resTy); mk (CLocal rest) resTy ])) resTy
      let cases = [ (CPCtor("list", 0, []), None, mk (CLocal out) resTy); (CPCtor("list", 1, [ CPVar(y, el); CPVar(rest, resTy) ]), None, again) ]
      let body = mk (CMatch(mk (CLocal cur) resTy, cases)) resTy
      mk (CLetRec([ (rv, [ (out, resTy); (cur, resTy) ], body) ], mk (CApp(mk (CLocal rv) rvTy, [ nil; reversed ])) resTy)) resTy
  /// Maps over an array (or Array.init) as one array: Array.init's loop with the maps inside.
  let arrayOf (src: Source) (stages: list<Stage>) (resTy: Ty) : CExpr =
    let nv = fresh "n"
    let r = fresh "r"
    let i = fresh "i"
    let (cnt, element, bind) =
      match src with
      | Init(n, g) -> (n, (fun (iv: CExpr) -> beta g [ iv ]), (fun (e: CExpr) -> e))
      | OfArray a ->
        let av = fresh "a"
        let aRef = mk (CLocal av) a.ty
        (mk (CPrim("Array.length", [ aRef ])) tInt, (fun (iv: CExpr) -> mk (CPrim("array.get", [ aRef; iv ])) (elemOf a.ty)), (fun (e: CExpr) -> mk (CLet(av, a, e)) e.ty))
      | OfList _ -> panic "unreachable"
    let mapped (iv: CExpr) = pass (element iv) stages (fun (y: CExpr) -> y) (fun () -> panic "a filter building an array")
    let n = mk (CLocal nv) tInt
    let first = mk (CPrim("Array.create", [ n; mapped (mk (CInt(i64 0)) tInt) ])) resTy
    let set = mk (CArraySet(r, mk (CLocal i) tInt, mapped (mk (CLocal i) tInt))) tUnit
    let last = mk (CBin("-", n, mk (CInt(i64 1)) tInt)) tInt
    let fill = mk (CFor(i, mk (CInt(i64 1)) tInt, mk (CInt(i64 1)) tInt, last, set)) tUnit
    let filled = mk (CLetMut(r, first, mk (CSeq(fill, mk (CLocal r) resTy)) resTy)) resTy
    let empty = mk (CPrim("array.lit", [])) resTy
    let isEmpty = mk (CBin("<=", n, mk (CInt(i64 0)) tInt)) tBool
    bind (mk (CLet(nv, cnt, mk (CIf(isEmpty, empty, filled)) resTy)) resTy)
  let rec ex (e: CExpr) : CExpr =
    let consume (isArray: bool) (xs: CExpr) (pureStep: bool) (k: Source -> list<Stage> -> CExpr) : option<CExpr> =
      let (src, stages) = chain isArray xs []
      // a consumer whose function may do anything needs stages that can't panic
      if fusible src stages && (pureStep || stagesTotal stages) then Some(k src stages) else None
    let fused =
      match call e with
      | Some(f, [ xs ]) when (f = "Collections.List.sum" || f = "Collections.Array.sum") && numeric e.ty ->
        consume (String.contains "Array" f) xs true (fun src st -> foldOver src st (zeroOf e.ty) (fun a x -> mk (CBin("+", a, x)) e.ty))
      | Some("Collections.List.sumBy", [ f; xs ]) when numeric e.ty && pureLambda f 1 ->
        consume false xs true (fun src st -> foldOver src st (zeroOf e.ty) (fun a x -> mk (CBin("+", a, beta f [ x ])) e.ty))
      | Some("Collections.List.length", [ xs ]) ->
        consume false xs true (fun src st -> foldOver src st (mk (CInt(i64 0)) tInt) (fun a _ -> mk (CBin("+", a, mk (CInt(i64 1)) tInt)) tInt))
      // s is now evaluated after n
      | Some(fn, [ f; s; xs ]) when (fn = "Collections.List.fold" || fn = "Collections.Array.fold") && pureLambda f 2 && isPure s ->
        consume (String.contains "Array" fn) xs true (fun src st -> foldOver src st s (fun a x -> beta f [ a; x ]))
      | Some(fn, [ f; xs ]) when fn = "Collections.List.iter" || fn = "Collections.Array.iter" ->
        // the function is evaluated first, as the call would; a lambda is applied in place
        let isArray = String.contains "Array" fn
        let pureF = pureLambda f 1
        let body (src: Source) (st: list<Stage>) =
          match lambdaBody f 1 with
          | Some _ -> foldOver src st (mk CUnit tUnit) (fun _ x -> beta f [ x ])
          | None ->
            let fv = fresh "f"
            let applied (x: CExpr) = mk (CApp(mk (CLocal fv) f.ty, [ x ])) tUnit
            mk (CLet(fv, f, foldOver src st (mk CUnit tUnit) (fun _ x -> applied x))) tUnit
        consume isArray xs pureF body
      | Some(fn, [ g; _ ]) when (fn = "Collections.List.map" || fn = "Collections.List.filter") && pureLambda g 1 ->
        // a pipeline of several stages building a list
        let (src, stages) = chain false e []
        let worth =
          match src with
          | Init _ -> true
          | _ -> List.length stages >= 2
        if worth then Some(listOf src stages e.ty) else None
      | Some("Collections.Array.map", [ g; _ ]) when pureLambda g 1 ->
        // maps building an array
        let (src, stages) = chain true e []
        let isMap (s: Stage) =
          match s with
          | MapS _ -> true
          | FilterS _ -> false
        let maps = List.forall isMap stages
        let worth =
          match src with
          | Init _ -> true
          | _ -> List.length stages >= 2
        if maps && worth then Some(arrayOf src stages e.ty) else None
      | _ -> None
    match fused with
    | Some f -> { f with k = mapChildren ex f.k }
    | None -> { e with k = mapChildren ex e.k }
  let one (f: MFun) =
    // per function, as Mono's names
    count.Value <- 0
    { f with body = ex f.body }
  List.map one funs
