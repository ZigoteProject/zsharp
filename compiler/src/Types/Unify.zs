/// Unification (decision 73): two types made the same, their variables bound; a kinded variable
/// meets the other's kind (a literal's types, the traits it needs). What doesn't unify is thrown
/// (Mismatched), and the expression under check catches it; a trial undoes its bindings (Vars).
/// Units of measure unify as Kennedy's, rows as Leijen's scoped labels.
open Ty
open Vars
open Norm
open Show
open Fail

/// What unification asks of the checker it works for (its context 'c): whether a type has a
/// trait through a user impl (the impl's own requirements pushed onto the type's arguments), and
/// the trait's other parameters as the impl for a type determines them (Iter on list<int>:
/// [int], 0017).
type Hooks<'c> =
  { userImpl: 'c -> string -> Ty -> bool / <Mismatched, Fails>
    implParams: 'c -> string -> Ty -> option<list<Ty>> }

let private differ () : 'a / Mismatched = Mismatched.throw Differ

// both constraints at once: literal kinds keep only the types that also have the traits
let private meet (v: Vars) (h: Hooks<'c>) (c: 'c) (a: Kind) (b: Kind) : Kind / <Mismatched, Fails> =
  let traits = Set.union a.traits b.traits
  // a trait's other parameters, which unify unifies first where both kinds have them
  let pars = Map.fold (fun (m: Map<string, list<Ty>>) k x -> if Map.containsKey k m then m else Map.add k x m) a.params b.params
  let allowed =
    match (a.allowed, b.allowed) with
    | (None, k) -> k
    | (k, None) -> k
    | (Some x, Some y) -> Some(Set.intersect x y)
  let has (tr: string) (n: string) = hasBuiltinImpl tr n || h.userImpl c tr (tcon n)
  match allowed with
  | Some s ->
    let ok = Set.ofList (List.filter (fun n -> List.forall (fun tr -> has tr n) (Set.toList traits)) (Set.toList s))
    if Set.isEmpty s then
      differ ()
    else if Set.isEmpty ok then
      let tr =
        match List.tryFind (fun tr -> List.forall (fun n -> not (has tr n)) (Set.toList s)) (Set.toList traits) with
        | Some tr -> tr
        | None -> ""
      let shown = if Set.contains "int" s then "int" else if Set.contains "f64" s then "f64" else List.head (Set.toList s)
      Mismatched.throw (NoImpl(tr, tcon shown))
    else
      { allowed = Some ok; traits = traits; params = pars }
  | None -> { allowed = None; traits = traits; params = pars }

let rec private occurs (v: Vars) (r: int) (t: Ty) : bool =
  match prune v t with
  | TVar i -> i = r
  | TCon(_, ts)
  | TTuple ts -> List.exists (occurs v r) ts
  | TFun(a, b, row) -> occurs v r a || occurs v r b || occurs v r row
  | TMeas(_, vs) -> List.exists (fun (x, _) -> occurs v r x) vs
  | TGen _ -> false

// floor division, toward -infinity
let private floorDiv (k: int) (e: int) : int = if k % e <> 0 && ((k < 0) <> (e < 0)) then k / e - 1 else k / e

/// Unifies two units of measure (Kennedy): solves a/b = 1 for the variable v with the smallest
/// exponent e. When e divides every other exponent, v = rest^(-1/e). Otherwise v becomes a fresh
/// variable times rest^(-floor(k/e)), which leaves every other exponent smaller than e, and the
/// rest is solved again: so 'u^2 = 'v^3 gives 'u = 'w^3 and 'v = 'w^2. Rigid variables (a
/// generic function's own) can't be solved for; when only they are left, the units differ.
let rec private unifyMeas (v: Vars) (a: Ty) (b: Ty) : unit / Mismatched =
  match normMeas v (measDiv v a b) with
  | ([], []) -> ()
  | (us, vs) ->
    let isVar (p: Ty * int) =
      match prune v (fst p) with
      | TVar _ -> true
      | _ -> false
    let solvable = List.filter isVar vs
    if List.isEmpty solvable then
      differ ()
    let abs (n: int) = if n < 0 then -n else n
    let (x, e) = List.fold (fun (bx, be) (y, f) -> if abs f < abs be then (y, f) else (bx, be)) (List.head solvable) (List.tail solvable)
    let others = List.filter (fun (w, _) -> not (sameVar v w x)) vs
    let divides = List.forall (fun (_, k) -> k % e = 0) us && List.forall (fun (_, k) -> k % e = 0) others
    match prune v x with
    | TVar r when divides ->
      // v^e * rest = 1  =>  v = rest^(-1/e)
      bind v r (TMeas(List.map (fun (u, k) -> (u, -k / e)) us, List.map (fun (w, k) -> (w, -k / e)) others))
    | TVar _ when List.length solvable = 1 -> differ () // v^e = units e doesn't divide
    | TVar r ->
      let w = fresh v kAny
      bind v r (TMeas(List.map (fun (u, k) -> (u, -(floorDiv k e))) us, (w, 1) :: List.map (fun (y, k) -> (y, -(floorDiv k e))) others))
      unifyMeas v a b
    | _ -> differ ()

// whether a type has what a kind asks: one of its allowed types, every trait
let private satisfies (v: Vars) (h: Hooks<'c>) (c: 'c) (k: Kind) (t: Ty) : bool / <Mismatched, Fails> =
  let allowedOk =
    match (k.allowed, t) with
    | (None, _) -> true
    | (Some s, TCon(n, [])) -> Set.contains n s
    | _ -> false
  let has (tr: string) =
    let ok =
      match t with
      | TCon(n, []) when hasBuiltinImpl tr n -> true
      | TCon(n, [ TMeas _ ]) when hasBuiltinImpl tr n -> true
      | _ -> h.userImpl c tr t
    if not ok then
      Mismatched.throw (NoImpl(tr, t))
    true
  allowedOk && List.forall has (Set.toList k.traits)

/// Makes two types the same.
let rec unify (v: Vars) (h: Hooks<'c>) (c: 'c) (a: Ty) (b: Ty) : unit / <Mismatched, Fails> =
  match (prune v a, prune v b) with
  | (TVar r1, TVar r2) when r1 = r2 -> ()
  | (TVar r1, TVar r2) ->
    // 'c : Iter<int> and 'c : Iter<'a>: one type's elements have one type
    let k1 = kindOf v r1
    let k2 = kindOf v r2
    for (tr, ps) in Map.toList k1.params do
      match Map.tryFind tr k2.params with
      | Some qs -> List.iter2 (unify v h c) ps qs
      | None -> ()
    let k = meet v h c (kindOf v r1) (kindOf v r2)
    if isFree v r2 then
      setKind v r2 k
    bind v r1 (TVar r2)
    // a literal's type the trait leaves one choice for ("abc" : Iter<'a>: a string, not a cstr)
    // is that type now, so the impl gives the trait's other parameters
    match k.allowed with
    | Some s when Set.count s = 1 && not (Map.isEmpty k.params) -> unify v h c (TVar r2) (tcon (List.head (Set.toList s)))
    | _ -> ()
  | (TVar r, t)
  | (t, TVar r) ->
    let k = kindOf v r
    if occurs v r t || not (satisfies v h c k t) then
      differ ()
    bind v r t
    // the impl for t's head determines the trait's other parameters
    for (tr, ps) in Map.toList k.params do
      match h.implParams c tr t with
      | Some os -> List.iter2 (unify v h c) ps os
      | None -> ()
  | (TCon(x, xs), TCon(y, ys)) when x = y && Set.contains x nums -> unifyMeas v (measOf xs) (measOf ys)
  | (TMeas _, _)
  | (_, TMeas _) -> unifyMeas v a b
  | (TCon(x, xs), TCon(y, ys)) when x = y && List.length xs = List.length ys -> List.iter2 (unify v h c) xs ys
  | (TFun(a1, b1, r1), TFun(a2, b2, r2)) ->
    unify v h c a1 a2
    unify v h c b1 b2
    unifyRow v h c r1 r2
  | (TTuple xs, TTuple ys) when List.length xs = List.length ys -> List.iter2 (unify v h c) xs ys
  | (TGen i, TGen j) when i = j -> ()
  | _ -> differ ()

/// Unifies two effect rows (Leijen's scoped labels): each label of one meets the first label of
/// the other with its effect's name (their type arguments unify), and each row's tail takes
/// what's left of the other's. A closed row (no variable) can't take more.
and unifyRow (v: Vars) (h: Hooks<'c>) (c: 'c) (r1: Ty) (r2: Ty) : unit / <Mismatched, Fails> =
  match (prune v r1, prune v r2) with
  | (TVar a, TVar b) when a = b -> ()
  | (TCon("$total", []), TCon("$total", [])) -> ()
  // a bare variable takes the other row whole (pure code's rows are mostly these)
  | (TVar x, t)
  | (t, TVar x) ->
    if occurs v x t then
      differ ()
    bind v x t
  | _ -> unifyLabels v h c r1 r2

and private unifyLabels (v: Vars) (h: Hooks<'c>) (c: 'c) (r1: Ty) (r2: Ty) : unit / <Mismatched, Fails> =
  let (ls1, _) = rowParts v r1
  let (ls2, _) = rowParts v r2
  let rest1 = Buffer.empty
  let mutable rest2 = ls2
  for l in ls1 do
    match List.tryFindIndex (fun m -> labelName v m = labelName v l) rest2 with
    | Some i ->
      match (prune v l, prune v (List.item i rest2)) with
      | (TCon(_, xs), TCon(_, ys)) when List.length xs = List.length ys -> List.iter2 (unify v h c) xs ys
      | _ -> differ ()
      rest2 <- List.removeAt i rest2
    | None -> Buffer.push l rest1
  let rest1 = Array.toList (Buffer.toArray rest1)
  // the tails after the labels' arguments unified, which may have linked them
  let t1 = prune v (snd (rowParts v r1))
  let t2 = prune v (snd (rowParts v r2))
  let link (x: int) (row: Ty) =
    if occurs v x row then
      differ ()
    bind v x row
  match (t1, t2) with
  | (TVar v1, TVar v2) when v1 = v2 -> if not (List.isEmpty rest1 && List.isEmpty rest2) then differ ()
  | (TVar v1, TVar v2) ->
    let tail = fresh v kRow
    link v1 (mkRow rest2 tail)
    link v2 (mkRow rest1 tail)
  | (TVar v1, _) when List.isEmpty rest1 -> link v1 (mkRow rest2 t2)
  | (_, TVar v2) when List.isEmpty rest2 -> link v2 (mkRow rest1 t1)
  | (TCon("$total", []), TCon("$total", [])) when List.isEmpty rest1 && List.isEmpty rest2 -> ()
  | (TGen i, TGen j) when i = j && List.isEmpty rest1 && List.isEmpty rest2 -> ()
  | _ -> differ ()

/// The effects a function type performs where the other one, of the same shape, can't: the labels
/// of its rows that the other's closed rows lack ([] when the shapes differ or none).
let rec extraEffects (v: Vars) (expected: Ty) (actual: Ty) : list<Ty> =
  match (prune v expected, prune v actual) with
  | (TFun(a1, b1, r1), TFun(a2, b2, r2)) ->
    let here =
      match rowParts v r1 with
      | (ls, t) ->
        match prune v t with
        | TCon("$total", []) -> List.filter (fun l -> not (List.exists (fun m -> labelName v m = labelName v l) ls)) (fst (rowParts v r2))
        | _ -> []
    List.concat [ here; extraEffects v a1 a2; extraEffects v b1 b2 ]
  | (TCon(n, xs), TCon(m, ys)) when n = m && List.length xs = List.length ys -> List.concat (List.map2 (extraEffects v) xs ys)
  | (TTuple xs, TTuple ys) when List.length xs = List.length ys -> List.concat (List.map2 (extraEffects v) xs ys)
  | _ -> []

/// Effects as text: Yield<int>, Log.
let showEffects (v: Vars) (ls: list<Ty>) : string = String.join ", " (List.distinct (List.map (show v) ls))
