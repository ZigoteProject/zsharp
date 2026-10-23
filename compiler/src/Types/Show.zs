/// Types as text (0025's printer). With `full`, names keep their namespaces (for symbol names and
/// lookup keys, which must tell a program's own Map from Collections.Map) and every row shows;
/// without, they read as written. A function's effects follow its result (`int -> unit /
/// Yield<int>`); one without any shows none. The function's ambient row (its last arrow's row
/// variable) isn't shown where it only connects the function arguments to the function, as their
/// last arrows' rows (`List.iter : ('a -> unit) -> list<'a> -> unit`); an argument that must
/// perform nothing shows `/ <>`.
open Ty
open Vars
open Norm

// the type variables of a type, each as often as it occurs
let rec private varsIn (v: Vars) (t: Ty) : list<Ty> =
  match prune v t with
  | TVar i -> [ TVar i ]
  | TGen i -> [ TGen i ]
  | TCon(_, ts)
  | TTuple ts -> List.concat (List.map (varsIn v) ts)
  | TFun(a, b, r) -> List.concat [ varsIn v a; varsIn v b; varsIn v r ]
  | TMeas(_, vs) -> List.concat (List.map (fun (x, _) -> varsIn v x) vs)

/// A function type's last arrow's row (`a -> b -> c / R`: R), if the type is a function.
let rec lastRow (v: Vars) (t: Ty) : option<Ty> =
  match prune v t with
  | TFun(_, b, r) ->
    match prune v b with
    | TFun _ -> lastRow v b
    | _ -> Some r
  | _ -> None

// the rows in ambient places (0025): a function type's last arrow, and the last arrows of the
// function types in argument position, at any depth
let rec private ambientRows (v: Vars) (t: Ty) : list<Ty> =
  match prune v t with
  | TFun(a, b, r) ->
    let arg =
      match prune v a with
      | TFun _ -> ambientRows v a
      | _ -> []
    let rest =
      match prune v b with
      | TFun _ -> ambientRows v b
      | _ -> [ r ]
    List.append arg rest
  | _ -> []

// a type variable's name
let private varName (v: Vars) (i: int) : string =
  let k = kindOf v i
  match k.allowed with
  | Some s when Set.contains "int" s -> "int"
  | Some s when Set.contains "f64" s -> "f64"
  | Some s when Set.contains "string" s -> "string"
  | _ -> $"'t{i + 1}"

/// A type as text.
let showWith (v: Vars) (full: bool) (t: Ty) : string =
  let vars = varsIn v t
  // the ambient row's variable, when every place it's in is an ambient one
  let ambient =
    if full then
      None
    else
      match lastRow v t with
      | Some r ->
        match prune v (snd (rowParts v r)) with
        | TVar i ->
          let x = TVar i
          let all = List.length (List.filter (sameVar v x) vars)
          let placed = List.length (List.filter (fun r -> sameVar v (snd (rowParts v r)) x) (ambientRows v t))
          if all = placed then Some x else None
        | TGen i ->
          let x = TGen i
          let all = List.length (List.filter (sameVar v x) vars)
          let placed = List.length (List.filter (fun r -> sameVar v (snd (rowParts v r)) x) (ambientRows v t))
          if all = placed then Some x else None
        | _ -> None
      | None -> None
  let hidden (x: Ty) =
    match ambient with
    | Some a -> sameVar v a x
    | None -> false
  // the row variables shown, in the order first met
  let rowVars = Buffer.empty
  let rec findRows (t: Ty) =
    match prune v t with
    | TFun(a, b, r) ->
      findRows a
      findRows b
      let tail = prune v (snd (rowParts v r))
      let isVar =
        match tail with
        | TVar _
        | TGen _ -> true
        | _ -> false
      if isVar && not (hidden tail) then
        let mutable seen = false
        for i in 0 .. Buffer.length rowVars - 1 do
          if sameVar v rowVars.[i] tail then
            seen <- true
        if not seen then
          Buffer.push tail rowVars
      for l in fst (rowParts v r) do
        findRows l
    | TCon(_, ts)
    | TTuple ts ->
      for x in ts do
        findRows x
    | _ -> ()
  findRows t
  let rowVarName (x: Ty) =
    let mutable found = -1
    for i in 0 .. Buffer.length rowVars - 1 do
      if found < 0 && sameVar v rowVars.[i] x then
        found <- i
    // (one not found, a row shown as a type, is 'e0, as in the F# compiler)
    if found = 0 then "'e" else $"'e{found + 1}"
  // arg: the row of an argument's last arrow, which shows <> when empty
  let rec rowText (arg: bool) (r: Ty) : string =
    let (ls, tail) = rowParts v r
    let labels = List.map (show false) ls
    let tailText =
      match prune v tail with
      | TCon("$total", []) -> None
      | x when hidden x -> None
      | x -> Some(rowVarName x)
    match (labels, tailText) with
    | ([], None) when arg && not full && isRowEmpty v r -> "<>"
    | ([], None) -> ""
    | ([ l ], None) -> l
    | ([], Some x) -> x
    | (ls, None) -> "<" + String.join ", " ls + ">"
    | (ls, Some x) -> "<" + String.join ", " ls + " | " + x + ">"
  // arg: t is a function type in argument position
  and show (arg: bool) (t: Ty) : string =
    match prune v t with
    | TFun(a, b, r) ->
      let last =
        match prune v b with
        | TFun _ -> false
        | _ -> true
      let effects = rowText (arg && last) r
      let param =
        match prune v a with
        | TFun _ -> "(" + show true a + ")"
        | _ -> show false a
      let result =
        match prune v b with
        | TFun _ when effects <> "" -> "(" + show arg b + ")"
        | TFun _ -> show arg b
        | _ -> show false b
      param + " -> " + result + (if effects = "" then "" else " / " + effects)
    | TCon("$ext", args) -> "<" + rowText false (TCon("$ext", args)) + ">"
    | TCon("$total", []) -> "<" + rowText false rowEmpty + ">"
    | TVar i when isRowKind (kindOf v i) -> rowVarName (TVar i)
    | x -> showOne x
  // one type constructor's text
  and showOne (t: Ty) : string =
    match t with
    | TMeas _ ->
      let (us, vs) = normMeas v t
      let term (name: string) (e: int) = if e = 1 || e = -1 then name else $"{name}^{if e < 0 then -e else e}"
      let parts = List.append (List.map (fun (u, e) -> (term u e, e)) us) (List.map (fun (x, e) -> (term (show false x) e, e)) vs)
      let pos = List.map fst (List.filter (fun (_, e) -> e > 0) parts)
      let neg = List.map fst (List.filter (fun (_, e) -> e < 0) parts)
      match (pos, neg) with
      | ([], []) -> "1"
      | (_, []) -> String.join " " pos
      | ([], _) -> "1/" + String.join " " neg
      | _ -> String.join " " pos + "/" + String.join " " neg
    | TCon(n, []) when isDynName n && not full -> "dyn " + shortName (String.sub n 4 (String.length n - 4))
    | TCon(n, args) ->
      let n = if full then n else shortName n
      if List.isEmpty args then n else n + "<" + String.join ", " (List.map (show false) args) + ">"
    | TFun _ -> show false t
    | TTuple ts ->
      let part (x: Ty) =
        match prune v x with
        | TTuple _
        | TFun _ -> "(" + show false x + ")"
        | _ -> show false x
      String.join " * " (List.map part ts)
    | TGen i -> "'" + String.ofByte (u8 (97 + i))
    | TVar i ->
      match v.links.[i] with
      | Some b -> show false b
      | None -> varName v i
  show false t

let show (v: Vars) (t: Ty) : string = showWith v false t

let showFull (v: Vars) (t: Ty) : string = showWith v true t

/// A function type's effects in words, for hover and zs doc (0025): what it handles from each
/// function argument (the labels of the argument's row beyond its own, in order), which arguments
/// must perform nothing, and what it performs; "" when no argument's row says anything. `names`
/// are the parameters' names, as the definition has them.
let explain (v: Vars) (names: list<string>) (t: Ty) : string =
  let labelsOf (r: Ty) = List.map (show v) (fst (rowParts v r))
  let rec spine (t: Ty) : list<Ty> =
    match prune v t with
    | TFun(a, b, _) -> a :: spine b
    | _ -> []
  let own =
    match lastRow v t with
    | Some r -> labelsOf r
    | None -> []
  // the multiset difference, in xs's order
  let rec beyond (xs: list<string>) (ys: list<string>) : list<string> =
    match xs with
    | [] -> []
    | x :: rest when List.contains x ys ->
      let i = List.findIndex (fun y -> y = x) ys
      beyond rest (List.removeAt i ys)
    | x :: rest -> x :: beyond rest ys
  let handles = Buffer.empty
  let pureArgs = Buffer.empty
  let mutable i = 0
  for a in spine t do
    let name =
      match List.tryItem i names with
      | Some n -> n
      | None -> "the argument"
    match lastRow v a with
    | Some r when isRowEmpty v r -> Buffer.push (name + " must perform nothing") pureArgs
    | Some r ->
      match beyond (labelsOf r) own with
      | [] -> ()
      | ls -> Buffer.push ("handles " + String.join ", " ls + " from " + name) handles
    | None -> ()
    i <- i + 1
  if Buffer.length handles = 0 && Buffer.length pureArgs = 0 then
    ""
  else
    let performs = if List.isEmpty own then [] else [ "performs " + String.join ", " own ]
    String.join ", " (List.concat [ Array.toList (Buffer.toArray handles); Array.toList (Buffer.toArray pureArgs); performs ])
