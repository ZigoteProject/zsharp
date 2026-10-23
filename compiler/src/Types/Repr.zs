/// How values of a type are held: whether they hold a reference count, whether a union is a plain
/// value or a heap cell, and what keeps a type from crossing threads (the Share trait).
open Ty
open Vars
open Show

// whether a value of the type holds a reference count, directly or in a field; `visiting`: the
// unions being looked through, so a recursive union is found (and stays boxed)
let rec private heapIn (v: Vars) (types: Map<string, TypeInfo>) (visiting: Set<string>) (t: Ty) : bool =
  match prune v t with
  | TCon("string", _)
  | TCon("array", _)
  | TCon("Buffer", _)
  | TCon("span", _)
  | TCon("weak", _)
  | TFun _ -> true
  | TCon(n, _) when isCellType n -> true
  | TCon("share", [ f ]) -> heapIn v types visiting f
  | TCon("fixed", [ el; _ ]) -> heapIn v types visiting el
  | TCon(n, _) when isDynName n -> true
  | TCon(n, args) ->
    match Map.tryFind n types with
    | Some { def = UnionDef _ } -> Set.contains n visiting || not (plainUnionIn v types visiting t)
    | Some { def = RecordDef fs } -> List.exists (fun (_, ft) -> heapIn v types visiting (Norm.substGen v args ft)) fs
    | _ -> false
  | TTuple ts -> List.exists (heapIn v types visiting) ts
  | _ -> false

// a union kept as a plain value ({ tag, fields }) instead of a heap cell: not recursive, at most 4
// fields over all its cases, none of them holding a reference count (option<int>, result<int,
// f64>, enums, small state machines); others are boxed
and private plainUnionIn (v: Vars) (types: Map<string, TypeInfo>) (visiting: Set<string>) (t: Ty) : bool =
  match prune v t with
  | TCon(n, args) ->
    match Map.tryFind n types with
    | Some { def = UnionDef cs } ->
      let fields = List.collect (fun (_, fs) -> List.map (Norm.substGen v args) fs) cs
      List.length fields <= 4 && List.forall (fun ft -> not (heapIn v types (Set.add n visiting) ft)) fields
    | _ -> false
  | _ -> false

/// Whether a value of the type holds a reference count (directly or in a field).
let needsRc (v: Vars) (types: Map<string, TypeInfo>) (t: Ty) : bool = heapIn v types Set.empty t

/// Whether a union is a plain value rather than a heap cell.
let plainUnion (v: Vars) (types: Map<string, TypeInfo>) (t: Ty) : bool = plainUnionIn v types Set.empty t

/// What keeps a type's values from being shared between threads (the Share trait, DESIGN §7):
/// None when they can be. Numbers, strings and the like, share<F> functions, the values threads
/// share (Atomic, Mutex, Channel), and records, unions, tuples and arrays of those can; ref,
/// Buffer, weak, dyn, C pointers and other functions can't. A type variable goes to onVar (the
/// checker requires Share of it).
let rec shareBlocker (v: Vars) (onVar: Ty -> unit / 'e) (types: Map<string, TypeInfo>) (visiting: Set<string>) (t: Ty) : option<Ty> / 'e =
  let inner = shareBlocker v onVar types
  match prune v t with
  | TVar i ->
    onVar (TVar i)
    None
  | TCon(n, []) when hasBuiltinImpl "Share" n -> None
  | TCon("fixed", [ el; _ ]) -> inner visiting el
  | TCon(n, [ TMeas _ ]) when Set.contains n nums -> None
  | TMeas _ -> None
  | TCon("share", _)
  | TCon("fnptr", _)
  | TCon("Atomic", _) -> None
  | TCon("array", [ el ])
  | TCon("Mutex", [ el ])
  | TCon("Channel", [ el ]) -> inner visiting el
  | TCon(n, args) when not (isDynName n) && Option.isNone (builtinCons n) ->
    let key = showFull v (TCon(n, args))
    if Set.contains key visiting then
      // recursive: Share if the rest of it is
      None
    else
      match Map.tryFind n types with
      | Some { def = RecordDef fs } -> List.tryPick (fun (_, ft) -> inner (Set.add key visiting) (Norm.substGen v args ft)) fs
      | Some { def = UnionDef cs } ->
        List.tryPick (fun (_, fs) -> List.tryPick (fun ft -> inner (Set.add key visiting) (Norm.substGen v args ft)) fs) cs
      | None -> Some(TCon(n, args))
  | TTuple ts -> List.tryPick (inner visiting) ts
  | x -> Some x

/// How a union's values are represented.
type UnionRep =
  /// a value: { tag, every case's fields } (small, not recursive, no heap data)
  | Plain
  /// two cases, one without fields and one whose single field is a pointer: that field itself, or
  /// a static object for the other case (so `Some s` allocates nothing for option<string>): the
  /// tag of the case without, and the field's type
  | Niche of int * Ty
  /// heap cells for the cases with fields, with a tag in the cell only when there are several
  /// such cases (whether there is); a case without fields is a static cell, told apart by its
  /// address
  | Boxed of bool

let private cases (v: Vars) (types: Map<string, TypeInfo>) (t: Ty) : option<list<string * list<Ty>>> =
  match prune v t with
  | TCon(n, args) ->
    match Map.tryFind n types with
    | Some { def = UnionDef cs } -> Some(List.map (fun (c, fs) -> (c, List.map (Norm.substGen v args) fs)) cs)
    | _ -> None
  | _ -> None

// two cases, one without fields and one with a single field (option's shape): the tag of the one
// without, and the field's type
let private nicheShaped (cs: list<string * list<Ty>>) : option<int * Ty> =
  match cs with
  | [ (_, []); (_, [ f ]) ] -> Some(0, f)
  | [ (_, [ f ]); (_, []) ] -> Some(1, f)
  | _ -> None

/// How a union type's values are represented.
let unionRep (v: Vars) (types: Map<string, TypeInfo>) (t: Ty) : UnionRep =
  // an object that can't be the static one standing for a niche's empty case: a union of
  // option's shape may be that one, so it never is a niche's payload (option<option<string>>
  // boxes its outer Some)
  let rec pointer (f: Ty) =
    match prune v f with
    | TCon("string", _)
    | TCon("array", _)
    | TCon("Buffer", _)
    | TCon("weak", _)
    | TFun _ -> true
    | TCon(n, _) when isCellType n -> true
    | TCon("share", [ g ]) -> pointer g
    | TCon(n, _) when isDynName n -> true
    | g ->
      match cases v types g with
      | Some cs -> Option.isNone (nicheShaped cs) && not (plainUnion v types g)
      | None -> false
  if plainUnion v types t then
    Plain
  else
    let cs = Option.get (cases v types t)
    match nicheShaped cs with
    | Some(noneTag, f) when pointer f -> Niche(noneTag, f)
    | _ -> Boxed(List.length (List.filter (fun (_, fs) -> not (List.isEmpty fs)) cs) > 1)

/// The shape of the cell a boxed union's case is built in (with a tag?, its field types), which
/// reuse must match; None for a case that isn't a cell.
let cellShape (v: Vars) (types: Map<string, TypeInfo>) (t: Ty) (tag: int) : option<bool * list<Ty>> =
  match (unionRep v types t, cases v types t) with
  | (Boxed tagged, Some cs) when not (List.isEmpty (snd (List.item tag cs))) -> Some(tagged, snd (List.item tag cs))
  | _ -> None
