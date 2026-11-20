/// The IR checks between passes (zs build --check-ir, on in ./test.sh): after each pass, every
/// variable a function uses is bound in it, a jump goes to a join point around it with an argument
/// of each parameter's type, a direct call passes a function an argument of each parameter's type,
/// a dup or drop is of a variable bound with its type, and from monomorphization on no type has a
/// variable left; and after reference counting, every function's references are counted (owned,
/// below). A failure names the pass, the function and what's wrong, where it was made, rather
/// than as a crash of the binary.
open Types.Ty
open Core.Ir

// whether a type still has a type variable (or a scheme's)
let rec private generic (t: Ty) : bool =
  match t with
  | TVar _
  | TGen _ -> true
  | TCon(_, args) -> List.exists generic args
  | TTuple ts -> List.exists generic ts
  | TFun(a, b, r) -> generic a || generic b || generic r
  | TMeas(_, vs) -> not (List.isEmpty vs)

// two types the same, a function's effects aside (the passes after Evidence don't keep them)
let rec private same (a: Ty) (b: Ty) : bool =
  match (a, b) with
  | (TFun(a1, b1, _), TFun(a2, b2, _)) -> same a1 a2 && same b1 b2
  | (TCon(n, xs), TCon(m, ys)) -> n = m && sameAll xs ys
  | (TTuple xs, TTuple ys) -> sameAll xs ys
  | _ -> a = b

and private sameAll (xs: list<Ty>) (ys: list<Ty>) : bool =
  match (xs, ys) with
  | ([], []) -> true
  | (x :: xr, y :: yr) -> same x y && sameAll xr yr
  | _ -> false

/// What's wrong with a function's Core after a pass, if anything: monomorphic says types have no
/// variables any more, and arities gives the functions' parameter counts (for direct calls).
let private checkFun (monomorphic: bool) (signatures: Map<string, list<Ty>>) (f: Core.Program.MFun) : option<string> =
  let problem = ref None
  let say (what: string) =
    if Option.isNone problem.Value then
      problem.Value <- Some what
  let ty (where: string) (t: Ty) =
    if monomorphic && generic t then
      say $"{where} has a type with a variable left: {Types.Show.show (Types.Vars.make ()) t}"
  let rec walk (env: Map<string, Ty>) (joins: Map<string, list<Ty>>) (e: CExpr) =
    if Option.isNone problem.Value then
      ty "an expression" e.ty
      let bound (x: string) (what: string) =
        if not (Map.containsKey x env) then
          say $"{what} '{x}' isn't bound"
      let within (more: list<string * Ty>) = List.fold (fun m (x, t) -> Map.add x t m) env more
      let go (x: CExpr) = walk env joins x
      match e.k with
      | CLocal x -> bound x "a variable"
      | CAssign(x, v) ->
        bound x "an assigned variable"
        go v
      | CArraySet(x, i, v) ->
        bound x "an array set's variable"
        go i
        go v
      | CDup(x, t, body)
      | CDrop(x, t, body) ->
        match Map.tryFind x env with
        | None -> say $"a dup or drop of '{x}', which isn't bound"
        | Some bt -> if not (same bt t) then say $"a dup or drop of '{x}' as another type than it has"
        go body
      | CDropFields(x, _, _, _, token, body) ->
        bound x "a dropped cell"
        let inner = match token with | Some t -> Map.add t tUnit env | None -> env
        walk inner joins body
      | CFreeToken(t, body) ->
        bound t "a freed token"
        go body
      | CCtorAt(t, _, _, args) ->
        bound t "a reuse token"
        List.iter go args
      | CLam(ps, body) -> walk (within ps) joins body
      | CLet(x, v, body)
      | CLetMut(x, v, body) ->
        go v
        walk (Map.add x v.ty env) joins body
      | CLetFun(n, isRec, ps, body, rest) ->
        let self = if isRec then Map.add n e.ty env else env
        walk (List.fold (fun m (x, t) -> Map.add x t m) self ps) joins body
        walk (Map.add n e.ty env) joins rest
      | CLetRec(fs, rest) ->
        let names = List.fold (fun m (n, _, _) -> Map.add n tUnit m) env fs
        for (_, ps, body) in fs do
          walk (List.fold (fun m (x, t) -> Map.add x t m) names ps) joins body
        walk names joins rest
      | CFor(x, a, step, b, body) ->
        go a
        go step
        go b
        walk (Map.add x a.ty env) joins body
      | CMatch(scrut, cases) ->
        go scrut
        for (p, guard, body) in cases do
          let inner = within (patVars p)
          match guard with
          | Some g -> walk inner joins g
          | None -> ()
          walk inner joins body
      | CHandle(_, body, cls, (r, rt), ret) ->
        go body
        for (_, ps, (k, kt), cbody) in cls do
          walk (Map.add k kt (within ps)) joins cbody
        walk (Map.add r rt env) joins ret
      | CJoin(j, ps, body, rest) ->
        // the join point's body, its parameters bound; then the rest, whose paths may jump to it
        walk (within ps) joins body
        walk env (Map.add j (List.map snd ps) joins) rest
      | CJump(j, args) ->
        match Map.tryFind j joins with
        | None -> say $"a jump to '{j}', which isn't a join point around it"
        | Some ts ->
          if List.length ts <> List.length args then say $"a jump to '{j}' with {List.length args} arguments for its {List.length ts} parameters"
          else if not (List.forall id (List.map2 (fun (t: Ty) (a: CExpr) -> same t a.ty) ts args)) then say $"a jump to '{j}' with an argument of another type than its parameter"
        List.iter go args
      | CCallDirect(g, args) ->
        match Map.tryFind g signatures with
        | Some ts when List.length ts <> List.length args -> say $"a call of '{g}' with {List.length args} arguments for its {List.length ts} parameters"
        | Some ts when not (List.forall id (List.map2 (fun (t: Ty) (a: CExpr) -> same t a.ty) ts args)) -> say $"a call of '{g}' with an argument of another type than its parameter"
        | _ -> ()
        List.iter go args
      | k -> List.iter go (children k)
  for (x, t) in f.pars do
    ty $"parameter '{x}'" t
  ty "the result" f.ret
  walk (Map.ofList f.pars) Map.empty f.body
  problem.Value

/// What's wrong after a pass, in the first function with something wrong: "after inline, in
/// List.map: …"; monomorphic from monomorphization on.
let core (pass: string) (monomorphic: bool) (funs: list<Core.Program.MFun>) : option<string> =
  let signatures = Map.ofList (List.map (fun (f: Core.Program.MFun) -> (f.name, List.map snd f.pars)) funs)
  let first (f: Core.Program.MFun) = Option.map (fun what -> $"after {pass}, in {f.name}: {what}") (checkFun monomorphic signatures f)
  List.tryPick first funs

// ---- ownership, after reference counting (docs/reports/ownership-check.md)

// what a function's code holds of a counted variable. n: the references of its own it has yet to
// give away; via: where it's alive without one ("" nowhere, "*" the caller's, else the variable
// it was read from); cell: a `let mutable`'s slot (0 not one, 1 full, 2 moved out by slot.take,
// to be filled by slot.moved)
type private Held = { n: int; via: string; cell: int }

// what's wrong with a function's counts after reference counting, if anything: its code walked
// in the order it runs, each variable's references counted
let private ownedFun (heap: Ty -> bool) (borrowed: Map<string, Set<int>>) (f: Core.Program.MFun) : option<string> =
  let problem = ref None
  let say (what: string) =
    if Option.isNone problem.Value then
      problem.Value <- Some what
  let st = ref Map.empty
  // the path ended in a jump
  let gone = ref false
  let tokens = ref Set.empty
  // a matched variable's case: its tag and its fields' patterns
  let pats = ref Map.empty
  // what's held at each jump to a join point
  let arrivals = ref Map.empty
  let rec alive (x: string) : bool =
    match Map.tryFind x st.Value with
    | None -> true
    | Some h -> h.cell > 0 || h.n > 0 || h.via = "*" || (h.via <> "" && alive h.via)
  let read (x: string) =
    if not (alive x) then
      say $"'{x}' is read after its last reference went"
  let add (x: string) (d: int) =
    match Map.tryFind x st.Value with
    | Some h ->
      if h.n + d < 0 then say $"'{x}' is given away with no reference of its own"
      else st.Value <- Map.add x { h with n = h.n + d } st.Value
    | None -> ()
  let bind (x: string) (n: int) (via: string) (cell: int) = st.Value <- Map.add x { n = n; via = via; cell = cell } st.Value
  let unbind (x: string) =
    if not gone.Value then
      match Map.tryFind x st.Value with
      | Some h ->
        if h.n > 0 then say $"'{x}' is left with a reference nothing takes"
        else if h.cell = 2 then say $"mutable '{x}' is left moved out"
      | None -> ()
    st.Value <- Map.remove x st.Value
  let rec unlined (e: CExpr) : CExpr =
    match e.k with
    | CLine(_, a) -> unlined a
    | _ -> e
  let local (e: CExpr) : option<string> =
    match (unlined e).k with
    | CLocal x -> Some x
    | _ -> None
  let rec root (e: CExpr) : option<string> =
    match e.k with
    | CLocal x -> Some x
    | CField(r, _)
    | CLine(_, r) -> root r
    | _ -> None
  let isToken (e: CExpr) : bool =
    match (unlined e).k with
    | CLocal y -> Set.contains y tokens.Value
    | CPrim("token.null", _) -> true
    | _ -> false
  let same (a: Map<string, Held>) (b: Map<string, Held>) (where: string) =
    match List.tryFind (fun (x: string) -> Map.tryFind x a <> Map.tryFind x b) (List.append (Map.keys a) (Map.keys b)) with
    | Some x -> say $"'{x}' is held differently {where}"
    | None -> ()
  // the paths of alternatives: those that don't end in a jump end holding the same
  let branch (alts: list<unit -> unit>) =
    let s0 = st.Value
    let ends = ref []
    for alt in alts do
      st.Value <- s0
      gone.Value <- false
      alt ()
      if not gone.Value then
        ends.Value <- st.Value :: ends.Value
    match List.rev ends.Value with
    | [] -> gone.Value <- true
    | first :: more ->
      for m in more do
        same first m "at the ends of two branches"
      st.Value <- first
      gone.Value <- false
  let rec ev (e: CExpr) =
    if Option.isNone problem.Value then
      match e.k with
      | CLocal x -> add x (-1)
      | CLine(_, a) -> ev a
      | CDup(x, _, b) ->
        read x
        add x 1
        ev b
      | CDrop(x, _, b) ->
        add x (-1)
        ev b
      | CLet(x, w, b) ->
        match (unlined w).k with
        | CField(r, _) when heap w.ty && Option.isSome (root r) ->
          // a field read: its holder's, until a dup
          let y = Option.get (root r)
          read y
          bind x 0 y 0
        // a top-level value keeps its reference
        | CGlobalVal _ when heap w.ty -> bind x 0 "*" 0
        | _ ->
          let token = String.startsWith "$rc" x && isToken w
          ev w
          if token then
            tokens.Value <- Set.add x tokens.Value
          if token || heap w.ty then
            bind x 1 "" 0
        ev b
        unbind x
      | CLetMut(x, w, b) ->
        ev w
        if heap w.ty then
          bind x 0 "" 1
        ev b
        unbind x
      | CSeq(a, b) ->
        ev a
        if heap a.ty then
          say "a counted value is discarded"
        ev b
      | CIf(c, t, el) ->
        ev c
        branch [ (fun () -> ev t); (fun () -> ev el) ]
      | CMatch(s, cases) ->
        // a variable matched, or a tuple of them, lends the patterns' variables
        let holders =
          match (unlined s).k with
          | CLocal x -> [ x ]
          | CTuple xs when List.forall (fun (a: CExpr) -> Option.isSome (local a)) xs -> List.map (fun (a: CExpr) -> Option.get (local a)) xs
          | _ -> []
        if List.isEmpty holders then ev s else List.iter read holders
        let case (c: CPat * option<CExpr> * CExpr) () =
          let (p, g, body) = c
          let lend (via: string) (q: CPat) =
            for (x, t) in patVars q do
              if heap t then
                bind x 0 via 0
          match (holders, p) with
          | ([ x ], CPCtor(_, tag, fps)) ->
            pats.Value <- Map.add x (tag, fps) pats.Value
            lend x p
          | (xs, CPTuple qs) when List.length xs = List.length qs -> List.iter2 lend xs qs
          | (x :: _, _) -> lend x p
          | ([], _) -> lend "" p
          match g with
          | Some guard ->
            let before = st.Value
            ev guard
            same before st.Value "before and after a guard"
          | None -> ()
          ev body
          for (x, _) in patVars p do
            unbind x
        branch (List.map case cases)
      | CField(r, _) ->
        match root r with
        | Some x ->
          read x
          if heap e.ty then
            say $"a field of '{x}' is taken without a reference of its own"
        | None ->
          ev r
          if heap r.ty then
            say "a field is read from a value nothing holds"
      | CApplyClo(fe, args) ->
        List.iter ev args
        match local fe with
        | Some x -> read x
        | None -> say "a closure is applied that nothing holds"
      | CCallDirect(g, args) ->
        let lends = Option.defaultValue Set.empty (Map.tryFind g borrowed)
        let lent = ref []
        let one (j: int) (a: CExpr) =
          if Set.contains j lends && heap a.ty then
            match local a with
            | Some x -> lent.Value <- x :: lent.Value
            | None -> say $"a call of '{g}' lends a value nothing holds"
          else
            ev a
        List.iteri one args
        List.iter read lent.Value
      // shortcut: a moved-out mutable may still be read (its value is the taker's until that's
      // given away, which isn't followed here); follow the taker when Rc's moves grow
      | CPrim("slot.take", [ a ]) ->
        match local a with
        | Some x ->
          match Map.tryFind x st.Value with
          | Some h -> if h.cell = 1 then st.Value <- Map.add x { h with cell = 2 } st.Value else say $"'{x}' is moved out, and isn't a mutable holding a value"
          | None -> ()
        | None -> say "slot.take of what isn't a variable"
      | CPrim("task.held", _)
      | CPrim("token.null", _) -> ()
      | CPrim(op, a :: rest) when String.endsWith "#b" op ->
        List.iter ev rest
        match root a with
        | Some x -> read x
        | None -> say $"{op} reads a value nothing holds"
      | CAssign(x, w) ->
        let moved =
          match w.k with
          | CPrim("slot.moved", [ v ]) ->
            ev v
            true
          | _ ->
            ev w
            false
        match Map.tryFind x st.Value with
        | Some h ->
          if h.cell = 0 then ()
          else if moved && h.cell = 1 then say $"'{x}' is assigned as moved out while it holds a value"
          else if not moved && h.cell = 2 then say $"'{x}' is assigned as holding a value while it's moved out"
          else st.Value <- Map.add x { h with cell = 1 } st.Value
        | None -> ()
      | CArraySet(x, i, w) ->
        ev i
        ev w
        read x
      | CCtorAt(t, _, _, args) ->
        List.iter ev args
        add t (-1)
      | CFreeToken(t, b) ->
        add t (-1)
        ev b
      | CDropFields(x, _, tag, keep, token, b) ->
        add x (-1)
        match Map.tryFind x pats.Value with
        | Some(ptag, fps) when ptag = tag ->
          for (i, fp) in List.indexed fps do
            if Set.contains i keep then
              match fp with
              | CPVar(w, _)
              | CPAs(_, w, _) -> add w 1
              | _ -> ()
        | _ -> say $"the fields of '{x}' are dropped outside its match"
        match token with
        | Some t ->
          tokens.Value <- Set.add t tokens.Value
          bind t 1 "" 0
          ev b
          unbind t
        | None -> ev b
      | CWhile _
      | CFor _ ->
        // runs any number of times: it leaves what it found
        let before = st.Value
        List.iter ev (children e.k)
        if not gone.Value then
          same before st.Value "before and after a loop"
      | CJump(j, args) ->
        List.iter ev args
        arrivals.Value <- Map.add j (st.Value :: Option.defaultValue [] (Map.tryFind j arrivals.Value)) arrivals.Value
        gone.Value <- true
      | CJoin(j, ps, body, rest) ->
        let outer = st.Value
        arrivals.Value <- Map.add j [] arrivals.Value
        ev rest
        let restEnd = if gone.Value then None else Some st.Value
        // what a jump leaves behind is gone; what was around the join point arrives with it
        let arrived (a: Map<string, Held>) : Map<string, Held> =
          let keeps (xh: string * Held) =
            let (x, h) = xh
            if Map.containsKey x outer then
              true
            else
              if h.n > 0 || h.cell = 2 then
                say $"'{x}' is left with a reference at a jump to '{j}'"
              false
          Map.ofList (List.filter keeps (Map.toList a))
        match List.map arrived (Map.find j arrivals.Value) with
        | [] ->
          match restEnd with
          | Some s -> st.Value <- s
          | None -> ()
        | first :: more ->
          for m in more do
            same first m $"at two jumps to '{j}'"
          st.Value <- first
          gone.Value <- false
          for (x, t) in ps do
            let token = String.startsWith "$rc" x && t = tcon "cptr"
            if token then
              tokens.Value <- Set.add x tokens.Value
            if token || heap t then
              bind x 1 "" 0
          ev body
          for (x, _) in ps do
            unbind x
          match restEnd with
          | Some s ->
            if gone.Value then
              st.Value <- s
              gone.Value <- false
            else
              same s st.Value $"after join point '{j}' and after its rest"
          | None -> ()
      | k -> List.iter ev (children k)
  let mine = Option.defaultValue Set.empty (Map.tryFind f.name borrowed)
  for (i, (x, t)) in List.indexed f.pars do
    if heap t then
      if Set.contains i mine then bind x 0 "*" 0 else bind x 1 "" 0
  ev f.body
  for (x, _) in f.pars do
    unbind x
  problem.Value

/// What's wrong with the counts after reference counting, in the first function with something
/// wrong: every reference a function's code gets (a parameter it owns, a value it makes, a dup)
/// is given away once on every path (to a call, a cell, its result, a drop), nothing is read once
/// its last reference went, a reuse token is used once, and a `let mutable` moved out is filled
/// again. borrowed: the parameters each function borrows, which its callers lend.
let owned (types: Map<string, TypeInfo>) (borrowed: Map<string, Set<int>>) (funs: list<Core.Program.MFun>) : option<string> =
  let v = Types.Vars.make ()
  let seen = ref Map.empty
  let heap (t: Ty) : bool =
    match Map.tryFind t seen.Value with
    | Some b -> b
    | None ->
      let b = Types.Repr.needsRc v types t
      seen.Value <- Map.add t b seen.Value
      b
  let first (f: Core.Program.MFun) = Option.map (fun what -> $"after reference counting, in {f.name}: {what}") (ownedFun heap borrowed f)
  List.tryPick first funs
