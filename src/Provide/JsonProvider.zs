/// The json provider (proposal 0001): a document's shape as records with the Json derive, and
/// parse and print functions, as `zs provide json <file>` prints. An object is a record named after
/// its key (two keys with the same fields share one), an array a list whose element type is
/// unified over the elements, a number `int` when every occurrence is integral, `null` or a key
/// some of an array's objects lack an option, and a key whose values differ in shape stays `Json`.

/// A value's shape over every occurrence seen.
type Shape =
  /// Nothing seen: an empty array's elements. `Json` when it stays so.
  | SUnknown
  | SNull
  | SBool
  | SInt
  | SFloat
  | SString
  /// Values of different shapes: `Json`, as it is.
  | SAny
  | SList of Shape
  | SOption of Shape
  /// An object: its fields in document order.
  | SRecord of list<string * Shape>

let private optional (s: Shape) : Shape =
  match s with
  | SOption _ -> s
  | SNull -> s
  | _ -> SOption s

/// The shape of two occurrences: what both are, an option when one is null, `f64` over `int`,
/// fields missing on one side optional, and `Json` when they don't fit together.
let rec unify (a: Shape) (b: Shape) : Shape =
  match (a, b) with
  | (SUnknown, x) -> x
  | (x, SUnknown) -> x
  | (SNull, SNull) -> SNull
  | (SNull, x) -> optional x
  | (x, SNull) -> optional x
  | (SOption x, y) -> optional (unify x y)
  | (x, SOption y) -> optional (unify x y)
  | (SInt, SInt) -> SInt
  | (SFloat, SFloat) -> SFloat
  | (SInt, SFloat) -> SFloat
  | (SFloat, SInt) -> SFloat
  | (SBool, SBool) -> SBool
  | (SString, SString) -> SString
  | (SList x, SList y) -> SList (unify x y)
  | (SRecord fs, SRecord gs) -> SRecord (unifyFields fs gs)
  | _ -> SAny

and private unifyFields (fs: list<string * Shape>) (gs: list<string * Shape>) : list<string * Shape> =
  let find (k: string) (xs: list<string * Shape>) : option<Shape> =
    match List.tryFind (fun (n, _) -> n = k) xs with
    | Some(_, s) -> Some s
    | None -> None
  let left =
    List.map (fun (k, s) -> (match find k gs with
                             | Some t -> (k, unify s t)
                             | None -> (k, optional s))) fs
  let right =
    List.choose (fun (k, s) -> (match find k fs with
                                | Some _ -> None
                                | None -> Some(k, optional s))) gs
  List.append left right

/// A document's shape.
let rec shapeOf (j: Json) : Shape =
  match j with
  | JNull -> SNull
  | JBool _ -> SBool
  | JInt _ -> SInt
  | JString _ -> SString
  | JArray xs -> SList (List.fold (fun acc x -> unify acc (shapeOf x)) SUnknown xs)
  | JObject kvs ->
    // a key twice in one object unifies its values
    let add (acc: list<string * Shape>) (kv: string * Json) : list<string * Shape> =
      let (k, v) = kv
      let s = shapeOf v
      if List.exists (fun (n, _) -> n = k) acc then List.map (fun (n, t) -> if n = k then (n, unify t s) else (n, t)) acc
      else List.append acc [ (k, s) ]
    SRecord (List.fold add [] kvs)
  // a JNumber, and a JUInt (past i64's range) where the library has one: stage 0's hasn't, and
  // the compiler builds with both
  | _ -> SFloat

/// A record the module declares: its name, its fields as written, and the path of keys it was
/// found at (empty for the document itself).
type Record = { name: string; fields: string; path: list<string> }

// the root record's name, the types given by path, the records so far, and every key written as
// a field (each must be one: Names.unnamed)
type private Naming = { root: string; overrides: list<string * string>; records: ref<list<Record>>; keys: ref<list<string>> }

let private pathText (path: list<string>) = String.join "." path

/// The Z# type for a shape at `path`, the records it holds registered first (so a record is
/// declared before the one that uses it).
let rec private typeOf (cx: Naming) (path: list<string>) (key: string) (inList: bool) (s: Shape) : string =
  match s with
  | SUnknown -> "Json"
  | SAny -> "Json"
  | SNull -> "option<Json>"
  | SBool -> "bool"
  | SInt -> "int"
  | SFloat -> "f64"
  | SString -> "string"
  | SList e -> "list<" + typeOf cx path key true e + ">"
  | SOption e -> "option<" + typeOf cx path key inList e + ">"
  | SRecord [] -> "Json"
  | SRecord fs -> register cx path key inList fs

and private register (cx: Naming) (path: list<string>) (key: string) (inList: bool) (fs: list<string * Shape>) : string =
  let field (kv: string * Shape) =
    let (k, s) = kv
    let fieldPath = List.append path [ k ]
    let t =
      match List.tryFind (fun (p, _) -> p = pathText fieldPath) cx.overrides with
      | Some(_, t) -> t
      | None -> typeOf cx fieldPath k false s
    let dflt = if String.startsWith "option<" t then " = None" else ""
    cx.keys.Value <- k :: cx.keys.Value
    Names.fieldName k + ": " + t + dflt
  let text = String.join "; " (List.map field fs)
  match List.tryFind (fun (r: Record) -> r.fields = text) cx.records.Value with
  | Some r -> r.name
  | None ->
    let wanted = if List.isEmpty path then cx.root else Names.typeName (if inList then Names.singular key else key)
    let taken (n: string) = List.exists (fun (r: Record) -> r.name = n) cx.records.Value
    let rec free (n: int) : string =
      let candidate = if n = 1 then wanted else wanted + string n
      if taken candidate then free (n + 1) else candidate
    let name = free 1
    cx.records.Value <- List.append cx.records.Value [ { name = name; fields = text; path = path } ]
    name

/// The first value at a path of keys, an array's first element standing for the array.
let rec private sampleAt (j: Json) (path: list<string>) : option<Json> =
  match (j, path) with
  | (JArray(x :: _), _) -> sampleAt x path
  | (JArray [], _) -> None
  | (_, []) -> Some j
  | (JObject kvs, k :: rest) ->
    match List.tryFind (fun (n, _) -> n = k) kvs with
    | Some(_, v) -> sampleAt v rest
    | None -> None
  | _ -> None

/// The options `zs provide json` takes.
let options : list<string> = [ "root"; "types" ]

/// The pairs of a `types` option: `temp:f64,readings.value:f32`, a field's path and its type.
let private overridesOf (types: string) : result<list<string * string>, string> =
  let one (item: string) : result<string * string, string> =
    match String.indexOf ":" item with
    | None -> Error ("types: '" + item + "' isn't path:type, as temp:f64")
    | Some i -> Ok(String.sub item 0 i, String.trim (String.sub item (i + 1) (String.length item - i - 1)))
  let rec go (items: list<string>) (acc: list<string * string>) =
    match items with
    | [] -> Ok(List.rev acc)
    | item :: rest ->
      match one (String.trim item) with
      | Ok p -> go rest (p :: acc)
      | Error e -> Error e
  if types = "" then Ok [] else go (String.split "," types) []

/// The module for the document in `text`, read from `file`, with the options given: `root`
/// names the top record (Root), `types` overrides fields' types by path. Error when the text
/// isn't JSON, or an option isn't right.
let provide (file: string) (text: string) (opts: list<string * string>) : result<string, string> =
  let opt (name: string) (dflt: string) =
    match List.tryFind (fun (n, _) -> n = name) opts with
    | Some(_, v) -> v
    | None -> dflt
  let root = opt "root" "Root"
  if not (Names.isIdent root) || not (String.toUpper (String.sub root 0 1) = String.sub root 0 1) then Error ("root: '" + root + "' isn't a type name (a capitalized word, as Weather)")
  else
    match overridesOf (opt "types" "") with
    | Error e -> Error e
    | Ok overrides ->
      match Json.parse text with
      | Error e -> Error (file + ": " + e)
      | Ok doc ->
        let cx = { root = root; overrides = overrides; records = ref []; keys = ref [] }
        let top = typeOf cx [] "" false (shapeOf doc)
        match Names.unnamed (List.rev cx.keys.Value) with
        | Some e -> Error (file + ": " + e)
        | None ->
          let decl (r: Record) : list<string> =
            let from = if List.isEmpty r.path then file else List.item (List.length r.path - 1) r.path
            let sample =
              match sampleAt doc r.path with
              | Some j -> Names.clip 100 (Json.print j)
              | None -> ""
            [ Names.oneLine ("/// From \"" + from + "\": " + sample); "[<Derive(Json)>]"; "type " + r.name + " = { " + r.fields + " }"; "" ]
          let header = [ Names.oneLine ("// provided by json 0.1 from " + file); Names.oneLine ("// input: " + file); "" ]
          let functions =
            [ "/// Parses a document of " + top + "'s shape."
              "let parse (text: string) : result<" + top + ", string> = Result.bind fromJson (Json.parse text)"
              ""
              "/// Prints a " + top + " as a document."
              "let print (value: " + top + ") : string = Json.print (toJson value)" ]
          Ok(String.join "\n" (List.concat [ header; List.collect decl cx.records.Value; functions ]) + "\n")
