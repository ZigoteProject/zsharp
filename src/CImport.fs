/// import c "header.h": a C header's functions, structs, enums and #define constants as Z#
/// declarations (externs, [<CLayout>] records, constants). Declarations come from clang's JSON
/// AST (-ast-dump=json), constants from its macro listing (-E -dD). Only what the header itself
/// declares is imported, not the headers it includes. Whatever can't cross the C boundary
/// (unions, arrays, static inline functions) is left out, with a reason
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
  try
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
  with :? ComponentModel.Win32Exception -> Error "clang isn't installed here"

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
          "long", "int" // the word, like C's long on Linux (LP64 and ILP32)
          "long int", "int"
          "long long", "i64"
          "long long int", "i64"
          "unsigned long", "usize"
          "unsigned long int", "usize"
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
    | _ when t.Contains "(" ->
        // a function pointer, R (*)(A, B): fnptr<A -> B -> R>, or fnptr<unit -> R> for one
        // that takes nothing
        let m = Regex.Match(t, @"^(.*)\(\*\)\s*\((.*)\)$")
        let ps = if m.Success then m.Groups[2].Value.Trim() else ""

        if not m.Success || ps.Contains "(" then
            Error "it uses a function type other than a pointer to a function of C values"
        else
            let ps = if ps = "" || ps = "void" then [] else ps.Split ',' |> List.ofArray |> List.map (fun p -> p.Trim())

            if List.contains "..." ps then
                Error "it uses a pointer to a variadic function"
            else
                let parts = (ps |> List.map (zsType ctx)) @ [ zsType ctx m.Groups[1].Value ]

                match parts |> List.tryPick (function Error e -> Some e | Ok _ -> None) with
                | Some e -> Error e
                | None ->
                    let ts = parts |> List.map (function Ok t -> t | Error _ -> failwith "unreachable")
                    let args, ret = List.take ps.Length ts, List.last ts
                    let args = if args.IsEmpty then [ STName("unit", []) ] else args
                    Ok(STName("fnptr", [ List.foldBack (fun a acc -> STFun(a, acc)) args ret ]))
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

/// What an import produced: declarations, left-out names with reasons, and editor info.
type private Imported =
    { decls: (int * Decl) list
      skipped: (string * string) list
      infos: (string * CInfo) list
      headerFile: string } // the header's full path, as clang found it

/// The comment that documents a header line: a trailing `// ...` on it, else the `//` or
/// `/* */` lines right above it.
let private commentFor (lines: string[]) (line: int) =
    if line < 1 || line > lines.Length then
        ""
    else
        let l = lines[line - 1]
        let i = l.IndexOf "//"

        if i > 0 && l.Substring(0, i).Trim() <> "" then
            l.Substring(i + 2).Trim()
        else
            let above = ResizeArray<string>()
            let mutable j = line - 2

            while j >= 0 && (lines[j].TrimStart().StartsWith "//" || lines[j].TrimStart().StartsWith "*" || lines[j].TrimStart().StartsWith "/*") do
                let t = lines[j].Trim().TrimStart('/', '*').TrimEnd('/', '*').Trim()
                if t <> "" then above.Insert(0, t)
                j <- j - 1

            String.Join("\n", above)

let private importUncached (header: string) (dir: string) : Imported =
    let tmp = Path.Combine(Path.GetTempPath(), "zs-import-" + Guid.NewGuid().ToString("N") + ".c")
    File.WriteAllText(tmp, sprintf "#include \"%s\"\n" header)

    try
        let fail msg = raise (CompileError(0, msg))

        let ast =
            match clang [ "-fsyntax-only"; "-Xclang"; "-ast-dump=json"; "-I"; dir; tmp ] with
            | Ok json -> JsonNode.Parse(json, documentOptions = JsonDocumentOptions(MaxDepth = 10000))
            | Error e -> fail (e.Split('\n') |> Array.head |> fun l -> l.Replace(tmp + ":1:10: ", ""))

        let macros =
            match clang [ "-E"; "-dD"; "-I"; dir; tmp ] with
            | Ok text -> text
            | Error e -> fail e

        let fromHeader (file: string) =
            not (isNull file) && (file = header || file.EndsWith("/" + header) || Path.GetFileName file = Path.GetFileName header)

        // clang's JSON writes a location's file and line only when they change, in document
        // order; every node's own (file, line) is what is in effect after its loc
        let locs = Dictionary<JsonNode, string * int>(HashIdentity.Reference)
        let mutable file: string = null
        let mutable line = 0

        let rec scan (n: JsonNode) =
            match n with
            | :? JsonObject as o ->
                for kv in o do
                    match kv.Key with
                    | "file" when (kv.Value :? JsonValue) -> file <- kv.Value.GetValue<string>()
                    | "line" when (kv.Value :? JsonValue) -> line <- kv.Value.GetValue<int>()
                    | "includedFrom" -> ()
                    | "loc" ->
                        scan kv.Value
                        locs[o] <- (file, line)
                    | _ -> scan kv.Value
            | :? JsonArray as a ->
                for x in a do
                    scan x
            | _ -> ()

        scan ast
        let locOf (n: JsonNode) = match locs.TryGetValue n with | true, l -> l | _ -> (null, 0)

        let ctx =
            { typedefs = Dictionary()
              records = Dictionary()
              enums = HashSet() }

        let decls = ResizeArray<int * Decl>()
        let skipped = ResizeArray<string * string>()
        let infos = ResizeArray<string * CInfo>()
        let defined = HashSet<string>()
        let mutable headerFile = ""
        let headerLines = lazy (try File.ReadAllLines headerFile with _ -> [||])

        let info name csig (line: int) =
            infos.Add(
                name,
                { csig = csig
                  cdoc = commentFor headerLines.Value line
                  cfile = headerFile
                  cline = line }
            )

        let mutable unnamed: (JsonNode * bool) option = None // the last struct without a name

        let addRecord (name: string) (n: JsonNode) (mine: bool) =
            let raw = children n |> List.filter (fun f -> str f "kind" = "FieldDecl")
            let fields = raw |> List.map (fun f -> ident (str f "name"), zsType ctx (qualType f))

            match fields |> List.tryPick (fun (_, t) -> match t with Error e -> Some e | Ok _ -> None) with
            | _ when fields.IsEmpty -> skipped.Add(name, "it has no fields here (an opaque struct; pass it as cptr)")
            | Some e -> skipped.Add(name, "a field: " + e)
            | None when defined.Add name ->
                ctx.records[name] <- fields |> List.map fst

                if mine then
                    let body = RecordTy(fields |> List.map (fun (f, t) -> f, (match t with Ok t -> t | Error _ -> STName("unit", [])), None))
                    decls.Add(0, Attrs([ "CLayout", [] ], TypeDecl(name, [], body, [])))
                    let members = raw |> List.map (fun f -> sprintf "    %s %s;" (qualType f) (str f "name")) |> String.concat "\n"
                    info name (sprintf "typedef struct %s {\n%s\n} %s;" name members name) (snd (locOf n))
            | None -> ()

        for n in children ast do
            let declFile, declLine = locOf n
            let mine = fromHeader declFile

            if mine && headerFile = "" then
                headerFile <- declFile

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
                            info cn (sprintf "%s = %d" cn v) (snd (locOf c))
            | "FunctionDecl" when mine && not (isNull name) && not (defined.Contains name) ->
                let qt = qualType n

                let isStatic = str n "storageClass" = "static"
                let cret = qt.Substring(0, qt.IndexOf '(').Trim()
                let ret = zsType ctx cret
                let parms = children n |> List.filter (fun p -> str p "kind" = "ParmVarDecl")

                let pars =
                    parms
                    |> List.mapi (fun i p ->
                        match zsType ctx (qualType p) with
                        | Ok t -> Ok t
                        | Error e -> Error(sprintf "parameter %d: %s" (i + 1) e))

                let csig =
                    let ps =
                        parms
                        |> List.map (fun p -> match str p "name" with null -> qualType p | pn -> sprintf "%s %s" (qualType p) pn)
                        |> fun ps -> if qt.Contains "..." then ps @ [ "..." ] else ps
                    sprintf "%s %s(%s)" cret name (if ps.IsEmpty then "void" else String.concat ", " ps)

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
                    info name csig declLine
                | Some e, _ -> skipped.Add(name, e)
                | None, Error e -> skipped.Add(name, e)
            | _ -> ()

        // #define constants, attributed to files by clang's line markers
        let mutable mfile = ""

        for mline in macros.Split '\n' do
            let marker = Regex.Match(mline, "^# \\d+ \"([^\"]*)\"")

            if marker.Success then
                mfile <- marker.Groups[1].Value
            elif mline.StartsWith "#define " && fromHeader mfile then
                let m = Regex.Match(mline, @"^#define ([A-Za-z_][A-Za-z0-9_]*)(\(?)\s*(.*)$")

                if m.Success && m.Groups[2].Value = "" then
                    let name = m.Groups[1].Value

                    if not (name.StartsWith "_") && not (keywords.Contains name) && not (defined.Contains name) then
                        match macroValue ctx m.Groups[3].Value with
                        | Some v ->
                            defined.Add name |> ignore
                            decls.Add(0, Const(name, v))
                            if headerFile = "" then headerFile <- mfile
                            let at = headerLines.Value |> Array.tryFindIndex (fun l -> Regex.IsMatch(l, @"^\s*#\s*define\s+" + name + @"\b"))
                            info name (sprintf "#define %s %s" name (m.Groups[3].Value.Trim())) (match at with Some i -> i + 1 | None -> 0)
                        | None -> ()

        { decls = List.ofSeq decls
          skipped = List.ofSeq skipped
          infos = List.ofSeq infos
          headerFile = headerFile }
    finally
        File.Delete tmp

// ---- the on-disk cache: an editor without clang or the header (Zed's Flatpak sandbox) reads
// what the last successful import wrote, in <project>/.zs-cache/cimport/

// a type: "name", [ "name", arguments… ], or { "fun": [ parameter, result ] }
let rec private styJson (t: SType) : JsonNode =
    match t with
    | STName(n, []) -> JsonValue.Create n
    | STName(n, args) -> JsonArray((JsonValue.Create n :> JsonNode) :: (args |> List.map styJson) |> Array.ofList)
    | STFun(a, b) -> JsonObject(dict [ "fun", JsonArray(styJson a, styJson b) :> JsonNode ])
    | _ -> failwith "C import: unexpected type"

let rec private styOf (n: JsonNode) : SType =
    match n with
    | :? JsonArray as a -> STName(a[0].GetValue<string>(), [ for i in 1 .. a.Count - 1 -> styOf a[i] ])
    | :? JsonObject as o ->
        let f = o["fun"].AsArray()
        STFun(styOf f[0], styOf f[1])
    | _ -> STName(n.GetValue<string>(), [])

let rec private exprJson (e: Expr) : JsonNode =
    match e with
    | Lit v -> JsonObject(dict [ "int", JsonValue.Create v :> JsonNode ])
    | FloatLit v -> JsonObject(dict [ "float", JsonValue.Create v :> JsonNode ])
    | StrLit v -> JsonObject(dict [ "string", JsonValue.Create v :> JsonNode ])
    | RecordLit fs -> JsonObject(dict [ "record", JsonArray(fs |> List.map (fun (f, v) -> JsonArray(JsonValue.Create f, exprJson v) :> JsonNode) |> Array.ofList) :> JsonNode ])
    | _ -> failwith "C import: unexpected constant"

let rec private exprOf (n: JsonNode) : Expr =
    let o = n.AsObject()
    if o.ContainsKey "int" then Lit(o["int"].GetValue<int64>())
    elif o.ContainsKey "float" then FloatLit(o["float"].GetValue<float>())
    elif o.ContainsKey "string" then StrLit(o["string"].GetValue<string>())
    else RecordLit(o["record"].AsArray() |> Seq.map (fun p -> p[0].GetValue<string>(), exprOf p[1]) |> List.ofSeq)

let private declJson (d: Decl) : JsonNode =
    let o = JsonObject()

    match d with
    | Extern(name, args, variadic, ret) ->
        o["extern"] <- JsonValue.Create name
        o["args"] <- JsonArray(args |> List.map styJson |> Array.ofList)
        o["variadic"] <- JsonValue.Create variadic
        o["ret"] <- styJson ret
    | Attrs(_, TypeDecl(name, _, RecordTy fields, _)) ->
        o["struct"] <- JsonValue.Create name
        o["fields"] <- JsonArray(fields |> List.map (fun (f, t, _) -> JsonArray(JsonValue.Create f, styJson t) :> JsonNode) |> Array.ofList)
    | Const(name, v) ->
        o["const"] <- JsonValue.Create name
        o["value"] <- exprJson v
    | _ -> failwith "C import: unexpected declaration"

    o

let private declOf (n: JsonNode) : Decl =
    let o = n.AsObject()

    if o.ContainsKey "extern" then
        Extern(o["extern"].GetValue<string>(), o["args"].AsArray() |> Seq.map styOf |> List.ofSeq, o["variadic"].GetValue<bool>(), styOf o["ret"])
    elif o.ContainsKey "struct" then
        let fields = o["fields"].AsArray() |> Seq.map (fun f -> f[0].GetValue<string>(), styOf f[1], None) |> List.ofSeq
        Attrs([ "CLayout", [] ], TypeDecl(o["struct"].GetValue<string>(), [], RecordTy fields, []))
    else
        Const(o["const"].GetValue<string>(), exprOf o["value"])

let private save (file: string) (r: Imported) =
    let o = JsonObject()
    o["decls"] <- JsonArray(r.decls |> List.map (snd >> declJson) |> Array.ofList)
    o["skipped"] <- JsonArray(r.skipped |> List.map (fun (n, why) -> JsonArray(JsonValue.Create n, JsonValue.Create why) :> JsonNode) |> Array.ofList)

    o["infos"] <-
        JsonArray(
            r.infos
            |> List.map (fun (n, i) -> JsonArray(JsonValue.Create n, JsonValue.Create i.csig, JsonValue.Create i.cdoc, JsonValue.Create i.cline) :> JsonNode)
            |> Array.ofList
        )

    Directory.CreateDirectory(Path.GetDirectoryName file) |> ignore
    File.WriteAllText(file, o.ToJsonString())

    // a copy of the header, for go-to-definition where the header isn't installed
    if File.Exists r.headerFile then
        File.Copy(r.headerFile, file.Substring(0, file.Length - ".json".Length), true)

let private load (file: string) : Imported =
    let o = JsonNode.Parse(File.ReadAllText file).AsObject()
    let copy = file.Substring(0, file.Length - ".json".Length) // raylib.h.json -> raylib.h

    { decls = o["decls"].AsArray() |> Seq.map (fun d -> 0, declOf d) |> List.ofSeq
      skipped = o["skipped"].AsArray() |> Seq.map (fun p -> p[0].GetValue<string>(), p[1].GetValue<string>()) |> List.ofSeq
      infos =
        o["infos"].AsArray()
        |> Seq.map (fun p ->
            p[0].GetValue<string>(),
            { csig = p[1].GetValue<string>()
              cdoc = p[2].GetValue<string>()
              cfile = copy
              cline = p[3].GetValue<int>() })
        |> List.ofSeq
      headerFile = copy }

let private memo = Dictionary<string * string, DateTime * Imported>()

/// The header's declarations, recording what was left out and editor info for each name.
/// Cached in memory until the header changes, and on disk in cacheDir for machines where
/// clang or the header is missing.
let importHeader (header: string) (dir: string) (cacheDir: string) : (int * Decl) list =
    let path = Path.Combine(dir, header)
    let stamp = if File.Exists path then File.GetLastWriteTimeUtc path else DateTime.MinValue
    let cacheFile = Path.Combine(cacheDir, Regex.Replace(header, @"[^A-Za-z0-9_.-]", "_") + ".json")

    let r =
        match memo.TryGetValue((header, dir)) with
        | true, (t, r) when t = stamp -> r
        | _ ->
            let r =
                try
                    let r = importUncached header dir
                    (try save cacheFile r with _ -> ())
                    r
                with CompileError(_, msg) ->
                    if File.Exists cacheFile then
                        load cacheFile
                    else
                        raise (
                            CompileError(
                                0,
                                sprintf
                                    "import c \"%s\": %s. Build once where clang and the header are installed (e.g. ./dev zs build); that saves the import in %s for editors"
                                    header
                                    msg
                                    cacheDir
                            )
                        )

            memo[(header, dir)] <- (stamp, r)
            r

    for name, why in r.skipped do
        skippedC[name] <- why

    for name, i in r.infos do
        cInfo[name] <- i

    r.decls
