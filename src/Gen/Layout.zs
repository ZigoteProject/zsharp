/// Code generation's context and the shapes of values (the F# compiler's Codegen, its first part):
/// each type's LLVM type, a union's cells, the C ABI, and the instructions most code needs (string
/// constants, checks, intrinsics, SIMD and checked arithmetic).
//
// Representation (every heap object starts with a word-sized reference count; 0 = static, never
// freed). W is the machine word: i64, or i32 on a 32-bit chip (written i_W, resolved at the end):
//   int/usize W, i64/u64 i64, i32/u32 i32, i16/u16 i16, i8/u8 i8, f64 double, f32 float, bool i1,
//   unit {} (value: zeroinitializer), cstr ptr
//   string   ptr -> { W rc, W len, [len+1 x i8] }
//   array<T> ptr -> { W rc, W len, [len x T] }
//   ref<T>   ptr -> { W rc, T }
//   union    ptr -> { W rc, i32 tag, field... } for a case with fields (no tag when it's the only
//            such case); a case without fields is a static cell, told apart by its address. Two
//            cases, one without fields and one with a single pointer field (option<string>): the
//            field itself, or @zs.none
//   closure  ptr -> { W rc, ptr code, ptr info, env... }; code: (ptr self, arg) -> result;
//            info -> { ptr drop, i32 arity, ptr full }: the parameters it still takes, and code
//            taking all of them at once, full: (ptr self, args...) -> result
//   tuples and records: LLVM struct values; so are small non-recursive unions without heap data
//   (an i32 tag, or an i8 one for an enum, then every case's fields)
open Types.Ty
open Types.Repr
open Core.Ir
open Core.Program
open Emit

/// What code generation keeps for a module: the program's types and C functions, the build's
/// options, the text made so far (the declarations at the top, the helper functions, the
/// functions), what's been generated (by name), the string constants, the functions by name, the
/// functions it calls (in the order first called), the unions' representations, the LLVM types
/// and unions' cases made so far (asked for at nearly every instruction), and the debug
/// metadata. One heap cell, read field by field.
type G =
  | G of GData

and GData =
  { types: Map<string, TypeInfo>
    externs: Map<string, ExternSig>
    opts: Options
    v: Types.Vars.Vars
    part: option<Part>
    /// the linkage of what has one address in the whole program
    shared: string
    top: Buffer<string>
    helpers: Buffer<string>
    funcs: Buffer<string>
    generated: ref<Set<string>>
    strings: ref<Map<string, string>>
    fnTable: Map<string, MFun>
    referenced: ref<Set<string>>
    referencedOrder: Buffer<string>
    reps: ref<Map<Ty, UnionRep>>
    lltys: ref<Map<Ty, string>>
    unions: ref<Map<Ty, string * list<string * list<Ty>>>>
    md: Buffer<string>
    mdCount: ref<int>
    diFiles: ref<Map<string, string>>
    locs: ref<Map<string, string>>
    diTypes: ref<Map<string, string>>
    lenRange: ref<option<string>>
    compileUnit: ref<option<string>>
    noTypes: ref<option<string>>
    /// main's file, the debug info's compile unit's
    mainFile: string
    /// what the program can't be compiled for, the first found: a line and a message
    failure: ref<option<int * string>> }

type G with
  member g.types =
    match g with
    | G { types = x } -> x
  member g.externs =
    match g with
    | G { externs = x } -> x
  member g.opts =
    match g with
    | G { opts = x } -> x
  member g.v =
    match g with
    | G { v = x } -> x
  member g.part =
    match g with
    | G { part = x } -> x
  member g.shared =
    match g with
    | G { shared = x } -> x
  member g.top =
    match g with
    | G { top = x } -> x
  member g.helpers =
    match g with
    | G { helpers = x } -> x
  member g.funcs =
    match g with
    | G { funcs = x } -> x
  member g.generated =
    match g with
    | G { generated = x } -> x
  member g.strings =
    match g with
    | G { strings = x } -> x
  member g.fnTable =
    match g with
    | G { fnTable = x } -> x
  member g.referenced =
    match g with
    | G { referenced = x } -> x
  member g.referencedOrder =
    match g with
    | G { referencedOrder = x } -> x
  member g.reps =
    match g with
    | G { reps = x } -> x
  member g.lltys =
    match g with
    | G { lltys = x } -> x
  member g.unions =
    match g with
    | G { unions = x } -> x
  member g.md =
    match g with
    | G { md = x } -> x
  member g.mdCount =
    match g with
    | G { mdCount = x } -> x
  member g.diFiles =
    match g with
    | G { diFiles = x } -> x
  member g.locs =
    match g with
    | G { locs = x } -> x
  member g.diTypes =
    match g with
    | G { diTypes = x } -> x
  member g.lenRange =
    match g with
    | G { lenRange = x } -> x
  member g.compileUnit =
    match g with
    | G { compileUnit = x } -> x
  member g.noTypes =
    match g with
    | G { noTypes = x } -> x
  member g.mainFile =
    match g with
    | G { mainFile = x } -> x
  member g.failure =
    match g with
    | G { failure = x } -> x

/// Whether this is the first time the name is generated (it's remembered).
let firstTime (g: G) (name: string) : bool =
  if Set.contains name g.generated.Value then
    false
  else
    g.generated.Value <- Set.add name g.generated.Value
    true

/// A line at the module's top (declarations, constants).
let topLine (g: G) (s: string) = Buffer.push (s + "\n") g.top

/// A helper function's text.
let helper (g: G) (s: string) = Buffer.push s g.helpers

/// A function's symbol (remembered as called by this module).
let sym (g: G) (f: string) : string =
  if not (Set.contains f g.referenced.Value) then
    g.referenced.Value <- Set.add f g.referenced.Value
    Buffer.push f g.referencedOrder
  "@\"zs." + f + "\""

/// Whether a value of the type holds a reference count.
let heap (g: G) (t: Ty) : bool = needsRc g.v g.types t

let isArm64 (g: G) : bool = g.opts.arch = "aarch64"

/// Windows: the Microsoft x64 convention on x86-64 (on arm64, Windows's is AAPCS64's for
/// structs), LLP64.
let isWindows (g: G) : bool = String.contains "-windows" g.opts.target

/// The machine word (int, usize, reference counts, lengths): 32 bits on a Cortex-M and wasm32,
/// else 64.
let is32 (g: G) : bool = word32 g.opts.target

/// WebAssembly's C ABI: a struct of one scalar as that scalar, any other by a pointer to a copy
/// (byval), returned through an sret pointer.
let isWasm (g: G) : bool = String.startsWith "wasm" g.opts.target

let pointerBytes (g: G) : int = if is32 g then 4 else 8

let wordTy (g: G) : string = if is32 g then "i32" else "i64"

/// A number written in decimal.
let toInt (s: string) : int =
  let n : option<int> = Int.parse s
  Option.get n

let substGen (g: G) (args: list<Ty>) (t: Ty) : Ty = Types.Norm.substGen g.v args t

/// A type as messages show it.
let showT (g: G) (t: Ty) : string = Types.Show.show g.v t

/// A type in full, as names made from it show it (dup.T, drop.T).
let showF (g: G) (t: Ty) : string = Types.Show.showFull g.v t

/// Whether the type named n is a union.
let isUnionType (g: G) (n: string) : bool =
  match Map.tryFind n g.types with
  | Some { def = UnionDef _ } -> true
  | _ -> false

/// Whether the type named n is a record.
let isRecordType (g: G) (n: string) : bool =
  match Map.tryFind n g.types with
  | Some { def = RecordDef _ } -> true
  | _ -> false

/// A C union's cases (0004), when the type is one.
let cUnion (g: G) (t: Ty) : option<list<string * Ty>> =
  match t with
  | TCon(n, []) ->
    match Map.tryFind n g.types with
    | Some { def = CUnionDef cs } -> Some cs
    | _ -> None
  | _ -> None

/// A plain union's tag: a byte for an enum (no case has fields, so the tag is all there is, and an
/// array of them is a byte per element), else an i32: next to fields a byte saves no space, and on
/// a 32-bit chip it costs an extension at each test.
let tagTy (cases: list<string * list<Ty>>) : string =
  if List.length cases <= 256 && List.forall (fun (_, fs) -> List.isEmpty fs) cases then "i8" else "i32"

// the types whose values are pointers to objects (or C pointers)
let private pointers : Set<string> = Set.ofList [ "cstr"; "cptr"; "string"; "array"; "ref"; "weak"; "ptr"; "fnptr"; "Atomic"; "Mutex"; "Channel"; "Spsc" ]

// a mask's lanes
let private maskLanes (n: string) : int = snd (List.find (fun (m, _) -> m = n) maskTypes)

/// A type's LLVM type.
let rec llty (g: G) (t: Ty) : string =
  match t with
  // the machine word
  | TCon("int", [])
  | TCon("usize", []) -> wordTy g
  | TCon("i64", [])
  | TCon("u64", []) -> "i64"
  | TCon("i32", [])
  | TCon("u32", [])
  | TCon("char", []) -> "i32"
  | TCon("i16", [])
  | TCon("u16", []) -> "i16"
  | TCon("i8", [])
  | TCon("u8", []) -> "i8"
  | TCon("f64", []) -> "double"
  | TCon("f32", []) -> "float"
  | TCon("bool", []) -> "i1"
  | TCon("unit", []) -> "{}"
  | TCon(n, []) when isVectorName n ->
    let (e, k) = Option.get (vectorInfo n)
    $"<{k} x {llty g (tcon e)}>"
  | TCon(n, []) when isMaskName n -> $"<{maskLanes n} x i1>"
  | TCon(n, _) when Set.contains n pointers -> "ptr"
  | TFun _ -> "ptr"
  | TCon(n, _) when isDynName n -> "ptr"
  // N elements inline
  | TCon("fixed", [ el; TCon(n, []) ]) -> $"[{n} x {llty g el}]"
  | TCon _
  | TTuple _ ->
    match Map.tryFind t g.lltys.Value with
    | Some s -> s
    | None ->
      let s = lltyOf g t
      g.lltys.Value <- Map.add t s g.lltys.Value
      s
  | other -> panic $"llty: unresolved type {showT g other}"

// a record's, a union's, a C union's or a tuple's LLVM type, made (llty keeps it)
and private lltyOf (g: G) (t: Ty) : string =
  match t with
  | TCon(n, args) ->
    let info = Map.find n g.types
    match info.def with
    // a [<Bits>] record is the integer its fields are ranges of (0013)
    | RecordDef _ when Option.isSome info.bits -> $"i{(Option.get info.bits).width}"
    | RecordDef fs -> structTy g (List.map (fun (_, ft) -> substGen g args ft) fs)
    | UnionDef cs ->
      if plainUnion g.v g.types t then
        // a plain union: the tag, then every case's fields in order (cases don't overlap)
        "{ " + tagTy cs + String.concat (List.map (fun ft -> ", " + llty g (substGen g args ft)) (List.collect snd cs)) + " }"
      else
        "ptr"
    | CUnionDef cs ->
      // as clang lays a C union out: its case aligned most strictly (the largest of those), then
      // bytes to the union's size
      let sa (ft: Ty) = Option.get (Types.Repr.layout g.v g.types (pointerBytes g) ft)
      let better (a: Ty) (b: Ty) = snd (sa b) > snd (sa a) || (snd (sa b) = snd (sa a) && fst (sa b) > fst (sa a))
      let storage = List.fold (fun (best: Ty) (_, ft) -> if better best ft then ft else best) (snd (List.head cs)) cs
      let pad = fst (sa t) - fst (sa storage)
      "{ " + llty g storage + (if pad > 0 then $", [{pad} x i8]" else "") + " }"
  | TTuple ts -> structTy g ts
  | other -> panic $"llty: unresolved type {showT g other}"

and structTy (g: G) (ts: list<Ty>) : string = "{ " + String.join ", " (List.map (llty g) ts) + " }"

/// A type's name when it has no arguments, else "".
let tyName (t: Ty) : string =
  match t with
  | TCon(n, []) -> n
  | _ -> ""

/// Whether a type is a window (a span after monomorphization: Core's windowType).
let isWin (t: Ty) : bool =
  match t with
  | TCon(n, _) -> n = windowType
  | _ -> false

/// A Buffer after monomorphization: a ref to Core's bufferType record.
let isBuf (t: Ty) : bool =
  match t with
  | TCon("ref", [ TCon(n, [ _ ]) ]) -> n = bufferType
  | _ -> false

let isFloat (t: Ty) : bool = Set.contains (tyName t) floats

let isUnsigned (t: Ty) : bool = Set.contains (tyName t) unsigned

/// A Z# object C holds as an opaque handle: reference counted, a pointer, not a string.
let isHandle (g: G) (t: Ty) : bool = heap g t && llty g t = "ptr" && tyName t <> "string"

/// A union type's name and cases (their field types instantiated), each type's made once.
let union (g: G) (t: Ty) : string * list<string * list<Ty>> =
  match Map.tryFind t g.unions.Value with
  | Some u -> u
  | None ->
    let made =
      match t with
      | TCon(u, args) ->
        match (Map.find u g.types).def with
        | UnionDef cs -> (u, List.map (fun (n, fs) -> (n, List.map (substGen g args) fs)) cs)
        | RecordDef _
        | CUnionDef _ -> panic "not a union"
      | _ -> panic "not a union"
    g.unions.Value <- Map.add t made g.unions.Value
    made

/// Where case `tag`'s field j sits in a plain union's struct: after the tag and the earlier cases'
/// fields.
let plainField (g: G) (t: Ty) (tag: int) (j: int) : int =
  let (_, cs) = union g t
  1 + List.sumBy (fun (_, fs) -> List.length fs) (List.take tag cs) + j

/// A union type's representation.
let repOf (g: G) (t: Ty) : UnionRep =
  match Map.tryFind t g.reps.Value with
  | Some r -> r
  | None ->
    let r = unionRep g.v g.types t
    g.reps.Value <- Map.add t r g.reps.Value
    r

/// A union type's representation; None for other types.
let repOfUnion (g: G) (t: Ty) : option<UnionRep> =
  match t with
  | TCon(n, _) ->
    match Map.tryFind n g.types with
    | Some { def = UnionDef _ } -> Some(repOf g t)
    | _ -> None
  | _ -> None

let isNiche (g: G) (t: Ty) : bool =
  match repOf g t with
  | Niche _ -> true
  | _ -> false

/// Whether a boxed union's cells have a tag.
let tagged (g: G) (t: Ty) : bool =
  match repOfUnion g t with
  | Some(Boxed true) -> true
  | _ -> false

/// Whether a boxed union's cells have a tag word of their own, after the header: on a 32-bit
/// target, whose header word is the count. A 64-bit header word holds the tag (DESIGN §5.1).
let tagWord (g: G) (t: Ty) : bool = tagged g t && is32 g

/// The cell of a boxed union's case: the header word, the tag's own word when tagWord, then the
/// fields.
let cellTy (g: G) (t: Ty) (tag: int) : string =
  let fields = snd (List.item tag (snd (union g t)))
  "{ i_W" + (if tagWord g t then ", i32" else "") + String.concat (List.map (fun f -> ", " + llty g f) fields) + " }"

/// Field j's index in a case's cell.
let cellField (g: G) (t: Ty) (j: int) : int = j + (if tagWord g t then 2 else 1)

/// Where the tag of the cell at p is, and its type: bytes 4 and 5 of the header word (after the
/// 32-bit count; byte 6 is the runtime's), or its own word on a 32-bit target.
let tagAt (g: G) (em: Emitter) (p: string) : string * string =
  if is32 g then (instr em $"getelementptr {{ i_W, i32 }}, ptr {p}, i32 0, i32 1", "i32") else (instr em $"getelementptr i8, ptr {p}, i_W 4", "i16")

/// The tag of the cell at p, as an i32 (below cases, when given).
let loadTag (g: G) (em: Emitter) (p: string) (cases: option<int>) : string =
  let (tp, ty) = tagAt g em p
  let range =
    match cases with
    | Some n -> $", !range !{{{ty} 0, {ty} {n}}}"
    | None -> ""
  let v = instr em $"load {ty}, ptr {tp}{range}"
  if ty = "i32" then v else instr em $"zext {ty} {v} to i32"

let storeTag (g: G) (em: Emitter) (p: string) (tag: int) =
  let (tp, ty) = tagAt g em p
  emit em $"store {ty} {tag}, ptr {tp}"

/// A case without fields of a boxed union: a static cell (count 0, so never freed) with the tag
/// when the union's cells have one. A match tells it apart by its address.
let nullary (g: G) (t: Ty) (tag: int) : string =
  let (u, _) = union g t
  let name = $"@\"ctor.{u}.{tag}\""
  if firstTime g name then
    // not unnamed_addr: the address is what's compared
    if tagWord g t then
      topLine g $"{name} = {g.shared} constant {{ i_W, i32 }} {{ i_W 0, i32 {tag} }}"
    else if tagged g t then
      topLine g $"{name} = {g.shared} constant {{ i32, i16, i16 }} {{ i32 0, i16 {tag}, i16 0 }}"
    else
      topLine g $"{name} = {g.shared} constant {{ i_W }} {{ i_W 0 }}"
  name

let cloTy (g: G) (env: list<Ty>) : string = "{ i_W, ptr, ptr" + String.concat (List.map (fun f -> ", " + llty g f) env) + " }"

// ------------------------------------------------------------ C ABI (x86-64 System V, AAPCS64)

/// Size, alignment and scalar fields (offset, LLVM type) of a C-representable type.
let rec cLayout (g: G) (t: Ty) : int * int * list<int * string> =
  match llty g t with
  | "i1"
  | "i8" -> (1, 1, [ (0, "i8") ])
  | "i16" -> (2, 2, [ (0, "i16") ])
  | "i32" -> (4, 4, [ (0, "i32") ])
  | "float" -> (4, 4, [ (0, "float") ])
  | "i64" -> (8, 8, [ (0, "i64") ])
  | "double" -> (8, 8, [ (0, "double") ])
  | "ptr" -> (pointerBytes g, pointerBytes g, [ (0, "ptr") ])
  | _ ->
    match t with
    | TCon("fixed", [ el; TCon(n, []) ]) ->
      // C's T[N]: N elements, T's alignment
      let (sz, a, sc) = cLayout g el
      let k = toInt n
      (sz * k, a, List.collect (fun i -> List.map (fun (o, s) -> (i * sz + o, s)) sc) (List.init k (fun i -> i)))
    | TCon("fixed", _) -> panic $"cLayout: {showT g t}"
    | _ when Option.isSome (cUnion g t) ->
      // every case at offset 0, so all their scalars; the largest's size, the strictest alignment
      let parts = List.map (fun (_, ft) -> cLayout g ft) (Option.get (cUnion g t))
      let al = List.fold (fun m (_, a, _) -> max m a) 1 parts
      let size = List.fold (fun m (s, _, _) -> max m s) 0 parts
      ((size + al - 1) / al * al, al, List.collect (fun (_, _, sc) -> sc) parts)
    | _ ->
      let fs =
        match t with
        | TCon(n, _) ->
          match (Map.find n g.types).def with
          | RecordDef fs -> List.map snd fs
          | UnionDef _
          | CUnionDef _ -> []
        | _ -> []
      let off = ref 0
      let al = ref 1
      let scalars = Buffer.empty
      for ft in fs do
        let (sz, a, sc) = cLayout g ft
        off.Value <- (off.Value + a - 1) / a * a
        for (o, st) in sc do
          Buffer.push (off.Value + o, st) scalars
        off.Value <- off.Value + sz
        al.Value <- max al.Value a
      ((off.Value + al.Value - 1) / al.Value * al.Value, al.Value, Array.toList (Buffer.toArray scalars))

// a homogeneous aggregate (AAPCS's HFA) of 1-4 floats or 1-4 doubles: the kind and how many,
// counted by the size (a union's cases overlap)
let private hfaOf (size: int) (scalars: list<int * string>) : option<string * int> =
  match List.distinct (List.map snd scalars) with
  | [ k ] when k = "float" || k = "double" ->
    let n = size / (if k = "float" then 4 else 8)
    if n <= 4 then Some(k, n) else None
  | _ -> None

/// AAPCS64 (aarch64): an HFA goes in float registers as an array; up to 16 bytes in one or two
/// integer registers; anything bigger by reference.
let abiArm64 (g: G) (t: Ty) (isResult: bool) : Abi =
  let (size, _, scalars) = cLayout g t
  match hfaOf size scalars with
  | Some(k, n) -> Pieces [ $"[{n} x {k}]" ]
  | None ->
    if size > 16 then Memory
    else if size > 8 then Pieces [ "[2 x i64]" ]
    else if isResult then Pieces [ $"i{8 * size}" ]
    else Pieces [ "i64" ]

/// 32-bit Arm (a Cortex-M: thumb…), whose C ABI is AAPCS.
let isArm32 (g: G) : bool = String.startsWith "thumb" g.opts.target || String.startsWith "arm" g.opts.target

/// AAPCS, as clang lowers it: on a hard-float chip (eabihf, the VFP variant) a homogeneous
/// aggregate of 1-4 floats or doubles is passed and returned as itself, in float registers;
/// otherwise a struct is passed as words (i32s, or i64s when it's 8-byte aligned) in core
/// registers and then on the stack, one over 64 bytes as a copy (byval), and returned in r0 when
/// it fits in 4 bytes, else through an sret pointer.
let abiArm32 (g: G) (t: Ty) (isResult: bool) : Abi =
  let (size, align, scalars) = cLayout g t
  if Option.isSome (hfaOf size scalars) && String.endsWith "hf" g.opts.target then Pieces [ llty g t ]
  else if isResult then
    if size = 1 then Pieces [ "i8" ]
    else if size = 2 then Pieces [ "i16" ]
    else if size <= 4 then Pieces [ "i32" ]
    else Memory
  else if size > 64 then Memory
  else if align = 8 then Pieces [ $"[{(size + 7) / 8} x i64]" ]
  else Pieces [ $"[{(size + 3) / 4} x i32]" ]

/// Microsoft x64: a struct of 1, 2, 4 or 8 bytes as an integer that size, any other by a pointer
/// to a copy (or returned through an sret pointer).
let abiWin64 (g: G) (t: Ty) : Abi =
  let (size, _, _) = cLayout g t
  if size = 1 || size = 2 || size = 4 || size = 8 then Pieces [ $"i{8 * size}" ] else Memory

let abiFor (g: G) (t: Ty) (isResult: bool) : Abi =
  let lt = llty g t
  // unit ({}) has nothing to pass
  if not (String.startsWith "{" lt) || lt = "{}" then
    Scalar
  else if isArm64 g then
    abiArm64 g t isResult
  else if isArm32 g then
    abiArm32 g t isResult
  else if isWindows g then
    abiWin64 g t
  else if isWasm g then
    match cLayout g t with
    | (_, _, [ (_, s) ]) -> Pieces [ s ]
    | _ -> Memory
  else
    let (size, _, scalars) = cLayout g t
    if size > 16 then
      Memory
    else
      let eightbyte (k: int) =
        let here = List.filter (fun (o, _) -> o >= 8 * k && o < 8 * k + 8) scalars
        if List.forall (fun (_, s) -> s = "float" || s = "double") here then
          // SSE: a double, two floats or one (a union's cases are all here)
          if List.exists (fun (_, s) -> s = "double") here then "double"
          else if List.exists (fun (o, _) -> o = 8 * k + 4) here then "<2 x float>"
          else "float"
        else
          $"i{8 * min 8 (size - 8 * k)}"
      Pieces(List.map eightbyte (List.init ((size - 1) / 8 + 1) (fun k -> k)))

let abiOf (g: G) (t: Ty) : Abi = abiFor g t false

let cParam (g: G) (t: Ty) : string = if llty g t = "i1" then "i1 zeroext" else llty g t

/// How each parameter of a C function is passed. x86-64 System V: a struct goes in registers only
/// when all its eightbytes fit in the ones left (6 for integers, less one for an sret pointer, and
/// 8 for floating point); otherwise it goes on the stack whole, as a struct in memory does. A
/// scalar past the registers goes on the stack by itself, which LLVM does. AAPCS64's and AAPCS's
/// rules for the arrays they're given are LLVM's own (AAPCS splits one between the last core
/// registers and the stack), as Microsoft x64's four slots by position are.
let cModes (g: G) (pars: list<Ty>) (sret: bool) : list<Abi> =
  let ints = ref (if sret then 5 else 6)
  let sses = ref 8
  let mode (t: Ty) : Abi =
    match t with
    | TCon("callback", _)
    | TCon("span", _) ->
      ints.Value <- ints.Value - 2
      Scalar
    | TCon("unit", []) -> Scalar
    | _ ->
      match abiOf g t with
      | Scalar ->
        if llty g t = "double" || llty g t = "float" then sses.Value <- sses.Value - 1 else ints.Value <- ints.Value - 1
        Scalar
      | Pieces ps ->
        if isArm64 g || isArm32 g || isWindows g || isWasm g then
          Pieces ps
        else
          let ni = List.length (List.filter (fun (p: string) -> String.startsWith "i" p) ps)
          let ns = List.length ps - ni
          if ni <= ints.Value && ns <= sses.Value then
            ints.Value <- ints.Value - ni
            sses.Value <- sses.Value - ns
            Pieces ps
          else
            Memory
      | Memory -> Memory
  List.map mode pars

/// A struct passed in memory: x86-64 System V copies it onto the stack (byval); AAPCS64 and
/// Microsoft x64 pass a pointer to a copy the caller made.
let byval (g: G) (t: Ty) : string =
  let (_, a, _) = cLayout g t
  // AAPCS's stack slots are words: a copy is aligned to 4 at least
  if isArm64 g || isWindows g then "ptr" else $"ptr byval({llty g t}) align {(if isArm32 g then max 4 a else a)}"

/// LLVM return type for a C result, and whether it is returned through an sret pointer.
let cRet (g: G) (t: Ty) : string * bool =
  match t with
  | TCon("unit", []) -> ("void", false)
  | _ ->
    match abiFor g t true with
    | Scalar -> ((if llty g t = "i1" then "zeroext i1" else llty g t), false)
    | Pieces [ p ] -> (p, false)
    | Pieces ps -> ("{ " + String.join ", " ps + " }", false)
    | Memory -> ("void", true)

/// A struct in memory, read or written as its eightbytes (padded: a piece may be read whole past
/// a struct's last byte, such as an i_W for a 4-byte struct).
let slotFor (g: G) (em: Emitter) (t: Ty) : string =
  let slot = "%" + fresh em "abi"
  alloca em $"{slot} = alloca {{ {llty g t}, [16 x i8] }}, align 8"
  slot

let toPieces (g: G) (em: Emitter) (t: Ty) (v: string) (pieces: list<string>) : list<string * string> =
  let slot = slotFor g em t
  emit em $"store {llty g t} {v}, ptr {slot}"
  let piece (k: int) (pt: string) =
    let p = instr em $"getelementptr i8, ptr {slot}, i_W {8 * k}"
    (pt, instr em $"load {pt}, ptr {p}")
  List.mapi piece pieces

let fromPieces (g: G) (em: Emitter) (t: Ty) (pieces: list<string * string>) : string =
  let slot = slotFor g em t
  let piece (k: int) (pp: string * string) =
    let (pt, pv) = pp
    let p = instr em $"getelementptr i8, ptr {slot}, i_W {8 * k}"
    emit em $"store {pt} {pv}, ptr {p}"
  List.iteri piece pieces
  instr em $"load {llty g t}, ptr {slot}"

/// The LLVM parameter types (with attributes) a C parameter of this type becomes, passed so.
let cParamsAs (g: G) (t: Ty) (mode: Abi) : list<string> =
  match t with
  | TCon("callback", _) -> [ "ptr"; "ptr" ]
  // its data and its length (size_t)
  | TCon("span", _) -> [ "ptr"; "i_W" ]
  | TCon("unit", []) -> []
  | _ ->
    match mode with
    | Scalar -> [ cParam g t ]
    | Pieces ps -> ps
    | Memory -> [ byval g t ]

/// The LLVM parameters of a C function taking these (after an sret pointer, if it has one).
let cParamList (g: G) (pars: list<Ty>) (sret: bool) : list<string> = List.concat (List.map2 (cParamsAs g) pars (cModes g pars sret))

// ------------------------------------------------------------ instructions most code needs

let sizeOf (em: Emitter) (ty: string) : string =
  let p = instr em $"getelementptr {ty}, ptr null, i32 1"
  instr em $"ptrtoint ptr {p} to i_W"

// a string constant's bytes as LLVM writes them: printable ones as they are, others escaped
let private encoded (s: string) : string =
  let parts = Buffer.empty
  for i in 0 .. String.length s - 1 do
    let b = String.byte s i
    if b >= u8 32 && b < u8 127 && b <> u8 34 && b <> u8 92 then Buffer.push (String.ofByte b) parts else Buffer.push $"\\{b:X2}" parts
  joined parts

/// A string constant: a static string object (count 0).
let strGlobal (g: G) (s: string) : string =
  match Map.tryFind s g.strings.Value with
  | Some name -> name
  | None ->
    let n = String.length s
    let name = $"@.str.{Map.count g.strings.Value}"
    topLine g $"{name} = private unnamed_addr constant {{ i_W, i_W, [{n + 1} x i8] }} {{ i_W 0, i_W {n}, [{n + 1} x i8] c\"{encoded s}\\00\" }}"
    g.strings.Value <- Map.add s name g.strings.Value
    name

/// The bytes of a string literal, as a C string.
let cstrConst (g: G) (s: string) : string = $"getelementptr inbounds ({{ i_W, i_W, [{String.length s + 1} x i8] }}, ptr {strGlobal g s}, i32 0, i32 2)"

let panicWith (g: G) (em: Emitter) (msg: string) =
  emit em $"call void @zs_panic_c(ptr {cstrConst g msg})"
  emit em "unreachable"

/// Branches to a panic unless cond holds.
let check (g: G) (em: Emitter) (cond: string) (msg: string) =
  let ok = fresh em "ok"
  let bad = fresh em "fail"
  emit em $"br i1 {cond}, label %{ok}, label %{bad}"
  enter em bad
  panicWith g em msg
  enter em ok

/// A 64-bit value as a word-sized hash: itself, or on a 32-bit chip its halves xor'ed.
let foldWord (g: G) (em: Emitter) (v: string) : string =
  if is32 g then
    let hi = instr em $"lshr i64 {v}, 32"
    let x = instr em $"xor i64 {v}, {hi}"
    instr em $"trunc i64 {x} to i32"
  else
    v

/// A call to an LLVM intrinsic, declared the first time: name (llvm.sqrt.v4f32), result type,
/// typed arguments.
let intrinsic (g: G) (em: Emitter) (name: string) (ret: string) (args: list<string * string>) (flags: string) : string =
  let decl = $"declare {ret} @{name}(" + String.join ", " (List.map fst args) + ")"
  if firstTime g decl then
    helper g (decl + "\n")
  instr em ($"call {flags}{ret} @{name}(" + String.join ", " (List.map (fun (t, x) -> t + " " + x) args) + ")")

/// A SIMD type's element, lanes, their LLVM type (a mask's are i1), and LLVM's name for it in an
/// intrinsic's (v4f32).
let simdShape (g: G) (t: Ty) : string * int * string * string =
  let n = tyName t
  let (e, k) =
    match vectorInfo n with
    | Some(e, k) -> (e, k)
    | None -> ("bool", maskLanes n)
  let et = llty g (tcon e)
  let suffix =
    match et with
    | "float" -> "f32"
    | "double" -> "f64"
    | other -> other
  (e, k, et, $"v{k}{suffix}")

/// x in every lane of a <k x et>.
let splat (em: Emitter) (k: int) (et: string) (x: string) : string =
  let one = instr em $"insertelement <{k} x {et}> poison, {et} {x}, i32 0"
  instr em $"shufflevector <{k} x {et}> {one}, <{k} x {et}> poison, <{k} x i32> zeroinitializer"

/// Whether any lane of a <k x i1> is true.
let anyLane (g: G) (em: Emitter) (k: int) (m: string) : string = intrinsic g em $"llvm.vector.reduce.or.v{k}i1" "i1" [ ($"<{k} x i1>", m) ] ""

// the most negative value of a signed integer of these bits
let minOf (bits: int) : string = if bits = 64 then "-9223372036854775808" else $"{-(i64 1 <<< i64 (bits - 1))}"

/// + - * / % on SIMD vectors, lane by lane (integers wrap, as SIMD instructions do, and integer
/// division checks every lane's divisor), bitwise operators on integer vectors and masks (a
/// shift's amount, an int, for every lane), and = <> on whole vectors.
let simdBin (g: G) (em: Emitter) (op0: string) (t: Ty) (a: string) (b: string) (fast: bool) : string =
  let (e, k, et, _) = simdShape g t
  let lt = llty g t
  let isF = Set.contains e floats
  let uns = Set.contains e unsigned
  let op = if String.startsWith "wrap" op0 then String.sub op0 4 (String.length op0 - 4) else op0
  match op with
  | "="
  | "<>" ->
    let c = instr em $"{(if isF then "fcmp oeq" else "icmp eq")} {lt} {a}, {b}"
    let all = intrinsic g em $"llvm.vector.reduce.and.v{k}i1" "i1" [ ($"<{k} x i1>", c) ] ""
    if op = "=" then all else instr em $"xor i1 {all}, true"
  | "&&&" -> instr em $"and {lt} {a}, {b}"
  | "|||" -> instr em $"or {lt} {a}, {b}"
  | "^^^" -> instr em $"xor {lt} {a}, {b}"
  | "<<<"
  | ">>>" ->
    // modulo the lane's width, as for one integer
    let bits = toInt (String.sub et 1 (String.length et - 1))
    let w = llty g tInt
    let wbits = toInt (String.sub w 1 (String.length w - 1))
    let amount0 = if wbits = bits then b else if wbits > bits then instr em $"trunc {w} {b} to {et}" else instr em $"sext {w} {b} to {et}"
    let amount = instr em $"and {et} {amount0}, {bits - 1}"
    let ins = if op = "<<<" then "shl" else if uns then "lshr" else "ashr"
    let lanes = splat em k et amount
    instr em $"{ins} {lt} {a}, {lanes}"
  | _ when isF ->
    let f = Map.find op farith
    instr em $"{f}{(if fast then " fast" else "")} {lt} {a}, {b}"
  | "+"
  | "-"
  | "*" -> instr em $"{Map.find op arith} {lt} {a}, {b}"
  | _ ->
    // / and %: no lane divides by zero, nor MIN by -1 (which doesn't fit)
    let zero = instr em $"icmp eq {lt} {b}, zeroinitializer"
    let anyZero = anyLane g em k zero
    check g em (instr em $"xor i1 {anyZero}, true") "division by zero"
    if not uns then
      let bits = toInt (String.sub et 1 (String.length et - 1))
      let minLanes = splat em k et (minOf bits)
      let isMin = instr em $"icmp eq {lt} {a}, {minLanes}"
      let negLanes = splat em k et "-1"
      let isNeg1 = instr em $"icmp eq {lt} {b}, {negLanes}"
      let bad = instr em $"and <{k} x i1> {isMin}, {isNeg1}"
      let anyBad = anyLane g em k bad
      check g em (instr em $"xor i1 {anyBad}, true") "integer overflow"
    let ins = (if uns then "u" else "s") + (if op = "/" then "div" else "rem")
    instr em $"{ins} {lt} {a}, {b}"

/// Integer + - * that panics on overflow (llvm.*.with.overflow), in every build.
let checkedArith (g: G) (em: Emitter) (op: string) (uns: bool) (lt: string) (a: string) (b: string) : string =
  let name = $"llvm.{(if uns then "u" else "s")}{Map.find op arith}.with.overflow.{lt}"
  let decl = $"declare {{ {lt}, i1 }} @{name}({lt}, {lt})"
  if firstTime g decl then
    helper g (decl + "\n")
  let r = instr em $"call {{ {lt}, i1 }} @{name}({lt} {a}, {lt} {b})"
  let over = instr em $"extractvalue {{ {lt}, i1 }} {r}, 1"
  check g em (instr em $"xor i1 {over}, true") "integer overflow"
  instr em $"extractvalue {{ {lt}, i1 }} {r}, 0"

// ------------------------------------------------------------ [<Bits>] records (0013)

/// A [<Bits>] record's layout, when the type is one.
let bitsLayoutOf (g: G) (t: Ty) : option<BitsLayout> =
  match t with
  | TCon(n, []) ->
    match Map.tryFind n g.types with
    | Some info -> info.bits
    | None -> None
  | _ -> None

// an integer of one LLVM type as another: extended (unsigned) or cut
let resize (em: Emitter) (from: string) (into: string) (x: string) : string =
  let bits (lt: string) = toInt (String.sub lt 1 (String.length lt - 1))
  if from = into then x
  else if bits from < bits into then instr em $"zext {from} {x} to {into}"
  else instr em $"trunc {from} {x} to {into}"

// the low w bits of an iN, as a value LLVM folds
let private lowBits (em: Emitter) (lt: string) (w: int) : string =
  let n = toInt (String.sub lt 1 (String.length lt - 1))
  if w >= n then "-1" else instr em $"lshr {lt} -1, {n - w}"

/// Field i of the record v (type t): its bits shifted down and masked, as the field's type; an
/// enum's field holding a value with no case panics.
let bitsGet (g: G) (em: Emitter) (t: Ty) (v: string) (i: int) (ft: Ty) : string =
  let b = Option.get (bitsLayoutOf g t)
  let lt = $"i{b.width}"
  let (off, w) = List.item i b.places
  let shifted = if off = 0 then v else instr em $"lshr {lt} {v}, {off}"
  let field = if w >= b.width then shifted else instr em $"and {lt} {shifted}, {lowBits em lt w}"
  let ftl = llty g ft
  if ftl = "i1" then
    instr em $"icmp ne {lt} {field}, 0"
  else if String.startsWith "{" ftl then
    let (_, cases) = union g ft
    let tag = resize em lt "i8" field
    check g em (instr em $"icmp ult i8 {tag}, {List.length cases}") $"a field of {showT g t} holds no case of {showT g ft}"
    instr em $"insertvalue {ftl} zeroinitializer, i8 {tag}, 0"
  else
    resize em lt ftl field

/// The record v (type t) with field i set to x: its bits cleared and x's put there; a value wider
/// than its field panics, as an overflow does.
let bitsSet (g: G) (em: Emitter) (t: Ty) (v: string) (i: int) (ft: Ty) (x: string) : string =
  let b = Option.get (bitsLayoutOf g t)
  let lt = $"i{b.width}"
  let (off, w) = List.item i b.places
  let ftl = llty g ft
  let raw =
    if ftl = "i1" then
      instr em $"zext i1 {x} to {lt}"
    else if String.startsWith "{" ftl then
      resize em "i8" lt (instr em $"extractvalue {ftl} {x}, 0")
    else
      // an integer field narrower than its type: the value must fit
      let n = toInt (String.sub ftl 1 (String.length ftl - 1))
      if w < n then
        check g em (instr em $"icmp ule {ftl} {x}, {lowBits em ftl w}") "integer overflow"
      resize em ftl lt x
  let placed = if off = 0 then raw else instr em $"shl {lt} {raw}, {off}"
  let field = instr em $"shl {lt} {lowBits em lt w}, {off}"
  let others = instr em $"xor {lt} {field}, -1"
  let kept = instr em $"and {lt} {v}, {others}"
  instr em $"or {lt} {kept}, {placed}"

