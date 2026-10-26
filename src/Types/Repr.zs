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
      | Some { def = CUnionDef cs } -> List.tryPick (fun (_, ft) -> inner (Set.add key visiting) ft) cs
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

/// The machine word's bytes on a target (its triple, "" for the host): 4 on a Cortex-M and
/// wasm32, else 8.
let wordBytes (target: string) : int = if String.startsWith "thumb" target || String.startsWith "wasm32" target then 4 else 8

// the size and alignment of a C struct of these parts (each a size and an alignment): each part
// at its alignment, the whole padded to the strictest
let private structOf (parts: list<int * int>) : int * int =
  let mutable size = 0
  let mutable align = 1
  for (s, a) in parts do
    size <- (size + a - 1) / a * a + s
    align <- max align a
  ((size + align - 1) / align * align, align)

/// A value's size and alignment in bytes as code generation lays it out (DESIGN §5.1), with a
/// machine word of `word` bytes: a number its own (int and usize the word), a heap value, a
/// function or a pointer the word, a span three words, records and tuples as C lays out a struct
/// of their fields ([<CLayout>] ones are), a plain union its tag then every case's fields, a boxed
/// one a pointer, fixed<T, N> N elements, a vector its size; None for a type with a variable in
/// it (a generic function's, known after monomorphization).
let rec layout (v: Vars) (types: Map<string, TypeInfo>) (word: int) (t: Ty) : option<int * int> =
  let all (ts: list<Ty>) : option<list<int * int>> =
    List.fold (fun acc x -> Option.bind (fun xs -> Option.map (fun y -> y :: xs) (layout v types word x)) acc) (Some []) (List.rev ts)
  let pointer = Some(word, word)
  match prune v t with
  | TCon("int", [])
  | TCon("usize", []) -> Some(word, word)
  | TCon(n, [ TMeas _ ]) when Set.contains n nums -> layout v types word (TCon(n, []))
  | TCon("i64", [])
  | TCon("u64", [])
  | TCon("f64", []) -> Some(8, 8)
  | TCon("i32", [])
  | TCon("u32", [])
  | TCon("f32", [])
  | TCon("char", []) -> Some(4, 4)
  | TCon("i16", [])
  | TCon("u16", []) -> Some(2, 2)
  | TCon("i8", [])
  | TCon("u8", [])
  | TCon("bool", []) -> Some(1, 1)
  | TCon("unit", []) -> Some(0, 1)
  | TCon(n, []) when isVectorName n ->
    let (e, k) = Option.get (vectorInfo n)
    Option.map (fun (s, _) -> (s * k, s * k)) (layout v types word (TCon(e, [])))
  | TCon(n, []) when isMaskName n ->
    // <k x i1>: k bits, a byte at least
    let k = snd (List.find (fun (m, _) -> m = n) maskTypes)
    Some(max 1 (k / 8), max 1 (k / 8))
  | TCon("span", [ _ ]) -> Some(3 * word, word)
  | TCon("fixed", [ el; TCon(n, []) ]) ->
    let count : option<int> = Int.parse n
    match (layout v types word el, count) with
    | (Some(s, a), Some k) -> Some(s * k, a)
    | _ -> None
  | TCon(n, _) when isDynName n -> pointer
  | TCon(n, args) when Map.containsKey n types ->
    match (Map.find n types).def with
    | RecordDef fs -> Option.map structOf (all (List.map (fun (_, ft) -> Norm.substGen v args ft) fs))
    // a C union: its largest case, at the strictest alignment
    | CUnionDef cs ->
      let union (parts: list<int * int>) =
        let align = List.fold (fun m (_, a) -> max m a) 1 parts
        let size = List.fold (fun m (s, _) -> max m s) 0 parts
        ((size + align - 1) / align * align, align)
      Option.map union (all (List.map snd cs))
    | UnionDef cs ->
      if List.exists (fun x -> Option.isNone (layout v types word x)) args then None
      else if plainUnion v types t then
        // the tag (a byte for an enum, as code generation's tagTy), then every case's fields
        let tag = if List.length cs <= 256 && List.forall (fun (_, fs) -> List.isEmpty fs) cs then (1, 1) else (4, 4)
        Option.map (fun ps -> structOf (tag :: ps)) (all (List.collect (fun (_, fs) -> List.map (Norm.substGen v args) fs) cs))
      else
        pointer
  // string, array, ref, weak, Buffer, share, the C pointers, Atomic, Mutex, Channel: a pointer
  // whatever their arguments
  | TCon _
  | TFun _ -> pointer
  | TTuple ts -> Option.map structOf (all ts)
  | _ -> None

/// The offset in bytes of a record's field `index` (offsetof), as `layout` lays the record out;
/// None while a type variable is in a field before it.
let offsetOf (v: Vars) (types: Map<string, TypeInfo>) (word: int) (t: Ty) (index: int) : option<int> =
  match prune v t with
  | TCon(n, args) ->
    match Map.tryFind n types with
    | Some { def = RecordDef fs } when index < List.length fs ->
      let before = List.map (fun (_, ft) -> layout v types word (Norm.substGen v args ft)) (List.take (index + 1) fs)
      if List.exists Option.isNone before then
        None
      else
        // where the fields before it end, each at its alignment; it starts at the next multiple
        // of its own
        let parts = List.map Option.get before
        let ends = List.fold (fun (at: int) (s, a) -> (at + a - 1) / a * a + s) 0 (List.take index parts)
        let align = snd (List.item index parts)
        Some((ends + align - 1) / align * align)
    | _ -> None
  | _ -> None

/// The shape of the cell a boxed union's case is built in (with a tag?, its field types), which
/// reuse must match; None for a case that isn't a cell.
let cellShape (v: Vars) (types: Map<string, TypeInfo>) (t: Ty) (tag: int) : option<bool * list<Ty>> =
  match (unionRep v types t, cases v types t) with
  | (Boxed tagged, Some cs) when not (List.isEmpty (snd (List.item tag cs))) -> Some(tagged, snd (List.item tag cs))
  | _ -> None
