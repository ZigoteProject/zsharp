/// `import c` on the providers' protocol (proposal 0001, question 2): a header's declarations as
/// Z# source, from the same libclang reading `import c` does, so `zs provide c raylib.h` prints
/// an ejectable binding and `module Ray = import c "raylib.h"` is a module like a provided one.
/// Each declaration carries the C signature and comment as its `///` doc; the names left out
/// are listed with why. The bare `import c` keeps its own path (the declarations in place, with
/// `[<Link>]` and the editor's C hover).

let rec private styText (t: Syntax.Ast.SType) : string =
  match t with
  | Syntax.Ast.STName(n, []) -> n
  | Syntax.Ast.STName(n, args) -> n + "<" + String.join ", " (List.map styText args) + ">"
  | Syntax.Ast.STFun(a, b) ->
    let left =
      match a with
      | Syntax.Ast.STFun _ -> "(" + styText a + ")"
      | _ -> styText a
    left + " -> " + styText b
  | _ -> "_"

let rec private exprText (e: Syntax.Ast.Expr) : option<string> =
  match e.e with
  | Syntax.Ast.Lit v -> Some(string v)
  | Syntax.Ast.FloatLit v ->
    let s = string v
    Some(if String.contains "." s || String.contains "e" s || String.contains "n" s then s else s + ".0")
  | Syntax.Ast.StrLit v -> Some(Provide.Names.literal v)
  | Syntax.Ast.RecordLit fs ->
    let fields = List.map (fun (f: Syntax.Ast.FieldValue) -> Option.map (fun (v: string) -> f.field + " = " + v) (exprText f.value)) fs
    if List.forall Option.isSome fields then Some("{ " + String.join "; " (List.map Option.get fields) + " }") else None
  | _ -> None

// a declaration's /// lines: its C signature, then its comment's lines
let private docOf (infos: list<string * Build.CImport.CInfo>) (name: string) : list<string> =
  match List.tryFind (fun (ni: string * Build.CImport.CInfo) -> fst ni = name) infos with
  | Some(_, i) ->
    // the signature on one line (a struct's spans several), and the comment's lines each on its
    // own: the header's text (or a saved import's) never leaves its comment
    let oneLine = String.join " " (List.filter (fun (w: string) -> w <> "") (String.split " " (Provide.Names.oneLine i.csig)))
    let sig = if oneLine = "" then [] else [ "/// `" + oneLine + "`" ]
    let doc = List.map (fun (l: string) -> "/// " + Provide.Names.oneLine l) (List.filter (fun (l: string) -> l <> "") (List.map String.trim (String.split "\n" i.cdoc)))
    List.append sig (if List.isEmpty sig || List.isEmpty doc then doc else "///" :: doc)
  | None -> []

let private declText (infos: list<string * Build.CImport.CInfo>) (d: Syntax.Ast.DeclShape) : list<string> =
  match d with
  | Syntax.Ast.Extern(name, args, variadic, ret) ->
    let parts = List.append (List.map styText args) (if variadic then [ "..." ] else [])
    List.append (docOf infos name) [ "extern " + name + " : " + String.join " -> " (List.append parts [ styText ret ]); "" ]
  | Syntax.Ast.Attrs(_, inner) ->
    match inner.d with
    | Syntax.Ast.TypeDecl(name, _, Syntax.Ast.RecordTy fields, _) ->
      let field (f: Syntax.Ast.RecordField) = Provide.Names.fieldName f.name + ": " + styText f.ty
      List.append (docOf infos name) [ "[<CLayout>]"; "type " + name + " = { " + String.join "; " (List.map field fields) + " }"; "" ]
    | Syntax.Ast.TypeDecl(name, _, Syntax.Ast.UnionTy cases, _) ->
      let case (c: Syntax.Ast.Case) =
        match c.fields with
        | [] -> "  | " + c.case
        | fs -> "  | " + c.case + " of " + String.join " * " (List.map (fun (nf: option<string> * Syntax.Ast.SType) -> styText (snd nf)) fs)
      List.concat [ docOf infos name; [ "[<CLayout>]"; "type " + name + " =" ]; List.map case cases; [ "" ] ]
    | _ -> []
  | Syntax.Ast.Const(name, v) ->
    match exprText v with
    | Some text -> List.append (docOf infos name) [ "let " + name + " = " + text; "" ]
    | None -> [ "// " + name + ": a constant zs provide can't write"; "" ]
  | _ -> []

/// The module for `header`, found next to `dir`, in a package's include directories (`flags`) or
/// on the system's include path, read by libclang (or from `cacheDir`'s saved import where it
/// isn't installed): its declarations as Z#, in the header's order.
let provide (header: string) (dir: string) (flags: list<string>) (cacheDir: string) : result<string, string> =
  match Build.CImport.importHeader header dir flags cacheDir (-1) with
  | Error e -> Error e
  | Ok r ->
    let input = if r.headerFile = "" then header else Path.getRelativePath dir r.headerFile
    let skipped = List.map (fun (nw: string * string) -> Provide.Names.oneLine ("// left out: " + fst nw + " (" + snd nw + ")")) r.skipped
    let header = List.concat [ [ Provide.Names.oneLine ("// provided by c 0.1 from " + header); Provide.Names.oneLine ("// input: " + input); "" ]; skipped; (if List.isEmpty skipped then [] else [ "" ]) ]
    Ok(String.join "\n" (List.append header (List.collect (declText r.infos) r.decls)))
