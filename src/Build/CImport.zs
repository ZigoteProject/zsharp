/// import c "header.h": a C header's functions, structs, enums and #define constants as Z#
/// declarations (externs, [<CLayout>] records, constants), read through libclang in this process
/// (zsharp/libclang): the translation unit's cursors, and a macro's tokens for its value. Only
/// what the header itself declares is imported, not the headers it includes. Whatever can't cross
/// the C boundary (unions, arrays without a length, static inline functions) is left out, with a
/// reason. The F# compiler's CImport, which ran clang for its JSON AST and its macro listing.
open Syntax

/// What the editor shows for a C name: its C declaration, the comment documenting it, and where
/// it is (the header, or the copy of it saved with the import).
type CInfo = { csig: string; cdoc: string; cfile: string; cline: int }

/// What an import produced: declarations, the names left out with why, editor info, and the
/// header's full path as libclang found it.
type Imported = { decls: list<Ast.DeclShape>; skipped: list<string * string>; infos: list<string * CInfo>; headerFile: string }

// the C types seen so far: typedefs (name to C type), imported structs (their fields), enums
type private Ctx = { typedefs: ref<Map<string, string>>; records: ref<Map<string, list<string>>>; enums: ref<Set<string>> }

let private isWordByte (b: u8) =
  (b >= u8 97 && b <= u8 122) || (b >= u8 65 && b <= u8 90) || (b >= u8 48 && b <= u8 57) || b = u8 95

let private isSpace (b: u8) = b = u8 32 || b = u8 9 || b = u8 10 || b = u8 13

let private isDigit (b: u8) = b >= u8 48 && b <= u8 57

let private qualifiers : Set<string> = Set.ofList [ "const"; "volatile"; "restrict"; "__restrict" ]

// a C type without its qualifiers, its spaces one each
let private normalize (t: string) : string =
  let out = Buffer.empty
  let n = String.length t
  let mutable i = 0
  while i < n do
    let b = String.byte t i
    if isWordByte b then
      let mutable j = i
      while j < n && isWordByte (String.byte t j) do
        j <- j + 1
      let w = String.sub t i (j - i)
      if not (Set.contains w qualifiers) then
        Buffer.push w out
      i <- j
    else if isSpace b then
      Buffer.push " " out
      i <- i + 1
    else
      Buffer.push (String.ofByte b) out
      i <- i + 1
  // runs of spaces as one
  let joined = String.concat (Array.toList (Buffer.toArray out))
  let squeezed = Buffer.empty
  let mutable space = false
  for k in 0 .. String.length joined - 1 do
    let b = String.byte joined k
    if isSpace b then
      space <- true
    else
      if space then
        Buffer.push " " squeezed
      space <- false
      Buffer.push (String.ofByte b) squeezed
  String.trim (String.concat (Array.toList (Buffer.toArray squeezed)))

let private scalars : Map<string, string> =
  let pairs =
    [ ("void", "unit"); ("_Bool", "bool"); ("bool", "bool"); ("char", "i8"); ("signed char", "i8"); ("unsigned char", "u8"); ("short", "i16"); ("short int", "i16")
      ("unsigned short", "u16"); ("unsigned short int", "u16"); ("int", "i32"); ("signed int", "i32"); ("signed", "i32"); ("unsigned int", "u32"); ("unsigned", "u32")
      // the word, like C's long on Linux (LP64 and ILP32)
      ("long", "int"); ("long int", "int"); ("long long", "i64"); ("long long int", "i64"); ("unsigned long", "usize"); ("unsigned long int", "usize")
      ("unsigned long long", "u64"); ("unsigned long long int", "u64"); ("float", "f32"); ("double", "f64") ]
  Map.ofList pairs

let private named (n: string) : result<Ast.SType, string> = Ok(Ast.STName(n, []))

// R (*)(A, B) split as R and "A, B": the last "(*)" followed by a parenthesized end
let private fnPointer (t: string) : option<string * string> =
  let rec from (i: int) : option<string * string> =
    if i < 0 then
      None
    else
      if String.indexOfFrom t "(*)" i = i then
        let k = i
        let rest = String.trimStart (String.sub t (k + 3) (String.length t - k - 3))
        if String.startsWith "(" rest && String.endsWith ")" rest then Some(String.sub t 0 k, String.sub rest 1 (String.length rest - 2)) else from (i - 1)
      else
        from (i - 1)
  from (String.length t - 3)

// T[N] split as T (with what follows the length) and N
let private sized (t: string) : option<string * string> =
  match String.indexOf "[" t with
  | Some i ->
    let mutable j = i + 1
    while j < String.length t && isDigit (String.byte t j) do
      j <- j + 1
    if j > i + 1 && j < String.length t && String.byte t j = u8 93 then
      Some(String.trim (String.sub t 0 i) + String.sub t (j + 1) (String.length t - j - 1), String.sub t (i + 1) (j - i - 1))
    else
      None
  | None -> None

let private firstError (rs: list<result<Ast.SType, string>>) : option<string> =
  List.tryPick (fun (r: result<Ast.SType, string>) -> match r with | Error e -> Some e | Ok _ -> None) rs

let private oks (rs: list<result<Ast.SType, string>>) : list<Ast.SType> =
  List.choose (fun (r: result<Ast.SType, string>) -> match r with | Ok t -> Some t | Error _ -> None) rs

/// A C type as a Z# type, or why it can't be one.
let rec private zsType (ctx: Ctx) (depth: int) (qt: string) : result<Ast.SType, string> =
  let t = normalize qt
  if depth > 20 then
    // typedef struct X X;
    Error $"'{t}' is an opaque struct (pass a pointer to it, as cptr)"
  else
    match Map.tryFind t scalars with
    | Some s -> named s
    | None ->
      if String.contains "(" t then
        // a function pointer, R (*)(A, B): fnptr<A -> B -> R>, or fnptr<unit -> R> for one that
        // takes nothing
        match fnPointer t with
        | Some(r, ps0) when not (String.contains "(" (String.trim ps0)) ->
          let ps1 = String.trim ps0
          let ps = if ps1 = "" || ps1 = "void" then [] else List.map String.trim (String.split "," ps1)
          if List.contains "..." ps then
            Error "it uses a pointer to a variadic function"
          else
            let parts = List.append (List.map (zsType ctx (depth + 1)) ps) [ zsType ctx (depth + 1) r ]
            match firstError parts with
            | Some e -> Error e
            | None ->
              let ts = oks parts
              let args0 = List.take (List.length ps) ts
              let args = if List.isEmpty args0 then [ Ast.STName("unit", []) ] else args0
              Ok(Ast.STName("fnptr", [ List.fold (fun acc a -> Ast.STFun(a, acc)) (List.last ts) (List.rev args) ]))
        | _ -> Error "it uses a function type other than a pointer to a function of C values"
      else
        match sized t with
        | Some(el, n) ->
          // T[N]: N elements inline, fixed<T, N>; int[3][4] is fixed<fixed<i32, 4>, 3>
          match zsType ctx (depth + 1) el with
          | Ok e -> Ok(Ast.STName("fixed", [ e; Ast.STName(n, []) ]))
          | Error e -> Error e
        | None ->
          if String.contains "[" t then Error "it uses an array without a length"
          else if String.endsWith "*" t then
            let pointee = normalize (String.sub t 0 (String.length t - 1))
            named (if pointee = "char" || pointee = "signed char" then "cstr" else "cptr")
          else if String.startsWith "struct " t then zsType ctx (depth + 1) (String.sub t 7 (String.length t - 7))
          else if String.startsWith "enum " t then named "i32"
          else if String.startsWith "union " t then Error "it uses a union"
          else if Map.containsKey t ctx.records.Value then named t
          else if Set.contains t ctx.enums.Value then named "i32"
          else
            match Map.tryFind t ctx.typedefs.Value with
            | Some u when u <> t -> zsType ctx (depth + 1) u
            | _ -> Error $"type '{t}' can't cross the C boundary"

let private isKeyword (n: string) = Token.keyword n <> Token.Id

let private ident (n: string) = if isKeyword n then n + "_" else n

// ---- a #define's body as a constant, when it is a literal (or a struct literal of an imported
// struct)

// the body without one pair of parentheses around it and the spaces inside them, and whether
// it's negated
let private bare (body: string) : bool * string =
  let t0 = String.trim body
  let t1 = if String.startsWith "(" t0 then String.trim (String.sub t0 1 (String.length t0 - 1)) else t0
  let t2 = if String.endsWith ")" t1 then String.trim (String.sub t1 0 (String.length t1 - 1)) else t1
  if String.startsWith "-" t2 then (true, String.trim (String.sub t2 1 (String.length t2 - 1))) else (false, t2)

let private allBytes (p: u8 -> bool) (s: string) =
  let mutable ok = true
  for i in 0 .. String.length s - 1 do
    if not (p (String.byte s i)) then
      ok <- false
  ok

let private isHex (b: u8) = isDigit b || (b >= u8 97 && b <= u8 102) || (b >= u8 65 && b <= u8 70)

// s without the suffix letters in `letters` at its end (any number of them)
let private withoutSuffix (letters: string) (s: string) : string =
  let mutable n = String.length s
  while n > 0 && String.contains (String.ofByte (String.byte s (n - 1))) letters do
    n <- n - 1
  String.sub s 0 n

// 3, 0xFF, 10u, (-1): the value
let private intLiteral (body: string) : option<i64> =
  let (minus, t) = bare body
  let digits = withoutSuffix "uUlL" t
  let value =
    if String.startsWith "0x" digits || String.startsWith "0X" digits then
      let h = String.sub digits 2 (String.length digits - 2)
      if h <> "" && allBytes isHex h then Int.parseRadix 16 h else None
    else if digits <> "" && allBytes isDigit digits then
      let v : option<i64> = Int.parse digits
      v
    else
      None
  Option.map (fun (v: i64) -> if minus then -v else v) value

// 2.5f, 1e3, .5: the value (one suffix letter at most)
let private floatLiteral (body: string) : option<f64> =
  let (minus, t0) = bare body
  let t = if t0 <> "" && String.contains (String.ofByte (String.byte t0 (String.length t0 - 1))) "fFlL" then String.sub t0 0 (String.length t0 - 1) else t0
  // digits.digits, .digits, then an exponent; or digits and an exponent
  let n = String.length t
  let mutable i = 0
  while i < n && isDigit (String.byte t i) do
    i <- i + 1
  let whole = i
  let dot = i < n && String.byte t i = u8 46
  if dot then
    i <- i + 1
    while i < n && isDigit (String.byte t i) do
      i <- i + 1
  let fraction = if dot then i - whole - 1 else 0
  let mutable expOk = true
  let hasExp = i < n && (String.byte t i = u8 101 || String.byte t i = u8 69)
  if hasExp then
    i <- i + 1
    if i < n && (String.byte t i = u8 43 || String.byte t i = u8 45) then
      i <- i + 1
    let start = i
    while i < n && isDigit (String.byte t i) do
      i <- i + 1
    expOk <- i > start
  let shaped = i = n && expOk && ((dot && (whole > 0 || fraction > 0)) || (not dot && whole > 0 && hasExp))
  if shaped then
    let v : option<f64> = Float.parse t
    Option.map (fun (x: f64) -> if minus then -x else x) v
  else
    None

let rec private macroValue (ctx: Ctx) (body0: string) : option<Ast.Expr> =
  let body = String.trim body0
  match intLiteral body with
  | Some v -> Some(Ast.plain (Ast.Lit v))
  | None ->
    match floatLiteral body with
    | Some v -> Some(Ast.plain (Ast.FloatLit v))
    | None ->
      // what's between the first and the last byte (an empty body, a guard's #define, has none)
      let inner = if String.length body >= 2 then String.sub body 1 (String.length body - 2) else ""
      if String.length body >= 2 && String.startsWith "\"" body && String.endsWith "\"" body && not (String.contains "\"" inner) && not (String.contains "\\" inner) then
        Some(Ast.plain (Ast.StrLit inner))
      else
        // (Name){ a, b } or CLITERAL(Name){ a, b }, of an imported struct
        let typeEnd = match String.indexOf ")" body with | Some i -> i | None -> -1
        let start = if String.startsWith "CLITERAL(" body then 9 else if String.startsWith "(" body then 1 else -1
        let rest = if typeEnd > 0 then String.trim (String.sub body (typeEnd + 1) (String.length body - typeEnd - 1)) else ""
        let tname = if start > 0 && typeEnd > start then String.sub body start (typeEnd - start) else ""
        if tname <> "" && allBytes isWordByte tname && String.startsWith "{" rest && String.endsWith "}" rest && not (String.contains "}" (String.sub rest 0 (String.length rest - 1))) then
          match Map.tryFind tname ctx.records.Value with
          | Some fields ->
            let parts = List.filter (fun p -> p <> "") (List.map String.trim (String.split "," (String.sub rest 1 (String.length rest - 2))))
            let values = List.choose (macroValue ctx) parts
            if List.length values = List.length parts && List.length parts = List.length fields then
              Some(Ast.plain (Ast.RecordLit (List.map2 (fun f v -> ({ field = f; nameAt = -1; value = v } : Ast.FieldValue)) fields values)))
            else
              None
          | None -> None
        else
          None

/// The comment that documents a header line: a trailing `// ...` on it, else the `//` or `/* */`
/// lines right above it.
let private commentFor (lines: array<string>) (line: int) : string =
  if line < 1 || line > Array.length lines then
    ""
  else
    let l = lines.[line - 1]
    match String.indexOf "//" l with
    | Some i when i > 0 && String.trim (String.sub l 0 i) <> "" -> String.trim (String.sub l (i + 2) (String.length l - i - 2))
    | _ ->
      let above = ref []
      let mutable j = line - 2
      let commentLine (s: string) =
        let t = String.trimStart s
        String.startsWith "//" t || String.startsWith "*" t || String.startsWith "/*" t
      while j >= 0 && commentLine lines.[j] do
        let t = String.trim lines.[j]
        let mutable a = 0
        while a < String.length t && (String.byte t a = u8 47 || String.byte t a = u8 42) do
          a <- a + 1
        let mutable b = String.length t
        while b > a && (String.byte t (b - 1) = u8 47 || String.byte t (b - 1) = u8 42) do
          b <- b - 1
        let c = String.trim (String.sub t a (b - a))
        if c <> "" then
          above.Value <- c :: above.Value
        j <- j - 1
      String.join "\n" above.Value

// a cursor's spelling, and its type's
let private spelling (c: Libclang.CXCursor) = Libclang.text (clang_getCursorSpelling c)

let private typeText (t: Libclang.CXType) = Libclang.text (clang_getTypeSpelling t)

let private lineOf (c: Libclang.CXCursor) : int =
  let (_, line, _) = Libclang.place (clang_getCursorLocation c)
  line

let private fileOf (c: Libclang.CXCursor) : string =
  let (file, _, _) = Libclang.place (clang_getCursorLocation c)
  file

// a struct, enum or union without a name of its own
let private unnamedSpelling (n: string) = n = "" || String.contains "(unnamed" n || String.contains "(anonymous" n

// an array parameter is a pointer to its first element, as in C: T[N] as T * (as clang prints
// the parameter's type)
let private decayed (t: string) : string =
  match String.indexOf "[" t with
  | Some i ->
    let mutable j = i + 1
    while j < String.length t && isDigit (String.byte t j) do
      j <- j + 1
    if j < String.length t && String.byte t j = u8 93 then String.trimEnd (String.sub t 0 i) + " *" + String.sub t (j + 1) (String.length t - j - 1) else t
  | None -> t

// the declarations of a parsed translation unit (its file includes the header), at the import's
// place `at`
let private declarationsOf (tu: cptr) (header: string) (at: int) : Imported =
  let fromHeader (file: string) = file <> "" && (file = header || String.endsWith ("/" + header) file || Path.getFileName file = Path.getFileName header)
  let ctx : Ctx = { typedefs = ref Map.empty; records = ref Map.empty; enums = ref Set.empty }
  let decls = Buffer.empty
  let skipped = Buffer.empty
  let infos = Buffer.empty
  let defined = ref Set.empty
  let define (n: string) =
    if Set.contains n defined.Value then
      false
    else
      defined.Value <- Set.add n defined.Value
      true
  let headerFile = ref ""
  let headerLines : ref<option<array<string>>> = ref None
  let linesOfHeader () =
    match headerLines.Value with
    | Some ls -> ls
    | None ->
      let ls =
        match File.readAllLines headerFile.Value with
        | Ok xs -> Array.ofList xs
        | Error _ -> [||]
      headerLines.Value <- Some ls
      ls
  let info (name: string) (csig: string) (line: int) =
    Buffer.push (name, { csig = csig; cdoc = commentFor (linesOfHeader ()) line; cfile = headerFile.Value; cline = line }) infos
  let add (shape: Ast.DeclShape) = Buffer.push shape decls
  let children (c: Libclang.CXCursor) = Libclang.children c
  let addRecord (name: string) (n: Libclang.CXCursor) (mine: bool) =
    let kids = children n
    let raw = List.filter (fun (f: Libclang.CXCursor) -> clang_getCursorKind f = CXCursor_FieldDecl) kids
    let fields = List.map (fun (f: Libclang.CXCursor) -> (ident (spelling f), zsType ctx 0 (typeText (clang_getCursorType f)))) raw
    // a union or struct inside it without a name: its fields are the record's, unnamed
    let anonymous (k: Libclang.CXCursor) =
      let kind = clang_getCursorKind k
      (kind = CXCursor_StructDecl || kind = CXCursor_UnionDecl) && unnamedSpelling (spelling k)
    if List.isEmpty fields then
      Buffer.push (name, "it has no fields here (an opaque struct; pass it as cptr)") skipped
    else if List.exists (fun (f, _) -> f = "") fields || List.exists anonymous kids then
      Buffer.push (name, "a field has no name (a union or struct inside it, without one)") skipped
    else
      match firstError (List.map snd fields) with
      | Some e -> Buffer.push (name, "a field: " + e) skipped
      | None ->
        if define name then
          ctx.records.Value <- Map.add name (List.map fst fields) ctx.records.Value
          if mine then
            let field (p: string * result<Ast.SType, string>) : Ast.RecordField =
              let (f, t) = p
              let ty =
                match t with
                | Ok x -> x
                | Error _ -> Ast.STName("unit", [])
              let r : Ast.RecordField = { name = f; fieldAt = -1; ty = ty; default = None }
              r
            add (Ast.Attrs([ ("CLayout", []) ], Ast.decl (Ast.TypeDecl(name, [], Ast.RecordTy (List.map field fields), [])) at))
            let members = String.join "\n" (List.map (fun (f: Libclang.CXCursor) -> $"    {typeText (clang_getCursorType f)} {spelling f};") raw)
            info name $"typedef struct {name} {{\n{members}\n}} {name};" (lineOf n)
  // the last struct without a name, and whether it's the header's: the typedef after it names it
  let unnamed : ref<option<Libclang.CXCursor * bool>> = ref None
  let top = children (clang_getTranslationUnitCursor tu)
  for n in top do
    let (declFile, declLine, _) = Libclang.place (clang_getCursorLocation n)
    let mine = fromHeader declFile
    let kind = clang_getCursorKind n
    if mine && headerFile.Value = "" && kind <> CXCursor_MacroDefinition then
      headerFile.Value <- declFile
    let name = spelling n
    if kind = CXCursor_TypedefDecl then
      let qt = typeText (clang_getTypedefDeclUnderlyingType n)
      // typedef struct { ... } Name; the unnamed struct right before takes the name
      match unnamed.Value with
      | Some(r, m) when name <> "" ->
        unnamed.Value <- None
        addRecord name r m
      | _ ->
        if name <> "" && not (String.contains "(unnamed" qt || String.contains "(anonymous" qt) then
          ctx.typedefs.Value <- Map.add name qt ctx.typedefs.Value
    else if kind = CXCursor_StructDecl then
      if not (List.isEmpty (children n)) then
        if unnamedSpelling name then unnamed.Value <- Some(n, mine) else addRecord name n mine
    else if kind = CXCursor_EnumDecl then
      if not (unnamedSpelling name) then
        ctx.enums.Value <- Set.add name ctx.enums.Value
      for c in children n do
        if clang_getCursorKind c = CXCursor_EnumConstantDecl then
          let v = clang_getEnumConstantDeclValue c
          let cn = spelling c
          if mine && define cn then
            add (Ast.Const(cn, Ast.plain (Ast.Lit v)))
            info cn $"{cn} = {v}" (lineOf c)
    else if kind = CXCursor_FunctionDecl && mine && name <> "" && not (Set.contains name defined.Value) then
      let fty = clang_getCursorType n
      let isStatic = clang_Cursor_getStorageClass n = CX_SC_Static
      let variadic = clang_isFunctionTypeVariadic fty <> u32 0
      let cret = String.trim (typeText (clang_getResultType fty))
      let ret = zsType ctx 0 cret
      let parms = List.init (max 0 (clang_Cursor_getNumArguments n)) (fun i -> clang_Cursor_getArgument n (u32 i))
      let par (i: int) (p: Libclang.CXCursor) =
        match zsType ctx 0 (decayed (typeText (clang_getCursorType p))) with
        | Ok t -> Ok t
        | Error e -> Error $"parameter {i + 1}: {e}"
      let pars = List.mapi par parms
      let csig =
        let shown (p: Libclang.CXCursor) =
          let pn = spelling p
          let pt = decayed (typeText (clang_getCursorType p))
          if pn = "" then pt else $"{pt} {pn}"
        let ps = List.append (List.map shown parms) (if variadic then [ "..." ] else [])
        let list = if List.isEmpty ps then "void" else String.join ", " ps
        $"{cret} {name}({list})"
      let problem =
        if isStatic then Some "it is static (inline), so there is no symbol to call"
        else if isKeyword name then Some "its name is a Z# keyword"
        else
          let retProblem = match ret with | Error e -> [ "the return type: " + e ] | Ok _ -> []
          List.tryHead (List.append retProblem (List.choose (fun (p: result<Ast.SType, string>) -> match p with | Error e -> Some e | Ok _ -> None) pars))
      match (problem, ret) with
      | (None, Ok r) ->
        define name |> ignore
        add (Ast.Extern(name, oks pars, variadic, r))
        info name csig declLine
      | (Some e, _) -> Buffer.push (name, e) skipped
      | (None, Error e) -> Buffer.push (name, e) skipped
  // #define constants: the header's object-like macros whose bodies are literals
  for n in top do
    if clang_getCursorKind n = CXCursor_MacroDefinition then
      let (file, line, _) = Libclang.place (clang_getCursorLocation n)
      let name = spelling n
      if fromHeader file && clang_Cursor_isMacroFunctionLike n = u32 0 && not (String.startsWith "_" name) && not (isKeyword name) && not (Set.contains name defined.Value) then
        // the body as clang -E -dD prints it: its tokens, a space where the source has one
        let body =
          match Libclang.tokens tu n with
          | [] -> ""
          | _ :: ts ->
            let pieces = Buffer.empty
            let mutable last = -1
            for (s, start, stop) in ts do
              if last >= 0 && start > last then
                Buffer.push " " pieces
              Buffer.push s pieces
              last <- stop
            String.concat (Array.toList (Buffer.toArray pieces))
        match macroValue ctx body with
        | Some v ->
          define name |> ignore
          add (Ast.Const(name, v))
          if headerFile.Value = "" then
            headerFile.Value <- file
          info name $"#define {name} {String.trim body}" line
        | None -> ()
  { decls = Array.toList (Buffer.toArray decls); skipped = Array.toList (Buffer.toArray skipped); infos = Array.toList (Buffer.toArray infos); headerFile = headerFile.Value }

// the header parsed through libclang: found next to the importing file (in dir), in a package's
// include directories (flags: -I and pkg-config's flags) or on the system's include path
let private importUncached (header: string) (dir: string) (flags: list<string>) (at: int) : result<Imported, string> =
  if not (Libclang.available ()) then
    Error "libclang isn't installed here"
  else
    match File.createTemp "zs-import-" with
    | Error e -> Error e
    | Ok tmp ->
      File.writeAllText tmp $"#include \"{header}\"\n" |> ignore
      let index = clang_createIndex 0 0
      // clang's own headers (stdbool.h and the like) from the resource directory beside libclang
      let resources = Libclang.resourceDir ()
      let args = List.concat [ [ "-x"; "c"; "-I"; dir ]; (if resources = "" then [] else [ "-resource-dir"; resources ]); flags ]
      let r =
        match Libclang.parse index tmp args (u32 CXTranslationUnit_DetailedPreprocessingRecord) with
        | None -> Error "libclang couldn't parse it"
        | Some tu ->
          let r =
            match Libclang.errors tu with
            | e :: _ -> Error(String.replace e (tmp + ":1:10: ") "")
            | [] -> Ok(declarationsOf tu header at)
          clang_disposeTranslationUnit tu
          r
      clang_disposeIndex index
      File.delete tmp |> ignore
      r

// ---- the on-disk cache: an editor without libclang or the header (Zed's Flatpak sandbox) reads
// what the last successful import wrote, in <project>/.zs-cache/cimport/

// a type: "name", [ "name", arguments… ], or { "fun": [ parameter, result ] }
let rec private styJson (t: Ast.SType) : Json =
  match t with
  | Ast.STName(n, []) -> JString n
  | Ast.STName(n, args) -> JArray(JString n :: List.map styJson args)
  | Ast.STFun(a, b) -> JObject [ ("fun", JArray [ styJson a; styJson b ]) ]
  | _ -> JNull

let rec private styOf (j: Json) : result<Ast.SType, string> =
  match j with
  | JString n -> Ok(Ast.STName(n, []))
  | JArray(JString n :: args) ->
    let ts = List.map styOf args
    match List.tryPick (fun (r: result<Ast.SType, string>) -> match r with | Error e -> Some e | Ok _ -> None) ts with
    | Some e -> Error e
    | None -> Ok(Ast.STName(n, oks ts))
  | JObject [ ("fun", JArray [ a; b ]) ] ->
    match (styOf a, styOf b) with
    | (Ok x, Ok y) -> Ok(Ast.STFun(x, y))
    | _ -> Error "a function type"
  | _ -> Error "a type"

let rec private exprJson (e: Ast.Expr) : Json =
  match e.e with
  | Ast.Lit v -> JObject [ ("int", JInt v) ]
  | Ast.FloatLit v -> JObject [ ("float", JNumber v) ]
  | Ast.StrLit v -> JObject [ ("string", JString v) ]
  | Ast.RecordLit fs -> JObject [ ("record", JArray(List.map (fun (f: Ast.FieldValue) -> JArray [ JString f.field; exprJson f.value ]) fs)) ]
  | _ -> JNull

let rec private exprOf (j: Json) : option<Ast.Expr> =
  match j with
  | JObject [ ("int", JInt v) ] -> Some(Ast.plain (Ast.Lit v))
  | JObject [ ("float", JNumber v) ] -> Some(Ast.plain (Ast.FloatLit v))
  | JObject [ ("float", JInt v) ] -> Some(Ast.plain (Ast.FloatLit(float v)))
  | JObject [ ("string", JString v) ] -> Some(Ast.plain (Ast.StrLit v))
  | JObject [ ("record", JArray ps) ] ->
    let field (p: Json) =
      match p with
      | JArray [ JString f; v ] -> Option.map (fun x -> ({ field = f; nameAt = -1; value = x } : Ast.FieldValue)) (exprOf v)
      | _ -> None
    let fs = List.choose field ps
    if List.length fs = List.length ps then Some(Ast.plain (Ast.RecordLit fs)) else None
  | _ -> None

let private declJson (d: Ast.DeclShape) : Json =
  match d with
  | Ast.Extern(name, args, variadic, ret) -> JObject [ ("extern", JString name); ("args", JArray(List.map styJson args)); ("variadic", JBool variadic); ("ret", styJson ret) ]
  | Ast.Attrs(_, { d = Ast.TypeDecl(name, _, Ast.RecordTy fields, _) }) ->
    JObject [ ("struct", JString name); ("fields", JArray(List.map (fun (f: Ast.RecordField) -> JArray [ JString f.name; styJson f.ty ]) fields)) ]
  | Ast.Const(name, v) -> JObject [ ("const", JString name); ("value", exprJson v) ]
  | _ -> JNull

let private declOf (at: int) (j: Json) : option<Ast.DeclShape> =
  match j with
  | JObject [ ("extern", JString name); ("args", JArray args); ("variadic", JBool variadic); ("ret", ret) ] ->
    let ts = List.map styOf args
    match (List.length (oks ts) = List.length ts, styOf ret) with
    | (true, Ok r) -> Some(Ast.Extern(name, oks ts, variadic, r))
    | _ -> None
  | JObject [ ("struct", JString name); ("fields", JArray fs) ] ->
    let field (f: Json) : option<Ast.RecordField> =
      match f with
      | JArray [ JString n; t ] ->
        match styOf t with
        | Ok ty ->
          let f : Ast.RecordField = { name = n; fieldAt = -1; ty = ty; default = None }
          Some f
        | Error _ -> None
      | _ -> None
    let fields = List.choose field fs
    if List.length fields = List.length fs then Some(Ast.Attrs([ ("CLayout", []) ], Ast.decl (Ast.TypeDecl(name, [], Ast.RecordTy fields, [])) at)) else None
  | JObject [ ("const", JString name); ("value", v) ] -> Option.map (fun e -> Ast.Const(name, e)) (exprOf v)
  | _ -> None

let private save (file: string) (r: Imported) : unit =
  let info (p: string * CInfo) =
    let (n, i) = p
    JArray [ JString n; JString i.csig; JString i.cdoc; JInt(i64 i.cline) ]
  let skip (p: string * string) =
    let (n, why) = p
    JArray [ JString n; JString why ]
  let fields = [ ("decls", JArray(List.map declJson r.decls)); ("skipped", JArray(List.map skip r.skipped)); ("infos", JArray(List.map info r.infos)) ]
  let o = JObject fields
  Tools.makeDirectory (Path.getDirectoryName file)
  File.writeAllText file (Json.print o) |> ignore
  // a copy of the header, for go-to-definition where the header isn't installed
  if File.exists r.headerFile then
    File.copy r.headerFile (String.sub file 0 (String.length file - 5)) |> ignore

let private load (file: string) (at: int) : result<Imported, string> =
  // raylib.h.json beside raylib.h
  let copy = String.sub file 0 (String.length file - 5)
  match File.readAllText file with
  | Error e -> Error e
  | Ok text ->
    match Json.parse text with
    | Ok(JObject [ ("decls", JArray ds); ("skipped", JArray ss); ("infos", JArray is) ]) ->
      let decls = List.choose (declOf at) ds
      let skip (s: Json) =
        match s with
        | JArray [ JString n; JString why ] -> Some(n, why)
        | _ -> None
      let info (s: Json) =
        match s with
        | JArray [ JString n; JString csig; JString cdoc; JInt line ] -> Some(n, { csig = csig; cdoc = cdoc; cfile = copy; cline = int line })
        | _ -> None
      if List.length decls = List.length ds then Ok { decls = decls; skipped = List.choose skip ss; infos = List.choose info is; headerFile = copy } else Error $"{file} isn't a saved import"
    | _ -> Error $"{file} isn't a saved import"

/// Where a header's import is saved in cacheDir.
let cacheFile (header: string) (cacheDir: string) : string =
  let piece (i: int) =
    let b = String.byte header i
    if isWordByte b || b = u8 46 || b = u8 45 then String.ofByte b else "_"
  let safe = String.concat (List.init (String.length header) piece)
  Path.combine cacheDir (safe + ".json")

/// The declarations of a header found next to the importing file (in `dir`), in a package's
/// include directories (`flags`: -I and pkg-config's flags) or on the system's include path, at
/// the import's place `at`. Saved in cacheDir for machines where libclang or the header is
/// missing, which read it from there.
let importHeader (header: string) (dir: string) (flags: list<string>) (cacheDir: string) (at: int) : result<Imported, string> =
  let saved = cacheFile header cacheDir
  match importUncached header dir flags at with
  | Ok r ->
    save saved r
    Ok r
  | Error msg ->
    if File.exists saved then
      load saved at
    else
      Error $"import c \"{header}\": {msg}. Build once where libclang and the header are installed (e.g. ./dev zs build); that saves the import in {cacheDir} for editors"
