/// Closure conversion and lambda lifting: every lambda and local function becomes a top-level
/// function whose leading parameters are its captured variables. Saturated calls to known
/// functions become direct calls; anything else builds or applies a closure.
open Types.Ty
open Core.Ir
open Core.Program

// a local function lifted out: its top-level name, its captures, how many parameters it takes
type private LocalFun = { lname: string; caps: list<string * Ty>; arity: int }

let rec private resultAfter (n: int) (t: Ty) : Ty =
  match (n, t) with
  | (0, x) -> x
  | (_, TFun(_, r, _)) -> resultAfter (n - 1) r
  | _ -> panic "resultAfter: not a function type"

// one function's conversion: its lifted lambdas, then it (arities: the program's functions')
let private liftOne (arities: Map<string, int>) (external: share<string -> option<int>>) (wrapped: bool) (f0: MFun) : list<MFun> =
  let arity (g: string) : int =
    match Map.tryFind g arities with
    | Some n -> n
    | None ->
      match external g with
      | Some n -> n
      | None -> panic $"Lift: unknown function {g}"
  // for the function being converted: what it lifts out, its file and line, and its lambdas'
  // numbers (so its code doesn't depend on other functions')
  let out = ref Buffer.empty
  let source = ref ("", 0)
  let count = ref 0
  /// Free value variables, with references to local functions replaced by their captures.
  let captures (lfuns: Map<string, LocalFun>) (e: CExpr) (exclude: Set<string>) : list<string * Ty> =
    let bound = Set.ofList (binders e)
    let expand (r: string * Ty) =
      match Map.tryFind (fst r) lfuns with
      | Some lf -> lf.caps
      | None -> [ r ]
    let kept = List.filter (fun (x, _) -> not (Set.contains x bound || Set.contains x exclude)) (List.collect expand (refs e))
    List.fold (fun (acc: list<string * Ty>) (c: string * Ty) -> if List.exists (fun (y, _) -> y = fst c) acc then acc else List.append acc [ c ]) [] kept
  let capExprs (caps: list<string * Ty>) = List.map (fun (x, t) -> mk (CLocal x) t) caps
  let applyChain (f: CExpr) (args: list<CExpr>) = if List.isEmpty args then f else mk (CApplyClo(f, args)) (resultAfter (List.length args) f.ty)
  let lifted (name: string) (pars: list<string * Ty>) (body: CExpr) : MFun =
    { name = name; pars = pars; ret = body.ty; row = rowEmpty; body = body; file = fst source.Value; line = snd source.Value }
  /// A closure of top-level function g holding args (owner's): of g itself, or of a function of
  /// owner's that calls g.
  let closureOf (owner: string) (g: string) (fty: Ty) (args: list<CExpr>) : CExpr =
    if not wrapped then
      mk (CMkClosure(g, args)) (resultAfter (List.length args) fty)
    else
      count.Value <- count.Value + 1
      let w = $"{owner}$call{count.Value}"
      let rec split (n: int) (t: Ty) : list<Ty> * Ty =
        if n = 0 then
          ([], t)
        else
          match t with
          | TFun(a, r, _) ->
            let (ps, res) = split (n - 1) r
            (a :: ps, res)
          | _ -> panic "closureOf"
      let (ptys, res) = split (arity g) fty
      let ps = List.mapi (fun i t -> ($"$w{i}", t)) ptys
      let body = mk (CCallDirect(g, List.map (fun (x, t) -> mk (CLocal x) t) ps)) res
      Buffer.push (lifted w ps body) out.Value
      mk (CMkClosure(w, args)) (resultAfter (List.length args) fty)
  /// A call of f with its first parameters pre (captures) and these arguments: direct when they're
  /// enough, else a closure (topLevel: f is a top-level function, see closureOf).
  let direct (owner: string) (topLevel: bool) (f: string) (pre: list<CExpr>) (n: int) (fty: Ty) (args: list<CExpr>) : CExpr =
    if List.length args >= n then
      applyChain (mk (CCallDirect(f, List.append pre (List.take n args))) (resultAfter n fty)) (List.skip n args)
    else if topLevel then
      closureOf owner f fty args
    else
      mk (CMkClosure(f, List.append pre args)) (resultAfter (List.length args) fty)
  let rec conv (lfuns: Map<string, LocalFun>) (owner: string) (e: CExpr) : CExpr =
    let cv (x: CExpr) = conv lfuns owner x
    match e.k with
    | CLocal x when Map.containsKey x lfuns ->
      let lf = Map.find x lfuns
      mk (CMkClosure(lf.lname, capExprs lf.caps)) e.ty
    | CGlobal(g, _) -> closureOf owner g e.ty []
    | CApp(h, args0) ->
      let args = List.map cv args0
      match h.k with
      | CGlobal(g, _) -> direct owner true g [] (arity g) h.ty args
      | CLocal x when Map.containsKey x lfuns ->
        let lf = Map.find x lfuns
        direct owner false lf.lname (capExprs lf.caps) lf.arity h.ty args
      | _ -> applyChain (cv h) args
    | CLam(ps, body) ->
      let caps = captures lfuns e Set.empty
      count.Value <- count.Value + 1
      let lname = $"{owner}$lam{count.Value}"
      lift lfuns lname caps ps body
      mk (CMkClosure(lname, capExprs caps)) e.ty
    | CLetFun(g, _, ps, body, rest) ->
      let caps = captures lfuns body (Set.ofList (g :: List.map fst ps))
      let lf = { lname = owner + "$" + g; caps = caps; arity = List.length ps }
      let lfuns2 = Map.add g lf lfuns
      lift lfuns2 lf.lname caps ps body
      conv lfuns2 owner rest
    | CLetRec(fs, rest) ->
      // functions that call each other: each takes every capture of the group, so a call between
      // them passes the captures along
      let names = Set.ofList (List.map (fun (g, _, _) -> g) fs)
      let all = List.collect (fun (_, ps, body) -> captures lfuns body (Set.union names (Set.ofList (List.map fst ps)))) fs
      let caps = List.fold (fun (acc: list<string * Ty>) (c: string * Ty) -> if List.exists (fun (y, _) -> y = fst c) acc then acc else List.append acc [ c ]) [] all
      let lfuns2 = List.fold (fun (m: Map<string, LocalFun>) (g, ps, _) -> Map.add g { lname = owner + "$" + g; caps = caps; arity = List.length ps } m) lfuns fs
      for (g, ps, body) in fs do
        lift lfuns2 (Map.find g lfuns2).lname caps ps body
      conv lfuns2 owner rest
    | k -> mk (mapChildren cv k) e.ty
  and lift (lfuns: Map<string, LocalFun>) (lname: string) (caps: list<string * Ty>) (ps: list<string * Ty>) (body0: CExpr) =
    let body = conv lfuns lname body0
    Buffer.push (lifted lname (List.append caps ps) body) out.Value
  // a mutable variable a lambda refers to becomes a cell for its whole scope, which the closure
  // holds: a for loop's body over an impl whose forEach wasn't inlined (a recursive one), the one
  // lambda that may assign its function's variables (0017)
  let rec mentions (x: string) (e: CExpr) : bool =
    match e.k with
    | CLocal y
    | CAssign(y, _)
    | CArraySet(y, _, _) when y = x -> true
    | k -> List.exists (mentions x) (children k)
  let rec lambdaMentions (x: string) (e: CExpr) : bool =
    match e.k with
    | CLam(_, b) -> mentions x b
    | k -> List.exists (lambdaMentions x) (children k)
  let rec cells (e: CExpr) : CExpr =
    match e.k with
    | CLetMut(x, v0, body) ->
      if lambdaMentions x body then
        let v = cells v0
        let cell = TCon("ref", [ v.ty ])
        let rec through (w: CExpr) : CExpr =
          match w.k with
          | CLocal y when y = x -> mk (CPrim("ref.get", [ mk (CLocal x) cell ])) w.ty
          | CAssign(y, u) when y = x -> mk (CPrim("ref.set", [ mk (CLocal x) cell; through u ])) w.ty
          | CArraySet(y, i, u) when y = x ->
            // the cell's array with the element changed (copied when shared)
            let at = TCon("array", [ u.ty ])
            let c = mk (CLocal x) cell
            let changed = mk (CPrim("array.update", [ mk (CPrim("ref.get", [ c ])) at; through i; through u ])) at
            mk (CPrim("ref.set", [ c; changed ])) w.ty
          | k -> mk (mapChildren through k) w.ty
        mk (CLet(x, mk (CPrim("ref", [ v ])) cell, through (cells body))) e.ty
      else
        mk (mapChildren cells e.k) e.ty
    | k -> mk (mapChildren cells k) e.ty
  // each function on its own; its lifted lambdas come before it, as they're made
  let one (f: MFun) : list<MFun> =
    // lifted lambdas are debugged as part of their function
    source.Value <- (f.file, f.line)
    count.Value <- 0
    let mine = Buffer.empty
    out.Value <- mine
    let body = conv Map.empty f.name (cells f.body)
    Buffer.push { f with body = body } mine
    Array.toList (Buffer.toArray mine)
  one f0

/// external: the arity of a function another module has the code of. wrapped: a closure of a
/// top-level function goes through a function of its maker's own, which calls it, so a function
/// borrows what it may whatever makes closures of it (a module's code is then the same whichever
/// modules are made with it).
let runWith (external: share<string -> option<int>>) (wrapped: bool) (funs: list<MFun>) : list<MFun> =
  let arities = Map.ofList (List.map (fun (f: MFun) -> (f.name, List.length f.pars)) funs)
  // each function on the pool (decision 76)
  List.concat (Array.toList (Array.Parallel.map (fun (f: MFun) -> liftOne arities external wrapped f) (Array.ofList funs)))

let run (funs: list<MFun>) : list<MFun> = runWith (fun _ -> None) false funs
