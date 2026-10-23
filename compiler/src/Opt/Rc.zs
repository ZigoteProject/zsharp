/// Perceus reference counting (Reinking, Xie, de Moura, Leijen; PLDI 2021), base algorithm:
/// precise ownership. Every owned variable is consumed exactly once on every path: moved into its
/// last use, dup'ed before earlier uses, and dropped as soon as it is dead (at the start of a
/// branch that does not use it). Function arguments are owned by the callee; a closure being
/// applied is borrowed. Pattern variables borrow from the scrutinee and are dup'ed when used.
open Types.Ty
open Core.Ir
open Core.Program

// the variable a value is, or a field (of a field…) of: what a read through it borrows
let rec private rootLocal (e: CExpr) : option<string> =
  match e.k with
  | CLocal x -> Some x
  | CField(r, _) -> rootLocal r
  | _ -> None

// whether e is the variable x
let private isLocalNamed (x: string) (e: CExpr) : bool =
  match e.k with
  | CLocal y -> y = x
  | _ -> false

// the reads that leave a parameter the caller's (borrowing)
let private reads : Set<string> = Set.ofList [ "array.get"; "Array.length"; "String.length"; "String.byte"; "fixed.get"; "fixed.length"; "ref.get"; "ref.set" ]

// the reads that borrow the array (or string) they read from, a variable or a field of one
let private lends : Set<string> = Set.ofList [ "array.get"; "Array.length"; "String.length"; "String.byte"; "vec.load"; "fixed.get"; "fixed.length" ]

/// A function's body with the parameters of its join points that are its own parameters gone:
/// where every jump to a join point passes the same parameter of the function from `keep` (one it
/// borrows) in a place, the join point's body uses that parameter itself, which outlives it, so no
/// jump dups it to pass it.
let private elideAliases (keep: string -> bool) (body: CExpr) : CExpr =
  let passed = ref Map.empty
  let kept (a: CExpr) : option<string> =
    match a.k with
    | CLocal x -> if keep x then Some x else None
    | _ -> None
  let rec scan (e: CExpr) =
    match e.k with
    | CJump(j, args) ->
      let here = List.map kept args
      match Map.tryFind j passed.Value with
      | Some before -> passed.Value <- Map.add j (List.map2 (fun (a: option<string>) b -> if a = b then a else None) before here) passed.Value
      | None -> passed.Value <- Map.add j here passed.Value
    | _ -> ()
    List.iter scan (children e.k)
  scan body
  let elided (j: string) : bool =
    match Map.tryFind j passed.Value with
    | Some slots -> List.exists Option.isSome slots
    | None -> false
  if not (List.exists elided (Map.keys passed.Value)) then
    body
  else
    let rec subst (m: Map<string, string>) (e: CExpr) : CExpr =
      match e.k with
      | CLocal x when Map.containsKey x m -> { e with k = CLocal(Map.find x m) }
      | k -> { e with k = mapChildren (subst m) k }
    let rec go (e: CExpr) : CExpr =
      match e.k with
      | CJoin(j, ps, b, rest) when elided j ->
        let slots = List.zip ps (Map.find j passed.Value)
        let m = Map.ofList (List.choose (fun ((q, _), s) -> Option.map (fun x -> (q, x)) s) slots)
        let ps2 = List.map fst (List.filter (fun (_, s) -> Option.isNone s) slots)
        { e with k = CJoin(j, ps2, go (subst m b), go rest) }
      | CJump(j, args) when elided j ->
        let slots = List.zip args (Map.find j passed.Value)
        { e with k = CJump(j, List.map (fun (a, _) -> go a) (List.filter (fun (_, s) -> Option.isNone s) slots)) }
      | k -> { e with k = mapChildren go k }
    go body

/// Borrowed parameters (Perceus borrowing), each function's indices: a heap parameter the function
/// only applies, reads (a.[i], lengths, a record's fields) or passes on to a borrowed parameter is
/// borrowed. The caller keeps ownership and the callee neither dups nor drops it, so a closure or
/// array threaded through a loop costs no reference counting. Only for functions called directly
/// (not closures, which are called through code pointers, nor the entries). For the whole
/// program, since a caller's code depends on its callees'. external: what another module's code
/// borrows (its functions aren't in funs).
let borrowingWith (types: Map<string, TypeInfo>) (entries: Set<string>) (external: string -> option<Set<int>>) (funs: list<MFun>) : Map<string, Set<int>> =
  let v = Types.Vars.make ()
  let heap (t: Ty) = Types.Repr.needsRc v types t
  let asValues = ref entries
  let rec values (e: CExpr) =
    match e.k with
    | CMkClosure(n, _) -> asValues.Value <- Set.add n asValues.Value
    | CPrim(op, _) ->
      // in a vtable
      if String.startsWith "fn:" op then
        asValues.Value <- Set.add (String.sub op 3 (String.length op - 3)) asValues.Value
    | _ -> ()
    List.iter values (children e.k)
  for f in funs do
    values f.body
  let borrowedOf = ref Map.empty
  for f in funs do
    if not (Set.contains f.name asValues.Value) then
      let heapPars = List.filter (fun (_, (_, t)) -> heap t) (List.indexed f.pars)
      borrowedOf.Value <- Map.add f.name (Set.ofList (List.map fst heapPars)) borrowedOf.Value
  let fnOf = Map.ofList (List.map (fun (f: MFun) -> (f.name, f)) funs)
  let changed = ref true
  // each round from the sets of the round before: they only shrink, so the rounds end at the same
  // sets in any order
  while changed.Value do
    let fewer (entry: string * Set<int>) : option<string * Set<int>> =
      // the parameters of the set the body uses in other ways, in one walk
      let (name, set) = entry
      let f = Map.find name fnOf
      let index = Map.ofList (List.map (fun i -> (fst (List.item i f.pars), i)) (Set.toList set))
      let bad = ref Set.empty
      let rec walk (e: CExpr) =
        match e.k with
        | CLocal x when Map.containsKey x index -> bad.Value <- Set.add (Map.find x index) bad.Value
        // a field read dups the field: the record itself stays the caller's
        | CField({ k = CLocal x }, _) when Map.containsKey x index -> ()
        | CApplyClo({ k = CLocal x }, args) when Map.containsKey x index -> List.iter walk args
        | CPrim(op, { k = CLocal x } :: rest) when Set.contains op reads && Map.containsKey x index -> List.iter walk rest
        | CCallDirect(g, args) ->
          let one (j: int) (a: CExpr) =
            match a.k with
            | CLocal x when Map.containsKey x index ->
              let once = List.length (List.filter (isLocalNamed x) args) = 1
              let bs =
                match Map.tryFind g borrowedOf.Value with
                | Some bs -> Some bs
                | None -> if Map.containsKey g fnOf then None else external g
              match bs with
              | Some bs2 when once && Set.contains j bs2 -> ()
              | _ -> bad.Value <- Set.add (Map.find x index) bad.Value
            | _ -> walk a
          List.iteri one args
        | CAssign(x, _)
        | CArraySet(x, _, _) when Map.containsKey x index ->
          bad.Value <- Set.add (Map.find x index) bad.Value
          List.iter walk (children e.k)
        | k -> List.iter walk (children k)
      if not (Set.isEmpty set) then
        walk (elideAliases (fun x -> Map.containsKey x index) f.body)
      if Set.isEmpty bad.Value then None else Some(name, Set.difference set bad.Value)
    let updates = List.choose fewer (Map.toList borrowedOf.Value)
    changed.Value <- not (List.isEmpty updates)
    for (name, set) in updates do
      borrowedOf.Value <- Map.add name set borrowedOf.Value
  borrowedOf.Value

let borrowing (types: Map<string, TypeInfo>) (entries: Set<string>) (funs: list<MFun>) : Map<string, Set<int>> = borrowingWith types entries (fun _ -> None) funs

let private isString (e: CExpr) : bool =
  match e.ty with
  | TCon("string", []) -> true
  | _ -> false

let private isConcat (e: CExpr) : bool =
  match e.k with
  | CBin(op, a, _) -> (op = "+" || op = "wrap+") && isString a
  | _ -> false

// a string built with +: its pieces, in order
let rec private flatten (e: CExpr) : list<CExpr> =
  match e.k with
  | CBin(_, a, b) when isConcat e -> List.append (flatten a) (flatten b)
  | _ -> [ e ]

// whether a path of e ends in a jump to a join point
let rec private jumps (e: CExpr) : bool =
  match e.k with
  | CJump _ -> true
  | CLet(_, _, b)
  | CLetMut(_, _, b)
  | CSeq(_, b)
  | CLine(_, b)
  | CDup(_, _, b)
  | CDrop(_, _, b)
  | CDropFields(_, _, _, _, _, b)
  | CFreeToken(_, b)
  | CJoin(_, _, _, b) -> jumps b
  | CIf(_, t, f) -> jumps t || jumps f
  | CMatch(_, cases) -> List.exists (fun (_, _, b) -> jumps b) cases
  | _ -> false

// how x is used first on the paths of e: 0, not at all; 1, read first; 2, assigned first
let rec private firstUse (x: string) (e: CExpr) : int =
  let inOrder (es: list<CExpr>) = List.fold (fun u c -> if u <> 0 then u else firstUse x c) 0 es
  // 1: a path that reads it, or that might not reassign it
  let join (us: list<int>) = if List.forall (fun u -> u = 2) us then 2 else if List.forall (fun u -> u = 0) us then 0 else 1
  match e.k with
  | CLocal y when y = x -> 1
  | CAssign(y, w) when y = x -> if firstUse x w = 1 then 1 else 2
  | CIf(c, t, f) ->
    match firstUse x c with
    | 0 -> join [ firstUse x t; firstUse x f ]
    | u -> u
  | CMatch(sc, cases) ->
    match firstUse x sc with
    | 0 -> join (List.map (fun (_, g, b) -> inOrder (List.append (Option.toList g) [ b ])) cases)
    | u -> u
  | CWhile _
  | CFor _ -> if Set.contains x (freeVars e) || List.exists (fun (y, _) -> y = x) (refs e) then 1 else 0
  | CLam _ -> 0
  | k -> inOrder (children k)

// the first assignment to x on every path, marked as taking a moved-out variable
let rec private markAssign (x: string) (e: CExpr) : CExpr =
  match e.k with
  | CAssign(y, w) when y = x -> mk (CAssign(x, mk (CPrim("slot.moved", [ w ])) w.ty)) e.ty
  | CIf(c, t, f) -> mk (CIf(c, markAssign x t, markAssign x f)) e.ty
  | CMatch(sc, cases) -> mk (CMatch(sc, List.map (fun (p, g, b) -> (p, g, markAssign x b)) cases)) e.ty
  | CSeq(a, b) -> if firstUse x a = 2 then mk (CSeq(markAssign x a, b)) e.ty else mk (CSeq(a, markAssign x b)) e.ty
  | CLet(y, w, b) -> if firstUse x w = 2 then mk (CLet(y, markAssign x w, b)) e.ty else mk (CLet(y, w, markAssign x b)) e.ty
  | CLine(l, a) -> mk (CLine(l, markAssign x a)) e.ty
  | _ -> e

/// Reference counting for funs, with the program's borrowed parameters (borrowing).
let lower (types: Map<string, TypeInfo>) (borrowedParams: Map<string, Set<int>>) (funs: list<MFun>) : list<MFun> =
  let v = Types.Vars.make ()
  let heap (t: Ty) = Types.Repr.needsRc v types t
  // temporaries numbered per function: a function's code doesn't depend on the others'
  let count = ref 0
  let next () =
    count.Value <- count.Value + 1
    count.Value
  let tmp () =
    let n = next ()
    $"$rc{n}"
  /// print/println of a string built with + (an interpolation, usually) prints the pieces instead
  /// of joining them: no concatenation, no allocation. Every piece is evaluated first, in order,
  /// as before, so output and panics happen exactly as they did.
  let rec printPieces (e: CExpr) : CExpr =
    match e.k with
    | CPrim(op, [ arg ]) when (op = "print" || op = "println") && isConcat arg ->
      let temps = List.map (fun (p: CExpr) -> (tmp (), printPieces p)) (flatten arg)
      let last = List.length temps - 1
      let pieces = List.mapi (fun i (t, p) -> mk (CPrim((if i = last then op else "print"), [ mk (CLocal t) p.ty ])) tUnit) temps
      let prints = List.reduce (fun a b -> mk (CSeq(a, b)) tUnit) pieces
      List.fold (fun (acc: CExpr) (t, p) -> mk (CLet(t, p, acc)) tUnit) prints (List.rev temps)
    | k -> mk (mapChildren printPieces k) e.ty
  // ---- re-matching: in `match x with C (a, b) -> if c then f a else x`, x stays alive for the
  // branch that returns it, so its drop can't be specialized for the whole case. Each branch where
  // x dies matches it again (a known constructor), so that branch takes the cell apart itself: the
  // fields move out without a dup, and the cell can be reused.
  let rematch (body: CExpr) : CExpr =
    let rec renameVars (m: Map<string, string>) (e: CExpr) : CExpr =
      match e.k with
      | CLocal x when Map.containsKey x m -> { e with k = CLocal(Map.find x m) }
      | k -> { e with k = mapChildren (renameVars m) k }
    let single (fps: list<CPat>) =
      let plain (fp: CPat) =
        match fp with
        | CPVar _
        | CPWild -> true
        | _ -> false
      List.forall plain fps
    let rec go (e0: CExpr) : CExpr =
      let e = { e0 with k = mapChildren go e0.k }
      match e.k with
      | CMatch(s, cases) ->
        match s.k with
        | CLocal x ->
          if heap s.ty && not (Types.Repr.plainUnion v types s.ty) then
            let one (c: CPat * option<CExpr> * CExpr) =
              let (p, g, b) = c
              match p with
              | CPCtor(u, tag, fps) when not (List.isEmpty fps) && single fps && Set.contains x (freeVars b) -> (p, g, push s x u tag fps b)
              | _ -> (p, g, b)
            { e with k = CMatch(s, List.map one cases) }
          else
            e
        | _ -> e
      | _ -> e
    // the branches of b where x (the scrutinee s) dies match it again; where x is used, b is left
    // as it is
    and push (s: CExpr) (x: string) (u: string) (tag: int) (fps: list<CPat>) (b: CExpr) : CExpr =
      let uses (y: CExpr) = Set.contains x (freeVars y)
      let branch (br: CExpr) = if uses br then push s x u tag fps br else again s u tag fps br
      match b.k with
      | CIf(c, t, f) when not (uses c) -> { b with k = CIf(c, branch t, branch f) }
      | CLet(w, y, rest) when not (uses y) -> { b with k = CLet(w, y, push s x u tag fps rest) }
      | CLine(l, inner) -> { b with k = CLine(l, push s x u tag fps inner) }
      | CMatch(s2, cases) when not (uses s2) && List.forall (fun (_, g, _) -> not (Option.exists uses g)) cases ->
        { b with k = CMatch(s2, List.map (fun (p, g, br) -> (p, g, branch br)) cases) }
      | _ -> b
    // match s again, with fresh names for the fields br uses
    and again (s: CExpr) (u: string) (tag: int) (fps: list<CPat>) (br: CExpr) : CExpr =
      let fv = freeVars br
      let rename (fp: CPat) : CPat * option<string * string> =
        match fp with
        | CPVar(w, t) when Set.contains w fv ->
          let n = next ()
          let w2 = $"{w}.r{n}"
          (CPVar(w2, t), Some(w, w2))
        | _ -> (CPWild, None)
      let (fps2, pairs) = List.unzip (List.map rename fps)
      let m = Map.ofList (List.choose (fun p -> p) pairs)
      mk (CMatch(s, [ (CPCtor(u, tag, fps2), None, renameVars m br) ])) br.ty
    go body
  let rcFun (f0: MFun) : MFun =
    count.Value <- 0
    let mine =
      match Map.tryFind f0.name borrowedParams with
      | Some bs -> bs
      | None -> Set.empty
    let lent = Set.ofList (List.map (fun (_, (x, _)) -> x) (List.filter (fun (i, _) -> Set.contains i mine) (List.indexed f0.pars)))
    let f = { f0 with body = elideAliases (fun x -> Set.contains x lent) (rematch (printPieces f0.body)) }
    // the free variables of the nodes rc meets, numbered below, remembered (each node's is asked
    // for again and again)
    let freeVars = cachedFreeVars ()
    // every variable's type, by unique name
    let vtypes = ref Map.empty
    let setType (x: string) (t: Ty) = vtypes.Value <- Map.add x t vtypes.Value
    let typeOf (x: string) : Ty = Map.find x vtypes.Value
    for (x, t) in f.pars do
      setType x t
    let rec collect (e: CExpr) =
      match e.k with
      | CLet(x, w, _)
      | CLetMut(x, w, _) -> setType x w.ty
      | CFor(x, a, _, _, _) -> setType x a.ty
      | CJoin(_, ps, _, _) ->
        for (x, t) in ps do
          setType x t
      | CMatch(_, cases) ->
        for (p, _, _) in cases do
          for (x, t) in patVars p do
            setType x t
      | _ -> ()
      List.iter collect (children e.k)
    collect f.body
    let rec mutsIn (e: CExpr) : list<string> =
      let own =
        match e.k with
        | CLetMut(x, _, _) -> [ x ]
        | _ -> []
      List.append own (List.collect mutsIn (children e.k))
    let mutables = Set.ofList (mutsIn f.body)
    let heapVar (x: string) = heap (typeOf x)
    // a task's state machine (task.suspend, task.abandon): what's held across a wait, which a
    // cancelled task drops when its coroutine is destroyed there. held: the owned variables the
    // code after the current subexpression consumes; muts: the heap `mutable`s in scope
    let held = ref Set.empty
    let muts = ref Set.empty
    let holding (extra: Set<string>) (g: unit -> CExpr) : CExpr =
      let saved = held.Value
      held.Value <- Set.union saved extra
      let r = g ()
      held.Value <- saved
      r
    // the layout of the cell a constructor builds (or a matched case is): with a tag?, and the
    // field types; None when the case isn't a cell (no fields, or a niche)
    let layoutOf (t: Ty) (tag: int) (fields: list<Ty>) : option<bool * list<Ty>> =
      Option.map (fun (tagged, _) -> (tagged, fields)) (Types.Repr.cellShape v types t tag)
    let fieldTypes (t: Ty) (tag: int) : list<Ty> =
      match t with
      | TCon(u, args) ->
        match (Map.find u types).def with
        | UnionDef cs -> List.map (Types.Norm.substGen v args) (snd (List.item tag cs))
        | RecordDef _ -> []
      | _ -> []
    // join points whose body builds a cell: their reuse-token parameter and the cell's layout
    let joinTok = ref Map.empty
    let tokenTy = tcon "cptr"
    // rewrites one constructor with the given field layout, on every path of e that ends in one,
    // to build in the token's cell; paths without one free the token. None: no site
    let rec place (tok: string) (layout: bool * list<Ty>) (e: CExpr) : option<CExpr> =
      let re (k: CKind) = Some(mk k e.ty)
      let free (b: CExpr) = mk (CFreeToken(tok, b)) b.ty
      match e.k with
      | CCtor(u, tag, args) when heap e.ty && layoutOf e.ty tag (List.map (fun (a: CExpr) -> a.ty) args) = Some layout -> re (CCtorAt(tok, u, tag, args))
      // runs repeatedly
      | CWhile _
      | CFor _ -> None
      | CJump(j, args) ->
        // a jump to a join point that builds a cell alike passes the token on, unless the jump
        // passes another token already
        let freeNow =
          match List.tryLast args with
          | Some { k = CPrim("token.null", _) } -> true
          | _ -> false
        match Map.tryFind j joinTok.Value with
        | Some(_, l) when l = layout && freeNow -> re (CJump(j, List.append (List.take (List.length args - 1) args) [ mk (CLocal tok) tokenTy ]))
        | _ -> None
      // the token isn't in the body's scope
      | CJoin(j, ps, body, rest) -> Option.map (fun r -> mk (CJoin(j, ps, body, r)) e.ty) (place tok layout rest)
      | CIf(c, t, f) ->
        match (place tok layout t, place tok layout f) with
        | (None, None) -> None
        | (t2, f2) -> re (CIf(c, Option.defaultValue (free t) t2, Option.defaultValue (free f) f2))
      | CMatch(s, cases) ->
        let placed = List.map (fun (p, g, b) -> (p, g, b, place tok layout b)) cases
        if List.forall (fun (_, _, _, b) -> Option.isNone b) placed then
          None
        else
          re (CMatch(s, List.map (fun (p, g, b, b2) -> (p, g, Option.defaultValue (free b) b2)) placed))
      | k ->
        // every other node evaluates each child exactly once: use the first child that can
        let found = ref false
        let firstPlaced (c: CExpr) : CExpr =
          if found.Value then
            c
          else
            match place tok layout c with
            | Some c2 ->
              found.Value <- true
              c2
            | None -> c
        let k2 = mapChildren firstPlaced k
        if found.Value then re k2 else None
    let drops (vars: Set<string>) (e: CExpr) : CExpr = List.fold (fun (acc: CExpr) x -> mk (CDrop(x, typeOf x, acc)) acc.ty) e (Set.toList vars)
    let dups (vars: Set<string>) (e: CExpr) : CExpr = List.fold (fun (acc: CExpr) x -> mk (CDup(x, typeOf x, acc)) acc.ty) e (Set.toList vars)
    // ---- borrowed projections (as in Lean 4's RC): the fields a match takes from a value that
    // stays alive past it are borrowed from it, not dup'ed, and dup'ed only where something takes
    // them. The value then counts as used wherever its fields are, so it's consumed only after
    // their last use.
    let parentOf = ref Map.empty
    // the variables e needs alive: its free variables, and the values their borrowed fields come
    // from
    let live (e: CExpr) : Set<string> =
      let rec up (acc: Set<string>) (x: string) : Set<string> =
        match Map.tryFind x parentOf.Value with
        | Some p -> if Set.contains p acc then acc else up (Set.add p acc) p
        | None -> acc
      let fv = freeVars e
      if Map.isEmpty parentOf.Value then fv else List.fold up fv (Set.toList fv)
    let isVar (e: CExpr) : bool =
      match e.k with
      | CLocal x -> not (Set.contains x mutables)
      | _ -> false
    let lendsAny (n: string) : bool =
      match Map.tryFind n borrowedParams with
      | Some bs -> not (Set.isEmpty bs)
      | None -> false
    // e must consume every variable in `owned`; `borrowed` variables stay alive throughout
    let rec rc (owned: Set<string>) (borrowed: Set<string>) (e: CExpr) : CExpr =
      let fv = freeVars e
      let lv = live e
      let dead = Set.difference owned lv
      // what e reaches only through borrowed fields: borrowed by e, dropped after it
      let viaFields = Set.difference (Set.intersect owned lv) fv
      let e2 = rcIn (Set.intersect owned fv) (Set.union borrowed viaFields) e
      // the drops go where e ends: after its value, or before a jump (which doesn't come back),
      // after the jump's arguments
      let rec after (x: CExpr) : CExpr =
        let re (k: CKind) = { x with k = k }
        match x.k with
        | CJump(j, args) ->
          let ts = List.map (fun (a: CExpr) -> (a, tmp ())) args
          for (a, t) in ts do
            setType t a.ty
          let jump = mk (CJump(j, List.map (fun (a, t) -> mk (CLocal t) a.ty) ts)) x.ty
          List.fold (fun (acc: CExpr) (a, t) -> mk (CLet(t, a, acc)) acc.ty) (drops viaFields jump) (List.rev ts)
        | _ when not (jumps x) ->
          let r = tmp ()
          setType r x.ty
          mk (CLet(r, x, drops viaFields (mk (CLocal r) x.ty))) x.ty
        | CLet(y, w, b) -> re (CLet(y, w, after b))
        | CLetMut(y, w, b) -> re (CLetMut(y, w, after b))
        | CSeq(a, b) -> re (CSeq(a, after b))
        | CLine(l, b) -> re (CLine(l, after b))
        | CIf(c, t, f) -> re (CIf(c, after t, after f))
        | CMatch(s, cases) -> re (CMatch(s, List.map (fun (p, g, b) -> (p, g, after b)) cases))
        | CDup(y, t, b) -> re (CDup(y, t, after b))
        | CDrop(y, t, b) -> re (CDrop(y, t, after b))
        | CDropFields(y, t, tag, keep, tok, b) -> re (CDropFields(y, t, tag, keep, tok, after b))
        | CFreeToken(t, b) -> re (CFreeToken(t, after b))
        // the jumps to it dropped them
        | CJoin(j, ps, body, rest) -> re (CJoin(j, ps, body, after rest))
        | _ -> panic "Rc: unreachable"
      let e3 = if Set.isEmpty viaFields then e2 else after e2
      drops dead e3
    // ordered subexpressions: each owned variable goes to the last one that uses it
    and rcList (owned: Set<string>) (borrowed: Set<string>) (es: list<CExpr>) : list<CExpr> =
      let rec go (rest: list<CExpr>) (fvs: list<Set<string>>) : list<CExpr> =
        match (rest, fvs) with
        | (ei :: more, fi :: later0) ->
          let later = List.fold Set.union Set.empty later0
          let mine = Set.intersect owned fi
          let oi = Set.difference mine later
          let r = holding (Set.intersect owned later) (fun () -> rc oi (Set.union borrowed (Set.difference mine oi)) ei)
          r :: go more later0
        | _ -> []
      go es (List.map live es)
    // let-binds a non-variable subexpression so it can be inspected by name
    and viaTemp (owned: Set<string>) (borrowed: Set<string>) (sub: CExpr) (build: CExpr -> CExpr) : CExpr =
      let t = tmp ()
      setType t sub.ty
      let b = build (mk (CLocal t) sub.ty)
      rcIn owned borrowed (mk (CLet(t, sub, b)) b.ty)
    and rcIn (owned: Set<string>) (borrowed: Set<string>) (e: CExpr) : CExpr =
      let re (k: CKind) = mk k e.ty
      match e.k with
      | CPerform _
      | CHandle _ -> panic "Rc: an effect's node after Evidence"
      | CLocal x ->
        if Set.contains x owned then e else if heap e.ty then mk (CDup(x, e.ty, e)) e.ty else e
      | CInt _
      | CFloat _
      | CBool _
      | CStr _
      | CUnit -> e
      | CLine(l, a) -> re (CLine(l, rc owned borrowed a))
      | CJoin(j, ps, body, rest) ->
        // a join point's body owns its parameters, as a function's does; jumps pass them. A body
        // that builds a cell also takes a reuse token (null, or a cell the jump's path took
        // apart), so that cell can be built in after the jump; and it borrows the function's
        // borrowed parameters it uses, as the function does
        let mine = Set.ofList (List.filter heapVar (List.map fst ps))
        let body2 = rc mine lent body
        // the cell it builds, or the one a join point it jumps to builds
        let rec layoutIn (x: CExpr) : option<bool * list<Ty>> =
          match x.k with
          | CCtor(_, tag, args) when heap x.ty && Option.isSome (layoutOf x.ty tag []) -> layoutOf x.ty tag (List.map (fun (a: CExpr) -> a.ty) args)
          | CJump(j2, _) when Map.containsKey j2 joinTok.Value -> Some(snd (Map.find j2 joinTok.Value))
          | k -> List.tryPick layoutIn (children k)
        match layoutIn body2 with
        | Some l ->
          let tp = tmp ()
          setType tp tokenTy
          joinTok.Value <- Map.add j (tp, l) joinTok.Value
          let body3 =
            match place tp l body2 with
            | Some b -> b
            | None -> mk (CFreeToken(tp, body2)) body2.ty
          re (CJoin(j, List.append ps [ (tp, tokenTy) ], body3, rc owned borrowed rest))
        | None -> re (CJoin(j, ps, body2, rc owned borrowed rest))
      | CJump(j, args) ->
        let args2 = rcList owned borrowed args
        if Map.containsKey j joinTok.Value then re (CJump(j, List.append args2 [ mk (CPrim("token.null", [])) tokenTy ])) else re (CJump(j, args2))
      | CLet(x, w, body) ->
        let fb = live body
        let fvv = live w
        let ov = Set.difference (Set.intersect owned fvv) fb
        let w2 = holding (Set.difference owned ov) (fun () -> rc ov (Set.union borrowed (Set.difference (Set.intersect owned fvv) ov)) w)
        let ob0 = Set.difference owned ov
        let ob = if heap w.ty then Set.add x ob0 else ob0
        re (CLet(x, w2, rc ob borrowed body))
      | CLetMut(x, w, body) ->
        let fb = live body
        let fvv = live w
        let ov = Set.difference (Set.intersect owned fvv) fb
        let w2 = holding (Set.difference owned ov) (fun () -> rc ov (Set.union borrowed (Set.difference (Set.intersect owned fvv) ov)) w)
        let saved = muts.Value
        if heap w.ty then
          muts.Value <- Set.add x muts.Value
        let body2 = rc (Set.difference owned ov) borrowed body
        muts.Value <- saved
        re (CLetMut(x, w2, body2))
      | CSeq(a, b) ->
        if heap a.ty then
          let t = tmp ()
          setType t a.ty
          rcIn owned borrowed (re (CLet(t, a, b)))
        else
          match rcList owned borrowed [ a; b ] with
          | [ a2; b2 ] -> re (CSeq(a2, b2))
          | _ -> panic "Rc: unreachable"
      | CIf(c, t, f) ->
        let fc = live c
        let fr = Set.union (live t) (live f)
        let mine = Set.intersect owned fc
        let oc = Set.difference mine fr
        let c2 = rc oc (Set.union borrowed (Set.difference mine oc)) c
        let rest = Set.difference owned oc
        let t2 = rc rest borrowed t
        re (CIf(c2, t2, rc rest borrowed f))
      | CMatch(s, cases) when isVar s -> matchVar owned borrowed e s cases
      | CMatch(s, cases) ->
        match s.k with
        | CTuple xs when List.forall isVar xs -> matchTuple owned borrowed e xs s cases
        | _ -> viaTemp owned borrowed s (fun w -> re (CMatch(w, cases)))
      | CField(r, i) ->
        match r.k with
        | CLocal x when isVar r ->
          let f = tmp ()
          setType f e.ty
          let res0 = mk (CLocal f) e.ty
          let res1 = if Set.contains x owned then mk (CDrop(x, typeOf x, res0)) e.ty else res0
          let res2 = if heap e.ty then mk (CDup(f, e.ty, res1)) e.ty else res1
          re (CLet(f, e, res2))
        | _ -> viaTemp owned borrowed r (fun w -> re (CField(w, i)))
      | CApplyClo(fe, args) ->
        match fe.k with
        | CLocal x when isVar fe ->
          // the closure stays alive across the arguments and the call, then is released
          let args2 = rcList (Set.remove x owned) (Set.add x borrowed) args
          if Set.contains x owned then
            let r = tmp ()
            setType r e.ty
            re (CLet(r, re (CApplyClo(fe, args2)), mk (CDrop(x, typeOf x, mk (CLocal r) e.ty)) e.ty))
          else
            re (CApplyClo(fe, args2))
        | _ -> viaTemp owned borrowed fe (fun w -> re (CApplyClo(w, args)))
      | CWhile _
      | CFor _ ->
        // loop parts run repeatedly, so they only borrow; owned variables die after the loop
        let all = Set.union owned borrowed
        let loop = re (mapChildren (rc Set.empty all) e.k)
        mk (CSeq(loop, drops owned (mk CUnit tUnit))) tUnit
      | CAssign(x, w) when heapVar x -> assignHeap owned borrowed e x w
      // the variable's own reference, moved out
      | CPrim("slot.take", _) -> e
      | CGlobalVal _ when heap e.ty ->
        // a top-level value keeps its reference; a read takes one of its own
        let t = tmp ()
        setType t e.ty
        re (CLet(t, e, mk (CDup(t, e.ty, mk (CLocal t) e.ty)) e.ty))
      | CGlobalVal _ -> e
      | CPrim(op, a :: rest) when Set.contains op lends && rootLent a rest ->
        // reading an element or the length borrows the array (or string), a variable or a record
        // field of one: no dup before, no drop inside; if this was x's last use, x is dropped after
        let x = Option.get (rootLocal a)
        let rest2 = rcList (Set.remove x owned) (Set.add x borrowed) rest
        let read = re (CPrim(op + "#b", a :: rest2))
        if Set.contains x owned then
          let r = tmp ()
          setType r e.ty
          re (CLet(r, read, mk (CDrop(x, typeOf x, mk (CLocal r) e.ty)) e.ty))
        else
          read
      | CAssign(x, w) -> re (CAssign(x, rc owned borrowed w))
      | CArraySet(x, i, w) ->
        match rcList owned borrowed [ i; w ] with
        | [ i2; w2 ] -> re (CArraySet(x, i2, w2))
        | _ -> panic "Rc: unreachable"
      | CTuple xs -> re (CTuple(rcList owned borrowed xs))
      | CCtor(u, tag, xs) -> re (CCtor(u, tag, rcList owned borrowed xs))
      | CCallDirect(n, xs) when lendsAny n -> callLending owned borrowed e n xs
      | CCallDirect(n, xs) -> re (CCallDirect(n, rcList owned borrowed xs))
      | CExtern(n, xs) -> re (CExtern(n, rcList owned borrowed xs))
      | CPrim(n, xs) when n = "task.suspend" || n = "task.abandon" ->
        // a wait: what the task holds across it (dropped if it's cancelled there) goes with it,
        // after its arguments, as task.held (variables and mutables)
        let xs2 = rcList owned borrowed xs
        let vars = List.filter heapVar (Set.toList (Set.union held.Value muts.Value))
        let heldNode = mk (CPrim("task.held", List.map (fun w -> mk (CLocal w) (typeOf w)) vars)) e.ty
        re (CPrim(n, List.append xs2 [ heldNode ]))
      | CPrim(n, xs) -> re (CPrim(n, rcList owned borrowed xs))
      | CMkClosure(n, xs) -> re (CMkClosure(n, rcList owned borrowed xs))
      | CBin(op, a, b) ->
        match rcList owned borrowed [ a; b ] with
        | [ a2; b2 ] -> re (CBin(op, a2, b2))
        | _ -> panic "Rc: unreachable"
      | CNeg a -> re (CNeg(rc owned borrowed a))
      | CNot a -> re (CNot(rc owned borrowed a))
      | _ -> panic "Rc: unexpected node"
    // whether a read through a (a variable, or a field of one) can borrow it: the rest of the
    // read doesn't use the variable
    and rootLent (a: CExpr) (rest: list<CExpr>) : bool =
      match rootLocal a with
      | Some x -> not (List.exists (fun (r: CExpr) -> Set.contains x (live r)) rest)
      | None -> false
    and matchVar (owned: Set<string>) (borrowed: Set<string>) (e: CExpr) (s: CExpr) (cases: list<CPat * option<CExpr> * CExpr>) : CExpr =
      let x = Option.get (rootLocal s)
      let xOwned = Set.contains x owned
      let one (c: CPat * option<CExpr> * CExpr) =
        let (p, g, body) = c
        let pvars = Set.ofList (List.filter heapVar (List.map fst (patVars p)))
        let all = Set.union (Set.union borrowed owned) pvars
        let g2 = Option.map (rc Set.empty all) g
        let used = Set.intersect pvars (freeVars body)
        match p with
        | CPCtor(_, tag, fps) when xOwned && not (List.isEmpty fps || Set.contains x (live body)) ->
          // x dies here: specialize its drop, and reuse its cell if the body builds one alike
          let directOf (ifp: int * CPat) : option<int * string> =
            let (i, fp) = ifp
            match fp with
            | CPVar(w, _)
            | CPAs(_, w, _) when Set.contains w used -> Some(i, w)
            | _ -> None
          let direct = List.choose directOf (List.indexed fps)
          let keep = Set.ofList (List.map fst direct)
          let nested = Set.difference used (Set.ofList (List.map snd direct))
          let body2 = rc (Set.union (Set.remove x owned) used) borrowed body
          let tok = tmp ()
          let node =
            match Option.bind (fun l -> place tok l body2) (layoutOf s.ty tag (fieldTypes s.ty tag)) with
            | Some b -> CDropFields(x, s.ty, tag, keep, Some tok, b)
            | None -> CDropFields(x, s.ty, tag, keep, None, body2)
          (p, g2, dups nested (mk node body.ty))
        | _ ->
          // x stays alive past this case (or is borrowed): its fields are borrowed from it, and x,
          // or whatever owns it, lives as long as they're used
          for w in Set.toList pvars do
            parentOf.Value <- Map.add w x parentOf.Value
          (p, g2, rc owned (Set.union borrowed pvars) body)
      mk (CMatch(s, List.map one cases)) e.ty
    // match (a, b) with …: the tuple only borrows its parts, which stay with their variables (owned
    // as before); the pattern variables borrow from the part they come from, which lives as long
    // as they're used
    and matchTuple (owned: Set<string>) (borrowed: Set<string>) (e: CExpr) (xs: list<CExpr>) (s: CExpr) (cases: list<CPat * option<CExpr> * CExpr>) : CExpr =
      let one (c: CPat * option<CExpr> * CExpr) =
        let (p, g, body) = c
        let pvars = Set.ofList (List.filter heapVar (List.map fst (patVars p)))
        let g2 = Option.map (rc Set.empty (Set.union (Set.union borrowed owned) pvars)) g
        match p with
        | CPTuple ps ->
          for (xe, q) in List.zip xs ps do
            match xe.k with
            | CLocal xv ->
              for (w, _) in patVars q do
                if heapVar w then
                  parentOf.Value <- Map.add w xv parentOf.Value
            | _ -> ()
          (p, g2, rc owned (Set.union borrowed pvars) body)
        | _ ->
          // an or-pattern may take a variable from a different part in each alternative: no one
          // part to keep alive, so the ones used are dup'ed
          let used = Set.intersect pvars (freeVars body)
          (p, g2, dups used (rc (Set.union owned used) borrowed body))
      mk (CMatch(s, List.map one cases)) e.ty
    // x <- f … x …: when x is a direct argument of the call (once, and nowhere else in it), the
    // call gets x's own reference and the old value isn't dropped, so a unique value stays unique
    // (copy-on-write updates in place)
    and assignHeap (owned: Set<string>) (borrowed: Set<string>) (e: CExpr) (x: string) (w: CExpr) : CExpr =
      let isX (a: CExpr) = isLocalNamed x a
      let direct (args: list<CExpr>) =
        let others = List.filter (fun a -> not (isX a)) args
        List.length (List.filter isX args) = 1 && List.forall (fun (a: CExpr) -> not (Set.contains x (freeVars a))) others
      let take (args: list<CExpr>) = List.map (fun (a: CExpr) -> if isX a then mk (CPrim("slot.take", [ a ])) a.ty else a) args
      // x <- (let p = x in …), as an inlined call is: p gets x's own reference
      let rec viaLets (y: CExpr) : option<CExpr> =
        match y.k with
        | CLet(p, a, body) when isX a && not (Set.contains x (freeVars body)) -> Some(mk (CLet(p, mk (CPrim("slot.take", [ a ])) a.ty, body)) y.ty)
        | CLet(p, pv, body) when not (Set.contains x (freeVars pv)) -> Option.map (fun b -> mk (CLet(p, pv, b)) y.ty) (viaLets body)
        | _ -> None
      let moved =
        match w.k with
        | CCallDirect(g, args) when direct args -> Some(mk (CCallDirect(g, take args)) w.ty)
        | CPrim(op, args) when direct args -> Some(mk (CPrim(op, take args)) w.ty)
        | CLet _ -> viaLets w
        | _ -> None
      match moved with
      | Some m -> mk (CAssign(x, mk (CPrim("slot.moved", [ rc owned borrowed m ])) m.ty)) e.ty
      | None -> mk (CAssign(x, rc owned borrowed w)) e.ty
    // borrowed positions: a variable passed once is lent (and dropped after the call if this was
    // its last use); anything else goes through a temporary dropped after
    and callLending (owned: Set<string>) (borrowed: Set<string>) (e: CExpr) (n: string) (xs: list<CExpr>) : CExpr =
      let bs = Map.find n borrowedParams
      let lentArg (j: int) (a: CExpr) =
        match a.k with
        | CLocal x -> Set.contains j bs && List.length (List.filter (isLocalNamed x) xs) = 1
        | _ -> false
      let needsTemp (j: int) (a: CExpr) = Set.contains j bs && not (lentArg j a)
      let ixs = List.indexed xs
      if List.exists (fun (j, a) -> needsTemp j a) ixs then
        // bind the others' temporaries first, then retry with variables in their place
        let temps = List.map (fun (j, a) -> if needsTemp j a then Some(tmp (), a) else None) ixs
        for t in temps do
          match t with
          | Some(w, a) -> setType w a.ty
          | None -> ()
        let arg (t: option<string * CExpr>) (a: CExpr) =
          match t with
          | Some(w, _) -> mk (CLocal w) a.ty
          | None -> a
        let call = mk (CCallDirect(n, List.map2 arg temps xs)) e.ty
        let body = List.fold (fun (acc: CExpr) (w, a) -> mk (CLet(w, a, acc)) e.ty) call (List.rev (List.choose (fun t -> t) temps))
        rcIn owned borrowed body
      else
        let lentVars = Set.ofList (List.choose (fun (j, a) -> if lentArg j a then rootLocal a else None) ixs)
        let others = List.map snd (List.filter (fun (j, a) -> not (lentArg j a)) ixs)
        let others2 = rcList (Set.difference owned lentVars) (Set.union borrowed lentVars) others
        // the arguments in order: the lent ones as they are, the others as rcList made them
        let rec args (rest: list<int * CExpr>) (made: list<CExpr>) : list<CExpr> =
          match rest with
          | [] -> []
          | (j, a) :: more ->
            if lentArg j a then
              a :: args more made
            else
              match made with
              | m :: ms -> m :: args more ms
              | [] -> panic "Rc: unreachable"
        let call = mk (CCallDirect(n, args ixs others2)) e.ty
        let dying = Set.intersect owned lentVars
        if Set.isEmpty dying then
          call
        else
          let r = tmp ()
          setType r e.ty
          mk (CLet(r, call, drops dying (mk (CLocal r) e.ty))) e.ty
    // ---- moving out of mutable variables: `let r = f … x …` (or a match or statement on such a
    // call) where x is a `let mutable` passed directly, and x is reassigned before it is read again
    // on every path after it. The call gets x's own reference (so a unique value stays unique, and
    // Perceus can reuse its cell), and that reassignment drops nothing.
    let rec moves (e: CExpr) : CExpr =
      let re (k: CKind) = mk k e.ty
      match e.k with
      | CLet(y, w, b) -> split w [ b ] (fun w2 bs -> re (CLet(y, w2, List.head bs)))
      | CSeq(a, b) -> split a [ b ] (fun a2 bs -> re (CSeq(a2, List.head bs)))
      | CMatch(sc, cases) when List.forall (fun (_, g, _) -> Option.isNone g) cases ->
        split sc (List.map (fun (_, _, b) -> b) cases) (fun sc2 bs -> re (CMatch(sc2, List.map2 (fun (p, g, _) b -> (p, g, b)) cases bs)))
      | k -> re (mapChildren moves k)
    // h followed by continuations: move what every continuation reassigns first
    and split (h: CExpr) (conts: list<CExpr>) (build: CExpr -> list<CExpr> -> CExpr) : CExpr =
      match h.k with
      | CLine(l, inner) -> split inner conts (fun inner2 cs -> build (mk (CLine(l, inner2)) h.ty) cs)
      | _ ->
        let args =
          match h.k with
          | CCallDirect(_, a)
          | CCtor(_, _, a)
          | CTuple a -> a
          | CPrim(op, a) when not (String.startsWith "slot." op) -> a
          | _ -> []
        let movable (a: CExpr) : option<string> =
          match a.k with
          | CLocal x -> if Set.contains x mutables && heapVar x && List.forall (fun c -> firstUse x c = 2) conts then Some x else None
          | _ -> None
        let alone (x: string) = List.length (List.filter (isLocalNamed x) args) = 1 && List.forall (fun (a: CExpr) -> isLocalNamed x a || not (Set.contains x (freeVars a))) args
        let ok = List.filter alone (List.choose movable args)
        if List.isEmpty ok then
          build (moves h) (List.map moves conts)
        else
          let take (a: CExpr) =
            match a.k with
            | CLocal x -> if List.contains x ok then mk (CPrim("slot.take", [ a ])) a.ty else a
            | _ -> a
          let h2 =
            match h.k with
            | CCallDirect(n, a) -> mk (CCallDirect(n, List.map take a)) h.ty
            | CCtor(u, t, a) -> mk (CCtor(u, t, List.map take a)) h.ty
            | CTuple a -> mk (CTuple(List.map take a)) h.ty
            | CPrim(op, a) -> mk (CPrim(op, List.map take a)) h.ty
            | _ -> h
          build h2 (List.map (fun c -> moves (List.fold (fun c2 x -> markAssign x c2) c ok)) conts)
    let owned = Set.difference (Set.ofList (List.filter heapVar (List.map fst f.pars))) lent
    { f with body = rc owned lent (number (moves f.body)) }
  // ponytail: one function at a time; on every core when the passes run in parallel (step 6)
  List.map rcFun funs
