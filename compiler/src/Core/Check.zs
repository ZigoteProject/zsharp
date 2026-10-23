/// The IR checks between passes (zs build --check-ir, on in ./test.sh): after each pass, every
/// variable a function uses is bound in it, a jump goes to a join point around it with an argument
/// of each parameter's type, a direct call passes a function an argument of each parameter's type,
/// a dup or drop is of a variable bound with its type, and from monomorphization on no type has a
/// variable left. A failure names the pass, the function and what's wrong, where it was made,
/// rather than as a crash of the binary.
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
