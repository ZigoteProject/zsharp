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

/// A node's number before its text, for a type that refers to itself (a list's tail); `define`
/// writes it.
let reserve (g: G) : string =
  g.mdCount.Value <- g.mdCount.Value + 1
  $"!{g.mdCount.Value}"

let define (g: G) (id: string) (s: string) = Buffer.push $"{id} = {s}\n" g.md

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
    // escaped as LLVM reads a string: Windows' \ would start an escape (tests\debug a byte 0xDE)
    let id = meta g $"!DIFile(filename: \"{encoded (Path.getFileName full)}\", directory: \"{encoded (Path.getDirectoryName full)}\")"
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
    | UnionDef cs ->
      match oneCase g t with
      | Some fs -> fs
      | None -> tcon (if tagTy cs = "i8" then "u8" else "i32") :: List.map (substGen g args) (List.collect snd cs)
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
    match t with
    // a SIMD vector, or a mask: its lanes side by side, aligned to its size as LLVM lays it out
    // (32-bit ARM's data layout aligns a 128-bit vector to 8)
    | TCon(n, []) when isVectorName n ->
      let (e, lanes) = Option.get (vectorInfo n)
      let size = lanes * fst (sizeAlign g (tcon e))
      let arm32 = String.startsWith "thumb" g.opts.arch || (String.startsWith "arm" g.opts.arch && not (String.startsWith "arm64" g.opts.arch))
      (size, (if arm32 && size = 16 then 8 else size))
    | TCon(n, []) when isMaskName n ->
      let lanes = snd (List.find (fun (m, _) -> m = n) maskTypes)
      let size = max 1 ((lanes + 7) / 8)
      (size, size)
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

/// The DWARF type of a variable: numbers, bool, char, strings (as their text), tuples, records
/// and plain unions of those as values; lists, arrays, boxed unions, refs and Buffers as the
/// type's name over a pointer to the object (print *p shows its count and fields, a list's head
/// and tail), an option over a pointer as the pointer, closures and the runtime's cells as
/// pointers. With field, the type of a struct's field: a string there is a pointer to its object.
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
  let word = 8 * pointerBytes g
  let memberNode (name: string) (dt: string) (bits: int) (off: int) = meta g $"!DIDerivedType(tag: DW_TAG_member, name: \"{name}\", baseType: {dt}, size: {bits}, offset: {8 * off})"
  let countMember () = memberNode "count" (Option.get (basic "i32" 32 "DW_ATE_signed")) 32 0
  // a heap value: the type's name over a pointer to its object, whose members, from the header
  // on, may name the type again (a list's tail), so its node is reserved before them
  let objectOf (size: int) (members: string -> list<string>) : option<string> =
    let key = "object " + showF g t
    match Map.tryFind key g.diTypes.Value with
    | Some id -> Some id
    | None ->
      // known by name before its members are made: a tree's node holds trees
      let name = showT g t
      let td = reserve g
      g.diTypes.Value <- Map.add key td g.diTypes.Value
      let obj = reserve g
      let ms = members td
      define g obj $"!DICompositeType(tag: DW_TAG_structure_type, name: \"{name} object\", size: {8 * size}, elements: !{{{String.join ", " ms}}})"
      let p = meta g $"!DIDerivedType(tag: DW_TAG_pointer_type, baseType: {obj}, size: {word})"
      define g td $"!DIDerivedType(tag: DW_TAG_typedef, name: \"{name}\", baseType: {p})"
      Some td
  // void*: a pointer with no pointee (LLVM requires the field, null for none)
  let voidPtr () = Option.get (named "void*" (fun () -> meta g $"!DIDerivedType(tag: DW_TAG_pointer_type, baseType: null, size: {word})"))
  // a pointer gdb shows as an address: the type's name over void*
  let opaque () = named ("opaque " + showF g t) (fun () -> meta g $"!DIDerivedType(tag: DW_TAG_typedef, name: \"{showT g t}\", baseType: {voidPtr ()})")
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
  // a fixed-size array: inline, N elements
  | TCon("fixed", [ el; TCon(n, []) ]) ->
    match diTypeOf g true el with
    | Some et -> named ("fixed " + showF g t) (fun () -> meta g $"!DICompositeType(tag: DW_TAG_array_type, baseType: {et}, size: {8 * fst (sizeAlign g t)}, elements: !{{!DISubrange(count: {toInt n})}})")
    | None -> None
  // an array: its object is the count, the length and the elements
  // (the element's type is made inside the object's callback, after the object's name is known:
  // an element may hold the object's own type, as Q of ref<Q> does)
  | TCon("array", [ el ]) ->
    let (es, _) = sizeAlign g el
    objectOf (2 * pointerBytes g) (fun _ ->
      let length = memberNode "length" (Option.get (basic "int" word "DW_ATE_signed")) word (pointerBytes g)
      match diTypeOf g true el with
      | Some et ->
        let elems = meta g $"!DICompositeType(tag: DW_TAG_array_type, baseType: {et}, elements: !{{!DISubrange(count: -1)}})"
        [ countMember (); length; memberNode "elements" elems (8 * es) (2 * pointerBytes g) ]
      | None -> [ countMember (); length ])
  // a list: a cell is the header, the head and the tail, another list
  | TCon("list", [ el ]) ->
    let (size, _, offsets) = layout g [ tcon "int"; el; t ]
    let (es, _) = sizeAlign g el
    objectOf size (fun td ->
      let tail = memberNode "tail" td word (List.item 2 offsets)
      match diTypeOf g true el with
      | Some et -> [ countMember (); memberNode "head" et (8 * es) (List.item 1 offsets); tail ]
      | None -> [ countMember (); tail ])
  // a ref, or a Buffer (a ref to its storage record: the owner array, the data, the length and
  // the room): the header and the value
  | TCon("ref", [ x ]) ->
    let (size, _, offsets) = layout g [ tcon "int"; x ]
    let (xs, _) = sizeAlign g x
    objectOf size (fun _ ->
      match diTypeOf g true x with
      | Some xt -> [ countMember (); memberNode "value" xt (8 * xs) (List.item 1 offsets) ]
      | None -> [ countMember () ])
  | TCon("cstr", _)
  | TCon("cptr", _)
  | TCon("ptr", _)
  | TCon("fnptr", _)
  | TCon("weak", _)
  | TCon("Atomic", _)
  | TCon("Mutex", _)
  | TCon("Channel", _)
  | TCon("Spsc", _)
  | TCon("share", _)
  | TFun _ -> opaque ()
  | TCon(n, _) when isDynName n -> opaque ()
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
  | TCon(n, _) when isUnionType g n && Option.isSome (oneCase g t) ->
    // one case: its field's type under the union's name, or a struct of its fields
    let (c, _) = List.head (snd (union g t))
    match Option.get (oneCase g t) with
    | [ ft ] ->
      match diTypeOf g true ft with
      | Some dt -> named ("typedef " + showF g t) (fun () -> meta g $"!DIDerivedType(tag: DW_TAG_typedef, name: \"{showT g t}\", baseType: {dt})")
      | None -> None
    | fts -> structOf (showT g t) (List.mapi (fun j ft -> ($"{shortName c}.{j}", ft)) fts)
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
  | TCon(n, _) when isUnionType g n ->
    let (_, cases) = union g t
    match repOf g t with
    // the option shape over a pointer: the pointer itself (None is the static none)
    | Types.Repr.Niche(_, payload) ->
      // its name reserved before the payload's type is made, which may hold this type again
      // (Leaf | Node of list<Rose>)
      let key = "niche " + showF g t
      match Map.tryFind key g.diTypes.Value with
      | Some id -> Some id
      | None ->
        let td = reserve g
        g.diTypes.Value <- Map.add key td g.diTypes.Value
        let pt =
          match diTypeOf g true payload with
          | Some pt -> pt
          | None -> voidPtr ()
        define g td $"!DIDerivedType(tag: DW_TAG_typedef, name: \"{showT g t}\", baseType: {pt})"
        Some td
    | _ ->
      // a cell: the header's count, the case (where the cells carry one), then each case with
      // fields as a struct of them over the cell, named after the case
      let tagged = tagged g t
      let headerTys = tcon "int" :: (if tagWord g t then [ tcon "i32" ] else [])
      let caseStruct (cf: string * list<Ty>) : option<string> =
        let (c0, fs) = cf
        let c = shortName c0
        if List.isEmpty fs then
          None
        else
          let (size, _, offsets) = layout g (List.append headerTys fs)
          let fields = List.mapi (fun j ft -> (($"{j}", ft), List.item (List.length headerTys + j) offsets)) fs
          let members = List.choose memberAt fields
          let st = meta g $"!DICompositeType(tag: DW_TAG_structure_type, name: \"{showT g t}.{c}\", size: {8 * size}, elements: !{{{String.join ", " members}}})"
          Some(memberNode c st (8 * size) 0)
      let cellSize (fs: list<Ty>) : int =
        let (s, _, _) = layout g (List.append headerTys fs)
        s
      let size = List.fold (fun (m: int) (cf: string * list<Ty>) -> max m (cellSize (snd cf))) (cellSize []) cases
      objectOf size (fun _ ->
        let caseMember =
          if not tagged then
            []
          else
            let items = List.mapi (fun i (c, _) -> $"!DIEnumerator(name: \"{shortName c}\", value: {i})") cases
            let bits = if tagWord g t then 32 else 16
            let enum = meta g $"!DICompositeType(tag: DW_TAG_enumeration_type, name: \"{showT g t} case\", size: {bits}, elements: !{{{String.join ", " items}}})"
            [ memberNode "case" enum bits (if tagWord g t then pointerBytes g else 4) ]
        List.concat [ [ countMember () ]; caseMember; List.choose caseStruct cases ])
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
