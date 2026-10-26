/// DWARF debug info (zs build -g) as LLVM metadata (the F# compiler's Codegen, its debug part):
/// files, the compile unit, locations, and the types of the variables gdb can show. Metadata is
/// numbered as made and written after the functions.
open Types.Ty
open Core.Ir
open Emit
open Layout

/// A metadata node: its number.
let meta (g: G) (s: string) : string =
  g.mdCount.Value <- g.mdCount.Value + 1
  let id = $"!{g.mdCount.Value}"
  Buffer.push $"{id} = {s}\n" g.md
  id

/// !range for array and string lengths: no array can be as long as the address space, so a length
/// is below 2^31 on a 32-bit chip and 2^47 on a 64-bit machine. Knowing that lets LLVM drop
/// overflow checks and bounds checks that can't fail (an index from a loop up to the length).
let lenRange (g: G) : string =
  match g.lenRange.Value with
  | Some r -> r
  | None ->
    let r = meta g (if word32 g.opts.target then "!{i_W 0, i_W 2147483648}" else "!{i_W 0, i_W 140737488355328}")
    g.lenRange.Value <- Some r
    r

/// A length's load, with the range it's in.
let loadLen (g: G) (em: Emitter) (p: string) : string =
  let r = lenRange g
  instr em $"load i_W, ptr {p}, !range {r}"

/// A source file's node.
let diFile (g: G) (file: string) : string =
  match Map.tryFind file g.diFiles.Value with
  | Some id -> id
  | None ->
    let full = Path.getFullPath file
    let id = meta g $"!DIFile(filename: \"{Path.getFileName full}\", directory: \"{Path.getDirectoryName full}\")"
    g.diFiles.Value <- Map.add file id g.diFiles.Value
    id

/// The compile unit (main's file).
let compileUnit (g: G) : string =
  match g.compileUnit.Value with
  | Some c -> c
  | None ->
    let file = diFile g g.mainFile
    let c = meta g $"distinct !DICompileUnit(language: DW_LANG_C11, file: {file}, producer: \"zs\", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug)"
    g.compileUnit.Value <- Some c
    c

/// The type every function's debug info has.
let noTypes (g: G) : string =
  match g.noTypes.Value with
  | Some t -> t
  | None ->
    let t = meta g "!DISubroutineType(types: !{})"
    g.noTypes.Value <- Some t
    t

/// A line's location in a scope.
let diLoc (g: G) (line: int) (scope: string) : string =
  let key = $"{line} {scope}"
  match Map.tryFind key g.locs.Value with
  | Some id -> id
  | None ->
    let id = meta g $"!DILocation(line: {line}, column: 1, scope: {scope})"
    g.locs.Value <- Map.add key id g.locs.Value
    id

/// The field types of a value that is an LLVM struct: a tuple's or a record's, or a plain union's
/// tag and then every case's fields.
let structFields (g: G) (t: Ty) : list<Ty> =
  match t with
  | TTuple ts -> ts
  | TCon("fixed", [ el; TCon(n, []) ]) -> List.replicate (toInt n) el
  | TCon(n, args) ->
    match (Map.find n g.types).def with
    | RecordDef fs -> List.map (fun (_, ft) -> substGen g args ft) fs
    | UnionDef cs -> tcon (if tagTy cs = "i8" then "u8" else "i32") :: List.map (substGen g args) (List.collect snd cs)
    | CUnionDef _ -> []
  | _ -> []

/// Size and alignment in bytes, as LLVM (and C) lays the value out.
let rec sizeAlign (g: G) (t: Ty) : int * int =
  match llty g t with
  | "i1"
  | "i8" -> (1, 1)
  | "i16" -> (2, 2)
  | "i32"
  | "float" -> (4, 4)
  | "i64"
  | "double" -> (8, 8)
  | "ptr" -> (pointerBytes g, pointerBytes g)
  | "{}" -> (0, 1)
  | _ when Option.isSome (cUnion g t) ->
    let (size, align, _) = cLayout g t
    (size, align)
  | _ ->
    let (size, align, _) = layout g (structFields g t)
    (size, align)

/// A struct's size and alignment, and each field's offset.
and layout (g: G) (ts: list<Ty>) : int * int * list<int> =
  let off = ref 0
  let align = ref 1
  let offsets = Buffer.empty
  for t in ts do
    let (s, a) = sizeAlign g t
    off.Value <- (off.Value + a - 1) / a * a
    Buffer.push off.Value offsets
    off.Value <- off.Value + s
    align.Value <- max align.Value a
  ((off.Value + align.Value - 1) / align.Value * align.Value, align.Value, Array.toList (Buffer.toArray offsets))

let private signedInts : Set<string> = Set.ofList [ "i8"; "i16"; "i32"; "i64" ]

let private unsignedInts : Set<string> = Set.ofList [ "u8"; "u16"; "u32"; "u64" ]

/// The DWARF type of a variable, for the types gdb can show as values: numbers, bool, char,
/// strings (as their text), and tuples, records and plain unions of those. With field, the type of
/// a struct's field: a string there is a pointer to its object (print *p for it).
let rec diTypeOf (g: G) (field: bool) (t: Ty) : option<string> =
  let named (key: string) (make: unit -> string) : option<string> =
    match Map.tryFind key g.diTypes.Value with
    | Some id -> Some id
    | None ->
      let id = make ()
      g.diTypes.Value <- Map.add key id g.diTypes.Value
      Some id
  let basic (name: string) (bits: int) (enc: string) = named name (fun () -> meta g $"!DIBasicType(name: \"{name}\", size: {bits}, encoding: {enc})")
  let pointer (key: string) (target: string) = named key (fun () -> meta g $"!DIDerivedType(tag: DW_TAG_pointer_type, baseType: {target}, size: {8 * pointerBytes g})")
  // a member of a struct, when gdb can show its type
  let memberAt (fo: (string * Ty) * int) : option<string> =
    let ((f, ft), off) = fo
    match diTypeOf g true ft with
    | Some dt ->
      let (bits, _) = sizeAlign g ft
      Some(meta g $"!DIDerivedType(tag: DW_TAG_member, name: \"{f}\", baseType: {dt}, size: {8 * bits}, offset: {8 * off})")
    | None -> None
  // a struct: its members, named, at their offsets (members gdb can't show are left out)
  let structOf (name: string) (fields: list<string * Ty>) =
    let make () =
      let (size, _, offsets) = layout g (List.map snd fields)
      let members = List.choose memberAt (List.zip fields offsets)
      meta g $"!DICompositeType(tag: DW_TAG_structure_type, name: \"{name}\", size: {8 * size}, elements: !{{{String.join ", " members}}})"
    named ("struct " + showF g t) make
  match t with
  | TCon("int", []) -> basic "int" (8 * pointerBytes g) "DW_ATE_signed"
  | TCon(n, []) when Set.contains n signedInts -> basic n (toInt (String.sub n 1 (String.length n - 1))) "DW_ATE_signed"
  | TCon(n, []) when Set.contains n unsignedInts -> basic n (toInt (String.sub n 1 (String.length n - 1))) "DW_ATE_unsigned"
  | TCon("usize", []) -> basic "usize" (8 * pointerBytes g) "DW_ATE_unsigned"
  | TCon("f64", []) -> basic "f64" 64 "DW_ATE_float"
  | TCon("f32", []) -> basic "f32" 32 "DW_ATE_float"
  | TCon("bool", []) -> basic "bool" 8 "DW_ATE_boolean"
  | TCon("char", []) -> basic "char" 32 "DW_ATE_UTF"
  | TCon("string", []) ->
    if field then
      // the object: { header word (its count first), length, bytes }
      let bytes = Option.get (basic "u8" 8 "DW_ATE_unsigned_char")
      let word = Option.get (basic "int" (8 * pointerBytes g) "DW_ATE_signed")
      let count = Option.get (basic "i32" 32 "DW_ATE_signed")
      let make () =
        let w = 8 * pointerBytes g
        let arr = meta g $"!DICompositeType(tag: DW_TAG_array_type, baseType: {bytes}, elements: !{{!DISubrange(count: -1)}})"
        let m (name: string) (ty: string) (size: int) (off: int) = meta g $"!DIDerivedType(tag: DW_TAG_member, name: \"{name}\", baseType: {ty}, size: {size}, offset: {off})"
        let m1 = m "count" count 32 0
        let m2 = m "length" word w w
        let m3 = m "bytes" arr w (2 * w)
        meta g $"!DICompositeType(tag: DW_TAG_structure_type, name: \"string\", size: {2 * w}, elements: !{{{m1}, {m2}, {m3}}})"
      Option.bind (pointer "string*") (named "string object" make)
    else
      // a variable: a pointer to its bytes (the declaration adds the offset), so gdb prints the
      // text
      Option.bind (pointer "char*") (basic "char" 8 "DW_ATE_signed_char")
  | TTuple ts -> structOf (showT g t) (List.mapi (fun i ft -> ($"Item{i + 1}", ft)) ts)
  // a [<Bits>] record: its integer (0013)
  | TCon(_, []) when Option.isSome (bitsLayoutOf g t) -> basic (showT g t) (Option.get (bitsLayoutOf g t)).width "DW_ATE_unsigned"
  | TCon(_, []) when Option.isSome (cUnion g t) ->
    // a C union, as C's is described: each case a member at offset 0
    let make () =
      let cases = List.map (fun (c, ft) -> ((Infer.Cx.afterLastDot c, ft), 0)) (Option.get (cUnion g t))
      meta g $"!DICompositeType(tag: DW_TAG_union_type, name: \"{showT g t}\", size: {8 * fst (sizeAlign g t)}, elements: !{{{String.join ", " (List.choose memberAt cases)}}})"
    named ("union " + showF g t) make
  | TCon(n, args) when isRecordType g n ->
    match (Map.find n g.types).def with
    | RecordDef fs -> structOf (showT g t) (List.map (fun (f, ft) -> (f, substGen g args ft)) fs)
    | UnionDef _
    | CUnionDef _ -> None
  | TCon(n, _) when isUnionType g n && Types.Repr.plainUnion g.v g.types t ->
    // the tag as an enumeration of the cases; then each case's fields, named after it
    let (_, cases) = union g t
    let tagBits = if tagTy cases = "i8" then 8 else 32
    let makeEnum () =
      let items = List.mapi (fun i (c, _) -> $"!DIEnumerator(name: \"{shortName c}\", value: {i})") cases
      meta g $"!DICompositeType(tag: DW_TAG_enumeration_type, name: \"{showT g t}\", size: {tagBits}, elements: !{{{String.join ", " items}}})"
    let enum = named ("enum " + showF g t) makeEnum
    if List.forall (fun (_, fs) -> List.isEmpty fs) cases then
      // an enum: its value is the tag
      enum
    else
      let caseFields (cf: string * list<Ty>) : list<string * Ty> =
        let (c0, fs) = cf
        let c = shortName c0
        List.mapi (fun j ft -> ((if List.length fs = 1 then c else $"{c}.{j}"), ft)) fs
      let fields = List.collect caseFields cases
      let make () =
        let (size, _, offsets) = layout g (structFields g t)
        let tagMember = meta g $"!DIDerivedType(tag: DW_TAG_member, name: \"case\", baseType: {Option.get enum}, size: {tagBits}, offset: 0)"
        let members = List.choose memberAt (List.zip fields (List.tail offsets))
        meta g $"!DICompositeType(tag: DW_TAG_structure_type, name: \"{showT g t}\", size: {8 * size}, elements: !{{{String.join ", " (tagMember :: members)}}})"
      named ("struct " + showF g t) make
  | _ -> None

let diType (g: G) (t: Ty) : option<string> = diTypeOf g false t

// whether a text is all decimal digits
let private allDigits (s: string) : bool =
  let ok = ref true
  for i in 0 .. String.length s - 1 do
    let b = String.byte s i
    if b < u8 48 || b > u8 57 then
      ok.Value <- false
  ok.Value

/// The name a variable has in the source (unique names are x.12; temporaries start with $).
let sourceName (x: string) : option<string> =
  if String.startsWith "$" x then
    None
  else
    match String.lastIndexOf "." x with
    | Some i when i > 0 && allDigits (String.sub x (i + 1) (String.length x - i - 1)) -> Some(String.sub x 0 i)
    | _ -> Some x
