/// import c "header.h": a C header's functions, structs, enums and #define constants as Z#
/// declarations (externs, [<CLayout>] records, constants). Declarations come from clang's JSON
/// AST (-ast-dump=json), constants from its macro listing (-E -dD). Only what the header itself
/// declares is imported, not the headers it includes. Whatever can't cross the C boundary
/// (unions, arrays, function pointers, static inline functions) is left out, with a reason
/// recorded in Syntax.skippedC.
module CImport

open System
open System.Collections.Generic
open System.Diagnostics
open System.IO
open System.Text.Json
open System.Text.Json.Nodes
open System.Text.RegularExpressions
open Syntax

let private clang (args: string list) =
    let psi = ProcessStartInfo "clang"

    for a in args do
        psi.ArgumentList.Add a

    psi.RedirectStandardOutput <- true
    psi.RedirectStandardError <- true
    use p = Process.Start psi
    let out = p.StandardOutput.ReadToEndAsync()
    let err = p.StandardError.ReadToEndAsync()
    p.WaitForExit()
    if p.ExitCode = 0 then Ok out.Result else Error(err.Result.Trim())

let private str (n: JsonNode) (key: string) =
    match n with
    | :? JsonObject as o when o.ContainsKey key && (o[key] :? JsonValue) -> o[key].GetValue<string>()
    | _ -> null

let private children (n: JsonNode) =
    match n with
    | :? JsonObject as o when o.ContainsKey "inner" -> o["inner"].AsArray() |> Seq.toList
    | _ -> []

let private qualType (n: JsonNode) = str n["type"] "qualType"

let private normalize (t: string) =
    Regex.Replace(Regex.Replace(t, @"\b(const|volatile|restrict|__restrict)\b", ""), @"\s+", " ").Trim()

type private Ctx =
    { typedefs: Dictionary<string, string> // name -> C type
      records: Dictionary<string, string list> // imported struct -> field names
      enums: HashSet<string> }

let private scalars =
    dict
        [ "void", "unit"
          "_Bool", "bool"
          "bool", "bool"
          "char", "i8"
          "signed char", "i8"
          "unsigned char", "u8"
          "short", "i16"
          "short int", "i16"
          "unsigned short", "u16"
          "unsigned short int", "u16"
          "int", "i32"
          "signed int", "i32"
          "signed", "i32"
          "unsigned int", "u32"
          "unsigned", "u32"
          "long", "int"
          "long int", "int"
          "long long", "int"
          "long long int", "int"
          "unsigned long", "u64"
          "unsigned long int", "u64"
          "unsigned long long", "u64"
          "unsigned long long int", "u64"
          "float", "f32"
          "double", "f64" ]

/// A C type as a Z# type, or why it can't be one.
let rec private zsType (ctx: Ctx) (qt: string) : Result<SType, string> = zsType' ctx 0 qt

and private zsType' (ctx: Ctx) (depth: int) (qt: string) : Result<SType, string> =
    let zsType ctx t = zsType' ctx (depth + 1) t
    let t = normalize qt
    let name n = Ok(STName(n, []))

    match t with
    | _ when depth > 20 -> Error(sprintf "'%s' is an opaque struct (pass a pointer to it, as cptr)" t) // typedef struct X X;
    | _ when scalars.ContainsKey t -> name scalars[t]
    | _ when t.Contains "(" -> Error "it uses a function pointer"
    | _ when t.Contains "[" -> Error "it uses an array"
    | _ when t.EndsWith "*" ->
        match normalize (t.Substring(0, t.Length - 1)) with
        | "char"
        | "signed char" -> name "cstr"
        | _ -> name "cptr"
    | _ when t.StartsWith "struct " -> zsType ctx (t.Substring 7)
    | _ when t.StartsWith "enum " -> name "i32"
    | _ when t.StartsWith "union " -> Error "it uses a union"
    | _ when ctx.records.ContainsKey t -> name t
    | _ when ctx.enums.Contains t -> name "i32"
    | _ when ctx.typedefs.ContainsKey t && ctx.typedefs[t] <> t -> zsType ctx ctx.typedefs[t]
    | _ -> Error(sprintf "type '%s' can't cross the C boundary" t)

let private ident (n: string) =
    if keywords.Contains n then n + "_" else n

let private parseInt (s: string) =
    if s.StartsWith "0x" || s.StartsWith "0X" then
        Convert.ToInt64(s.Substring 2, 16)
    else
        Int64.Parse s

/// A #define body as a constant, when it is a literal (or a struct literal of an imported struct).
let rec private macroValue (ctx: Ctx) (body: string) : Expr option =
    let body = body.Trim()
    let m = Regex.Match(body, @"^\(?\s*(-?)\s*(0[xX][0-9a-fA-F]+|\d+)[uUlL]*\s*\)?$")

    if m.Success then
        let v = parseInt m.Groups[2].Value
        Some(Lit(if m.Groups[1].Value = "-" then -v else v))
    else
        let m = Regex.Match(body, @"^\(?\s*(-?)\s*((\d+\.\d*|\.\d+)([eE][-+]?\d+)?|\d+[eE][-+]?\d+)[fFlL]?\s*\)?$")

        if m.Success then
            let v = Double.Parse(m.Groups[2].Value, Globalization.CultureInfo.InvariantCulture)
            Some(FloatLit(if m.Groups[1].Value = "-" then -v else v))
        else
            let m = Regex.Match(body, "^\"([^\"\\\\]*)\"$")

            if m.Success then
                Some(StrLit m.Groups[1].Value)
            else
                let m = Regex.Match(body, @"^(?:CLITERAL\((\w+)\)|\((\w+)\))\s*\{([^}]*)\}$")
                let tname = if m.Groups[1].Success then m.Groups[1].Value else m.Groups[2].Value

                if m.Success && ctx.records.ContainsKey tname then
                    let fields = ctx.records[tname]
                    let parts = m.Groups[3].Value.Split ',' |> Array.map (fun p -> p.Trim()) |> Array.filter ((<>) "")

                    let values = parts |> Array.choose (fun p -> macroValue ctx p)

                    if values.Length = parts.Length && parts.Length = fields.Length then
                        Some(RecordLit(List.zip fields (List.ofArray values)))
                    else
                        None
                else
                    None

/// The declarations a header provides, and the names it had to leave out (with reasons).
let private importUncached (header: string) (dir: string) : (int * Decl) list * (string * string) list =
    let tmp = Path.Combine(Path.GetTempPath(), "zs-import-" + Guid.NewGuid().ToString("N") + ".c")
    File.WriteAllText(tmp, sprintf "#include \"%s\"\n" header)

    try
        let fail msg = raise (CompileError(0, sprintf "import c \"%s\": %s" header msg))

        let ast =
            match clang [ "-fsyntax-only"; "-Xclang"; "-ast-dump=json"; "-I"; dir; tmp ] with
            | Ok json -> JsonNode.Parse(json, documentOptions = JsonDocumentOptions(MaxDepth = 10000))
            | Error e -> fail (e.Split('\n') |> Array.head)

        let macros =
            match clang [ "-E"; "-dD"; "-I"; dir; tmp ] with
            | Ok text -> text
            | Error e -> fail e

        let fromHeader (file: string) =
            not (isNull file) && (file = header || file.EndsWith("/" + header) || Path.GetFileName file = Path.GetFileName header)

        // clang's JSON writes a location's file only when it changes, in document order
        let mutable file: string = null

        let rec track (n: JsonNode) =
            match n with
            | :? JsonObject as o ->
                for kv in o do
                    if kv.Key = "file" && (kv.Value :? JsonValue) then
                        file <- kv.Value.GetValue<string>()
                    elif kv.Key <> "includedFrom" then
                        track kv.Value
            | :? JsonArray as a ->
                for x in a do
                    track x
            | _ -> ()

        let ctx =
            { typedefs = Dictionary()
              records = Dictionary()
              enums = HashSet() }

        let decls = ResizeArray<int * Decl>()
        let skipped = ResizeArray<string * string>()
        let defined = HashSet<string>()
        let mutable unnamed: (JsonNode * bool) option = None // the last struct without a name

        let addRecord (name: string) (n: JsonNode) (mine: bool) =
            let fields =
                children n
                |> List.filter (fun f -> str f "kind" = "FieldDecl")
                |> List.map (fun f -> ident (str f "name"), zsType ctx (qualType f))

            match fields |> List.tryPick (fun (_, t) -> match t with Error e -> Some e | Ok _ -> None) with
            | _ when fields.IsEmpty -> skipped.Add(name, "it has no fields here (an opaque struct; pass it as cptr)")
            | Some e -> skipped.Add(name, "a field: " + e)
            | None when defined.Add name ->
                ctx.records[name] <- fields |> List.map fst

                if mine then
                    let body = RecordTy(fields |> List.map (fun (f, t) -> f, (match t with Ok t -> t | Error _ -> STName("unit", [])), None))
                    decls.Add(0, Attrs([ "CLayout", [] ], TypeDecl(name, [], body, [])))
            | None -> ()

        for n in children ast do
            // the declaration's file is the one in effect at its loc (written before its body)
            match n with
            | :? JsonObject as o when o.ContainsKey "loc" -> track o["loc"]
            | _ -> ()

            let mine = fromHeader file
            track n
            let name = str n "name"

            match str n "kind" with
            | "TypedefDecl" ->
                let qt = qualType n

                // typedef struct { ... } Name; the unnamed struct right before takes the name
                match unnamed with
                | Some(r, m) when not (isNull name) ->
                    unnamed <- None
                    addRecord name r m
                | _ when not (isNull name) && not (qt.Contains "(unnamed" || qt.Contains "(anonymous") ->
                    ctx.typedefs[name] <- qt
                | _ -> ()
            | "RecordDecl" when str n "tagUsed" = "struct" && not (children n).IsEmpty ->
                if isNull name then unnamed <- Some(n, mine) else addRecord name n mine
            | "EnumDecl" ->
                if not (isNull name) then
                    ctx.enums.Add name |> ignore

                let mutable next = 0L

                for c in children n do
                    if str c "kind" = "EnumConstantDecl" then
                        let rec value (x: JsonNode) =
                            match str x "value" with
                            | null -> children x |> List.tryPick value
                            | v -> Some(Int64.Parse v)

                        let v = children c |> List.tryPick value |> Option.defaultValue next
                        next <- v + 1L
                        let cn = str c "name"

                        if mine && defined.Add cn then
                            decls.Add(0, Const(cn, Lit v))
            | "FunctionDecl" when mine && not (isNull name) && not (defined.Contains name) ->
                let qt = qualType n

                let isStatic = str n "storageClass" = "static"
                let ret = zsType ctx (qt.Substring(0, qt.IndexOf '(').Trim())

                let pars =
                    children n
                    |> List.filter (fun p -> str p "kind" = "ParmVarDecl")
                    |> List.mapi (fun i p ->
                        match zsType ctx (qualType p) with
                        | Ok t -> Ok t
                        | Error e -> Error(sprintf "parameter %d: %s" (i + 1) e))

                let problem =
                    if isStatic then
                        Some "it is static (inline), so there is no symbol to call"
                    elif keywords.Contains name then
                        Some "its name is a Z# keyword"
                    else
                        (match ret with
                         | Error e -> [ "the return type: " + e ]
                         | Ok _ -> [])
                        @ (pars |> List.choose (fun p -> match p with Error e -> Some e | Ok _ -> None))
                        |> List.tryHead

                match problem, ret with
                | None, Ok r ->
                    defined.Add name |> ignore
                    let args = pars |> List.choose (fun p -> match p with Ok t -> Some t | Error _ -> None)
                    decls.Add(0, Extern(name, args, qt.Contains "...", r))
                | Some e, _ -> skipped.Add(name, e)
                | None, Error e -> skipped.Add(name, e)
            | _ -> ()

        // #define constants, attributed to files by clang's line markers
        let mutable mfile = ""

        for line in macros.Split '\n' do
            let marker = Regex.Match(line, "^# \\d+ \"([^\"]*)\"")

            if marker.Success then
                mfile <- marker.Groups[1].Value
            elif line.StartsWith "#define " && fromHeader mfile then
                let m = Regex.Match(line, @"^#define ([A-Za-z_][A-Za-z0-9_]*)(\(?)\s*(.*)$")

                if m.Success && m.Groups[2].Value = "" then
                    let name = m.Groups[1].Value

                    if not (name.StartsWith "_") && not (keywords.Contains name) && not (defined.Contains name) then
                        match macroValue ctx m.Groups[3].Value with
                        | Some v ->
                            defined.Add name |> ignore
                            decls.Add(0, Const(name, v))
                        | None -> ()

        List.ofSeq decls, List.ofSeq skipped
    finally
        File.Delete tmp

let private cache = Dictionary<string * string, DateTime * ((int * Decl) list * (string * string) list)>()

/// The header's declarations (cached until the header changes), recording what was left out.
let importHeader (header: string) (dir: string) : (int * Decl) list =
    let path = Path.Combine(dir, header)
    let stamp = if File.Exists path then File.GetLastWriteTimeUtc path else DateTime.MinValue

    let decls, skipped =
        match cache.TryGetValue((header, dir)) with
        | true, (t, r) when t = stamp -> r
        | _ ->
            let r = importUncached header dir
            cache[(header, dir)] <- (stamp, r)
            r

    for name, why in skipped do
        skippedC[name] <- why

    decls
