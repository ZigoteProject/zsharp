/// Types under their variables' bindings: rows taken apart, measures in normal form, schemes
/// instantiated (TGen replaced), and types resolved (their free variables defaulted).
open Ty
open Vars

/// A row's labels, in order, and its tail: the empty row, or a variable.
let rec rowParts (v: Vars) (r: Ty) : list<Ty> * Ty =
  match prune v r with
  | TCon("$ext", [ l; rest ]) ->
    let (ls, t) = rowParts v rest
    (l :: ls, t)
  | t -> ([], t)

/// An effect label's name: Yield for Yield<int>.
let labelName (v: Vars) (l: Ty) : string =
  match prune v l with
  | TCon(n, _) -> n
  | _ -> ""

let isRowEmpty (v: Vars) (r: Ty) : bool =
  match rowParts v r with
  | ([], t) ->
    match prune v t with
    | TCon("$total", []) -> true
    | _ -> false
  | _ -> false

/// Whether two types are the same variable (a TVar's number, or a TGen's).
let sameVar (v: Vars) (a: Ty) (b: Ty) : bool =
  match (prune v a, prune v b) with
  | (TVar x, TVar y) -> x = y
  | (TGen i, TGen j) -> i = j
  | _ -> false

/// A measure in normal form: variables expanded, like terms merged, zeros dropped, units sorted.
let normMeas (v: Vars) (t: Ty) : list<string * int> * list<Ty * int> =
  let units = Buffer.empty
  let unitPowers = Buffer.empty
  let vars = Buffer.empty
  let powers = Buffer.empty
  let addVar (x: Ty) (e: int) =
    let mutable found = -1
    for i in 0 .. Buffer.length vars - 1 do
      if found < 0 && sameVar v vars.[i] x then
        found <- i
    if found >= 0 then
      powers.[found] <- powers.[found] + e
    else
      Buffer.push x vars
      Buffer.push e powers
  let addUnit (u: string) (e: int) =
    let mutable found = -1
    for i in 0 .. Buffer.length units - 1 do
      if found < 0 && units.[i] = u then
        found <- i
    if found >= 0 then
      unitPowers.[found] <- unitPowers.[found] + e
    else
      Buffer.push u units
      Buffer.push e unitPowers
  let rec go (t: Ty) (k: int) =
    match prune v t with
    | TMeas(us, vs) ->
      for (u, e) in us do
        addUnit u (e * k)
      for (x, e) in vs do
        go x (e * k)
    | x -> addVar x k
  go t 1
  let us = [ for i in 0 .. Buffer.length units - 1 do if unitPowers.[i] <> 0 then yield (units.[i], unitPowers.[i]) ]
  let vs = [ for i in 0 .. Buffer.length vars - 1 do if powers.[i] <> 0 then yield (vars.[i], powers.[i]) ]
  (List.sortBy fst us, vs)

/// A measure in normal form, as a type.
let normal (v: Vars) (t: Ty) : Ty =
  match normMeas v t with
  | (us, vs) -> TMeas(us, vs)

let isOneMeas (v: Vars) (t: Ty) : bool =
  match normMeas v t with
  | ([], []) -> true
  | _ -> false

/// A numeric type with a measure; unitless when the measure is 1.
let numWith (v: Vars) (n: string) (m: Ty) : Ty =
  if isOneMeas v m then TCon(n, []) else TCon(n, [ normal v m ])

let measOf (args: list<Ty>) : Ty =
  match args with
  | [ m ] -> m
  | _ -> measOne

let measMul (v: Vars) (a: Ty) (b: Ty) : Ty = normal v (TMeas([], [ (a, 1); (b, 1) ]))

let measDiv (v: Vars) (a: Ty) (b: Ty) : Ty = normal v (TMeas([], [ (a, 1); (b, -1) ]))

/// Replaces TGen i with args[i].
let rec substGen (v: Vars) (args: list<Ty>) (t: Ty) : Ty =
  match prune v t with
  | TGen i -> List.item i args
  | TMeas(us, vs) -> normal v (TMeas(us, List.map (fun (x, e) -> (substGen v args x, e)) vs))
  | TCon(n, a) -> TCon(n, List.map (substGen v args) a)
  | TFun(a, b, r) -> TFun(substGen v args a, substGen v args b, substGen v args r)
  | TTuple ts -> TTuple(List.map (substGen v args) ts)
  | x -> x

// what an unconstrained variable of a kind becomes: int, f64, string, bool or unit, the first
// the kind allows
let private defaultOf (k: Kind) : Ty =
  let fits (n: string) =
    let allowed =
      match k.allowed with
      | Some s -> Set.contains n s
      | None -> true
    allowed && List.forall (fun tr -> hasBuiltinImpl tr n) (Set.toList k.traits)
  match List.tryFind fits [ "int"; "f64"; "string"; "bool"; "unit" ] with
  | Some n -> tcon n
  | None ->
    match k.allowed with
    | Some s ->
      match Set.toList s with
      | n :: _ -> tcon n
      | [] -> tInt
    | None -> tInt

/// Fully resolves a type, its unconstrained variables defaulted (int, f64 or string by kind).
let rec resolve (v: Vars) (t: Ty) : Ty =
  match prune v t with
  | TVar i ->
    let d = defaultOf (kindOf v i)
    bind v i d
    d
  | TCon(n, args) -> TCon(n, List.map (resolve v) args)
  | TFun(a, b, r) -> TFun(resolve v a, resolve v b, resolveRow v r)
  | TTuple ts -> TTuple(List.map (resolve v) ts)
  | TGen i -> TGen i
  | TMeas(us, vs) ->
    // an unconstrained measure variable is 1
    for (x, _) in vs do
      match prune v x with
      | TVar i -> bind v i measOne
      | _ -> ()
    normal v (TMeas(us, vs))

/// A row resolved: an unconstrained tail is the empty row, and the labels are in canonical order
/// (by effect, the innermost first among one effect's: a stable sort), so equal rows are equal.
and resolveRow (v: Vars) (r: Ty) : Ty =
  let (ls, tail) = rowParts v r
  let tail =
    match prune v tail with
    | TVar i ->
      bind v i rowEmpty
      rowEmpty
    | x -> x
  mkRow (List.sortBy (labelName v) (List.map (resolve v) ls)) tail
