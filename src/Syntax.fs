module Syntax

open System
open System.Collections.Generic
open System.Globalization
open System.Text

exception CompileError of line: int * msg: string
exception CompileErrorPos of line: int * col: int * msg: string // with a column (parser errors)
exception CompileErrorAt of file: string * line: int * col: int * msg: string // col 0 = unknown

/// Source positions (line, column, length) of AST nodes, by node identity: identifiers,
/// binders, calls (their head) and statements. Kept beside the AST so it stays plain.
let positions = Dictionary<obj, int * int * int>(HashIdentity.Reference)

/// line 0 = "unknown here"; the nearest enclosing statement/declaration fills it in.
let fail line msg = raise (CompileError(line, msg))

type SType =
    | STName of string * SType list
    | STVar of string
    | STTuple of SType list
    | STFun of SType * SType
    | STMeasure of (string * bool * int) list // unit or measure variable (isVar), exponent: m/s^2

type Pat =
    | PWild
    | PIdent of string * Pat option // variable, or constructor with optional payload
    | PInt of int64
    | PBool of bool
    | PUnit
    | PTuple of Pat list
    | POr of Pat * Pat
    | PAs of Pat * string
    | PNamed of (string * Pat) list // constructor fields by name: Rect(h = h)
    | PArgs of Pat list // several atoms after a name: arguments of a parameterized active pattern

type Expr =
    | Lit of int64
    | FloatLit of float
    | BoolLit of bool
    | StrLit of string
    | UnitLit
    | Var of string
    | Call of string * Expr list // named function, constructor, builtin or extern applied to args
    | App of Expr * Expr list // any other expression applied to args
    | Lambda of Param list * Expr
    | Bin of string * Expr * Expr
    | Neg of Expr
    | Not of Expr
    | If of Expr * Expr * Expr option
    | Let of Pat * SType option * Expr * Expr
    | LetFun of string * bool * Param list * SType option * Expr * Expr
    | LetMut of string * SType option * Expr * Expr
    | Assign of Expr * Expr
    | While of Expr * Expr
    | For of string * Expr * Expr option * Expr * Expr // var, from, step, to, body
    | ForIn of string * Expr * Expr // for x in xs do body (list or array)
    | Seq of Expr * Expr
    | Tuple of Expr list
    | RecordLit of (string * Expr) list
    | Update of Expr * (string * Expr) list
    | Field of Expr * string
    | Index of Expr * Expr
    | ArrayLit of Expr list
    | Match of Expr * (Pat * Expr option * Expr) list
    | Question of Expr // e? (only valid where TryBind can be formed)
    | TryBind of Pat * Expr * Expr // let p = e? ; rest  (rest runs only if e is Ok)
    | DeriveCtx of string * Expr // prefixes errors inside a derive expansion ("field name: ...")
    | Measured of Expr * SType // 9.58<s>
    | At of int * Expr // source line, for error messages

and Param = Pat * SType option

type TypeBody =
    | RecordTy of (string * SType * Expr option) list // field, type, default
    | UnionTy of (string * (string option * SType) list) list // case, (field name, type)

type MemberParam =
    { mname: string
      mty: SType option
      optional: bool // ?x
      mdefault: Expr option } // ?x = e

type Member =
    { name: string
      isStatic: bool
      self: string option // v in `member v.Name`
      mpars: MemberParam list option // None: a property
      mret: SType option
      mbody: Expr
      mline: int }

type Decl =
    | Extern of name: string * args: SType list * variadic: bool * ret: SType
    | Fun of name: string * isRec: bool * pars: Param list * ret: SType option * body: Expr
    | TypeDecl of name: string * tparams: string list * TypeBody * Member list
    | TypeExt of name: string * tparams: string list * Member list // type string with member ...
    | Trait of name: string * tparam: string * methods: (string * SType) list
    | Derive of name: string * defs: (int * string * Param list * SType option * Expr) list
    | Attrs of (string * string list) list * Decl // [<Derive(Json); NoEquality>]
    | Private of Decl // let private f / type private T
    | Open of string // open Module
    | ModuleHeader of string // module Name (first line of a file)
    | Impl of traitName: string * head: SType * defs: (int * string * Param list * SType option * Expr) list

/// Rebuilds an expression with f applied to each direct child expression.
let mapExpr (f: Expr -> Expr) (e: Expr) : Expr =
    match e with
    | Lit _
    | FloatLit _
    | BoolLit _
    | StrLit _
    | UnitLit
    | Var _ -> e
    | Call(n, args) -> Call(n, List.map f args)
    | App(h, args) -> App(f h, List.map f args)
    | Lambda(ps, b) -> Lambda(ps, f b)
    | Bin(op, a, b) -> Bin(op, f a, f b)
    | Neg a -> Neg(f a)
    | Not a -> Not(f a)
    | If(c, t, e) -> If(f c, f t, Option.map f e)
    | Let(p, t, v, b) -> Let(p, t, f v, f b)
    | LetFun(n, r, ps, t, b, rest) -> LetFun(n, r, ps, t, f b, f rest)
    | LetMut(x, t, v, b) -> LetMut(x, t, f v, f b)
    | Assign(a, b) -> Assign(f a, f b)
    | While(c, b) -> While(f c, f b)
    | For(x, a, s, b, body) -> For(x, f a, Option.map f s, f b, f body)
    | ForIn(x, xs, b) -> ForIn(x, f xs, f b)
    | Seq(a, b) -> Seq(f a, f b)
    | Tuple xs -> Tuple(List.map f xs)
    | RecordLit fs -> RecordLit(fs |> List.map (fun (n, v) -> n, f v))
    | Update(r, fs) -> Update(f r, fs |> List.map (fun (n, v) -> n, f v))
    | Field(r, n) -> Field(f r, n)
    | Index(a, i) -> Index(f a, f i)
    | ArrayLit xs -> ArrayLit(List.map f xs)
    | Match(s, cases) -> Match(f s, cases |> List.map (fun (p, g, b) -> p, Option.map f g, f b))
    | Question a -> Question(f a)
    | TryBind(p, a, b) -> TryBind(p, f a, f b)
    | DeriveCtx(c, a) -> DeriveCtx(c, f a)
    | Measured(a, m) -> Measured(f a, m)
    | At(l, a) -> At(l, f a)

// ---------------------------------------------------------------- lexer

type Tok =
    | KInt of int64
    | KFloat of float
    | KStr of string
    | KInterp of (bool * string) list // (isExpr, text) parts of $"..."
    | KId of string
    | KTyVar of string
    | KKw of string
    | KSym of string
    | KNewline
    | KIndent
    | KDedent
    | KEof

type Token =
    { tok: Tok
      line: int
      col: int // 1-based; 0 for layout tokens
      len: int
      adj: bool } // no whitespace before it (F#: `f(x)` binds tighter than `f (x)`)

let showTok =
    function
    | KInt n -> string n
    | KFloat f -> string f
    | KStr _
    | KInterp _ -> "string literal"
    | KId s
    | KKw s
    | KSym s -> sprintf "'%s'" s
    | KTyVar s -> "'" + s
    | KNewline -> "end of line"
    | KIndent -> "indented block"
    | KDedent -> "end of block"
    | KEof -> "end of file"

let keywords =
    set
        [ "let"; "rec"; "if"; "then"; "else"; "extern"; "true"; "false"; "not"; "match"; "with"; "when"
          "type"; "of"; "as"; "fun"; "for"; "in"; "do"; "while"; "mutable"; "member"; "static"; "trait"; "impl"; "abstract"; "derive"; "open"; "module"; "private" ]

// longest first
let symbols =
    [ "..."; ".."; "->"; "<-"; "|>"; "|]"; "[|"; "[<"; ">]"; "::"; ">>"; "<>"; "<="; ">="; "&&"; "||"
      "?"; "("; ")"; "{"; "}"; "["; "]"; ","; ";"; "|"; "."; ":"; "="; "<"; ">"; "+"; "-"; "*"; "/"; "%"; "@"; "^" ]

let private unescape ln =
    function
    | 'n' -> '\n'
    | 't' -> '\t'
    | '0' -> '\000'
    | '\\' -> '\\'
    | '"' -> '"'
    | c -> fail ln (sprintf "unknown escape '\\%c'" c)

/// Offside rule: emits KIndent / KDedent / KNewline at line starts outside brackets.
/// A line starting with '|>' continues the previous one; a new line inside '{ }' or '[ ]' acts as ';'.
/// `Upper.name` lexes as one qualified identifier (List.map, Array.length).
/// Comments seen by the last lexComments call: (line, column, text).
let private comments = ResizeArray<int * int * string>()

let rec lex (src: string) : Token[] = lexWith src false

/// The tokens and every `//` comment, for the formatter.
and lexComments (src: string) : Token[] * (int * int * string) list =
    let toks = lexWith src true
    toks, List.ofSeq comments

and private lexWith (src: string) (keepComments: bool) : Token[] =
    if keepComments then
        comments.Clear()

    let toks = ResizeArray<Token>()
    let indents = Stack<int>()
    indents.Push 0
    let brackets = Stack<char>()
    let mutable first = true
    let lines = src.Replace("\r\n", "\n").Split '\n'

    for li in 0 .. lines.Length - 1 do
        let line = lines[li]
        let ln = li + 1
        let mutable i = 0
        let mutable start = 0

        let add t =
            toks.Add
                { tok = t
                  line = ln
                  col = start + 1
                  len = max 1 (i - start)
                  adj = start > 0 && line[start - 1] <> ' ' }

        while i < line.Length && line[i] = ' ' do
            i <- i + 1

        let rest = line.Substring i
        let blank = rest = "" || rest.StartsWith "//"

        if not blank && brackets.Count = 0 && not (rest.StartsWith "|>") then
            if rest[0] = '\t' then
                fail ln "tabs are not allowed for indentation"

            if first then
                if i <> 0 then
                    fail ln "top-level declarations must start at column 1"

                first <- false
            elif i > indents.Peek() then
                indents.Push i
                add KIndent
            else
                while i < indents.Peek() do
                    indents.Pop() |> ignore
                    add KDedent

                if i <> indents.Peek() then
                    fail ln "inconsistent indentation"

                add KNewline
        elif
            not blank
            && brackets.Count > 0
            && (brackets.Peek() = '{' || brackets.Peek() = '[')
            && not (rest.StartsWith "}" || rest.StartsWith "]" || rest.StartsWith "|]")
        then
            match toks[toks.Count - 1].tok with
            | KSym(";" | "{" | "[" | "[|")
            | KKw "with" -> ()
            | _ -> add (KSym ";")

        while i < line.Length do
            let c = line[i]
            start <- i

            if c = ' ' then
                i <- i + 1
            elif c = '/' && i + 1 < line.Length && line[i + 1] = '/' then
                if keepComments then
                    comments.Add(ln, i + 1, line.Substring i)

                i <- line.Length
            elif Char.IsDigit c then
                let s = i

                while i < line.Length && (Char.IsDigit(line[i]) || line[i] = '_') do
                    i <- i + 1

                if i + 1 < line.Length && line[i] = '.' && Char.IsDigit(line[i + 1]) then
                    i <- i + 1

                    while i < line.Length && (Char.IsDigit(line[i]) || line[i] = '_') do
                        i <- i + 1

                    if i < line.Length && (line[i] = 'e' || line[i] = 'E') then
                        i <- i + 1

                        if i < line.Length && (line[i] = '-' || line[i] = '+') then
                            i <- i + 1

                        while i < line.Length && Char.IsDigit(line[i]) do
                            i <- i + 1

                    add (KFloat(Double.Parse(line.Substring(s, i - s).Replace("_", ""), CultureInfo.InvariantCulture)))
                else
                    let ok, n = Int64.TryParse(line.Substring(s, i - s).Replace("_", ""))

                    if not ok then
                        fail ln "integer literal too large"

                    add (KInt n)
            elif c = '\'' && i + 1 < line.Length && Char.IsLetter(line[i + 1]) then
                let s = i + 1
                i <- i + 1

                while i < line.Length && (Char.IsLetterOrDigit(line[i]) || line[i] = '_') do
                    i <- i + 1

                add (KTyVar(line.Substring(s, i - s)))
            elif Char.IsLetter c || c = '_' then
                let s = i

                while i < line.Length && (Char.IsLetterOrDigit(line[i]) || line[i] = '_') do
                    i <- i + 1

                while Char.IsUpper(line[s]) && i + 1 < line.Length && line[i] = '.' && Char.IsLetter(line[i + 1]) do
                    i <- i + 1

                    while i < line.Length && (Char.IsLetterOrDigit(line[i]) || line[i] = '_') do
                        i <- i + 1

                let w = line.Substring(s, i - s)
                add (if keywords.Contains w then KKw w else KId w)
            elif c = '"' || (c = '$' && i + 1 < line.Length && line[i + 1] = '"') then
                let interp = c = '$'
                let parts = ResizeArray<bool * string>()
                let sb = StringBuilder()
                i <- i + (if interp then 2 else 1)

                while i < line.Length && line[i] <> '"' do
                    if line[i] = '\\' && i + 1 < line.Length then
                        i <- i + 1
                        sb.Append(unescape ln (line[i])) |> ignore
                        i <- i + 1
                    elif interp && line[i] = '{' && i + 1 < line.Length && line[i + 1] = '{' then
                        sb.Append '{' |> ignore
                        i <- i + 2
                    elif interp && line[i] = '}' && i + 1 < line.Length && line[i + 1] = '}' then
                        sb.Append '}' |> ignore
                        i <- i + 2
                    elif interp && line[i] = '{' then
                        parts.Add(false, sb.ToString())
                        sb.Clear() |> ignore
                        let s = i + 1
                        let mutable depth = 0
                        i <- i + 1

                        // the hole may itself contain braces: {f { x = 1 }}
                        while i < line.Length && (line[i] <> '}' || depth > 0) do
                            if line[i] = '{' then depth <- depth + 1
                            elif line[i] = '}' then depth <- depth - 1
                            i <- i + 1

                        if i >= line.Length then
                            fail ln "unterminated '{' in interpolated string"

                        parts.Add(true, line.Substring(s, i - s))
                        i <- i + 1
                    else
                        sb.Append(line[i]) |> ignore
                        i <- i + 1

                if i >= line.Length then
                    fail ln "unterminated string literal"

                i <- i + 1

                if interp then
                    parts.Add(false, sb.ToString())
                    add (KInterp(List.ofSeq parts))
                else
                    add (KStr(sb.ToString()))
            else
                let at = i

                let sym =
                    symbols
                    |> List.tryFind (fun s -> at + s.Length <= line.Length && line.Substring(at, s.Length) = s)

                if sym.IsNone then
                    fail ln (sprintf "unexpected character '%c'" c)

                let s = sym.Value

                // F#: `f -x` (space before, none after, following an operand) negates an argument
                let prefixMinus =
                    s = "-"
                    && at > 0
                    && line[at - 1] = ' '
                    && at + 1 < line.Length
                    && line[at + 1] <> ' '
                    && toks.Count > 0
                    && (match toks[toks.Count - 1].tok with
                        | KId _
                        | KInt _
                        | KFloat _
                        | KStr _
                        | KSym(")" | "]" | "|]") -> true
                        | _ -> false)

                match s with
                | "("
                | "{"
                | "[" -> brackets.Push s[0]
                | "[|"
                | "[<" -> brackets.Push '('
                | ")"
                | "}"
                | "]"
                | "|]"
                | ">]" when brackets.Count > 0 -> brackets.Pop() |> ignore
                | _ -> ()

                i <- i + s.Length
                add (KSym(if prefixMinus then "~-" else s))

    for _ in 2 .. indents.Count do
        toks.Add
            { tok = KDedent
              line = lines.Length
              col = 0
              len = 0
              adj = false }

    toks.Add
        { tok = KEof
          line = lines.Length
          col = 0
          len = 0
          adj = false }
    toks.ToArray()

// ---------------------------------------------------------------- parser

let private cons a b = Call("::", [ Tuple [ a; b ] ])

/// Parses a whole program, or (exprOnly) a single expression.
let rec private parseTokens (toks: Token[]) (exprOnly: bool) (track: bool) : (int * Decl) list * Expr option =
    let pos = ref 0
    let peek () = toks[pos.Value].tok
    let peek2 () = toks[min (pos.Value + 1) (toks.Length - 1)].tok
    let line () = toks[pos.Value].line

    /// Records where a node came from (the current token, or a given token index).
    let mark (ti: int) (node: 'n) : 'n =
        if track then
            let t = toks[ti]
            positions[box node] <- (t.line, t.col, t.len)

        node

    let copyPos (fromNode: obj) (node: 'n) : 'n =
        match positions.TryGetValue fromNode with
        | true, p when track -> positions[box node] <- p
        | _ -> ()

        node
    let advance () = pos.Value <- pos.Value + 1
    let err what =
        let t = toks[pos.Value]
        raise (CompileErrorPos(t.line, t.col, sprintf "expected %s, found %s" what (showTok t.tok)))

    let expect t what =
        if peek () = t then advance () else err what

    let isSym s = peek () = KSym s

    let ident () =
        match peek () with
        | KId s ->
            advance ()
            s
        | _ -> err "identifier"

    /// Consumes a case-separating '|', possibly at the start of the next line.
    let nextBar () =
        if peek () = KNewline && peek2 () = KSym "|" then
            advance ()

        if isSym "|" then
            advance ()
            true
        else
            false

    /// Consumes one '>' closing a type argument list, splitting '>>' if needed.
    let closeAngle () =
        match peek () with
        | KSym ">" -> advance ()
        | KSym ">>" -> toks[pos.Value] <- { toks[pos.Value] with tok = KSym ">" }
        | _ -> err "'>'"

    /// A unit of measure: m, m/s^2, kg m/s^2, 'u, 1 (inside <...> after a numeric type).
    let measure () =
        let rec term () : (string * bool * int) list =
            let unitTerm =
                match peek () with
                | KId u ->
                    advance ()
                    [ u, false, 1 ]
                | KTyVar v ->
                    advance ()
                    [ v, true, 1 ]
                | KInt 1L ->
                    advance ()
                    []
                | KSym "(" ->
                    advance ()
                    let m = product ()
                    expect (KSym ")") "')'"
                    m
                | _ -> err "unit of measure"

            if isSym "^" then
                advance ()

                let neg = isSym "-" || isSym "~-"

                if neg then
                    advance ()

                match peek () with
                | KInt k ->
                    advance ()
                    let k = if neg then -(int k) else int k
                    unitTerm |> List.map (fun (u, v, e) -> u, v, e * k)
                | _ -> err "exponent"
            else
                unitTerm

        and product () =
            let mutable m = term ()
            let mutable go = true

            while go do
                match peek () with
                | KSym "*" ->
                    advance ()
                    m <- m @ term ()
                | KSym "/" ->
                    advance ()
                    m <- m @ (term () |> List.map (fun (u, v, e) -> u, v, -e))
                | KId _
                | KTyVar _
                | KSym "(" -> m <- m @ term () // juxtaposition multiplies: kg m
                | _ -> go <- false

            m

        STMeasure(product ())

    let isNumericName n =
        List.contains n [ "int"; "i8"; "i16"; "i32"; "i64"; "u8"; "u16"; "u32"; "u64"; "usize"; "f32"; "f64"; "float"; "c_int" ]

    let rec tyAtom () =
        let t =
            match peek () with
            | KId n when isNumericName n && peek2 () = KSym "<" ->
                advance ()
                advance ()
                let m = measure ()
                closeAngle ()
                STName(n, [ m ])
            | KTyVar v ->
                advance ()
                STVar v
            | KId n ->
                advance ()

                if isSym "<" then
                    advance ()
                    let args = ResizeArray [ ty () ]

                    while isSym "," do
                        advance ()
                        args.Add(ty ())

                    closeAngle ()
                    STName(n, List.ofSeq args)
                else
                    STName(n, [])
            | KSym "(" ->
                advance ()
                let t = ty ()
                expect (KSym ")") "')'"
                t
            | _ -> err "type"

        // postfix application: int list, string option
        let mutable t = t

        while (match peek () with
               | KId _ -> true
               | _ -> false) do
            t <- STName(ident (), [ t ])

        t

    and tupleTy () =
        let first = tyAtom ()

        if isSym "*" then
            let items = ResizeArray [ first ]

            while isSym "*" do
                advance ()
                items.Add(tyAtom ())

            STTuple(List.ofSeq items)
        else
            first

    and ty () =
        let t = tupleTy ()

        if isSym "->" then
            advance ()
            STFun(t, ty ())
        else
            t

    let optTy () =
        if isSym ":" then
            advance ()
            Some(ty ())
        else
            None

    let startsPatAtom t =
        match t with
        | KId _
        | KInt _
        | KSym("-" | "~-")
        | KKw "true"
        | KKw "false"
        | KSym "("
        | KSym "[" -> true
        | _ -> false

    let rec pattern () =
        let mutable p = orPat ()

        while peek () = KKw "as" do
            advance ()
            p <- PAs(p, ident ())

        p

    // before '->', a line starting with '|' continues the or-pattern
    and orPat () =
        let mutable p = tuplePat ()

        while isSym "|" || (peek () = KNewline && peek2 () = KSym "|") do
            if peek () = KNewline then
                advance ()

            advance ()
            p <- POr(p, tuplePat ())

        p

    and tuplePat () =
        let first = consPat ()

        if isSym "," then
            let items = ResizeArray [ first ]

            while isSym "," do
                advance ()
                items.Add(consPat ())

            PTuple(List.ofSeq items)
        else
            first

    and consPat () =
        let head = appPat ()

        if isSym "::" then
            advance ()
            PIdent("::", Some(PTuple [ head; consPat () ]))
        else
            head

    and appPat () =
        match peek () with
        | KId c when c <> "_" && startsPatAtom (peek2 ()) && (Char.IsUpper c[0] || c.Contains ".") ->
            advance ()

            match [ while startsPatAtom (peek ()) do
                        yield patAtom () ] with
            | [ p ] -> PIdent(c, Some p)
            | ps -> PIdent(c, Some(PArgs ps))
        | _ -> patAtom ()

    and patAtom () =
        let t = peek ()

        if not (startsPatAtom t) then
            err "pattern"

        advance ()

        match t with
        | KId "_" -> PWild
        | KId x -> mark (pos.Value - 1) (PIdent(x, None))
        | KInt n -> PInt n
        | KSym("-" | "~-") ->
            match peek () with
            | KInt n ->
                advance ()
                PInt -n
            | _ -> err "integer"
        | KKw "true" -> PBool true
        | KKw "false" -> PBool false
        | KSym "[" ->
            let items = ResizeArray()

            while not (isSym "]") do
                items.Add(pattern ())

                if isSym ";" then
                    advance ()

            advance ()
            List.foldBack (fun p acc -> PIdent("::", Some(PTuple [ p; acc ]))) (List.ofSeq items) (PIdent("[]", None))
        | _ when isSym ")" ->
            advance ()
            PUnit
        | _ when (match peek (), peek2 () with
                  | KId _, KSym "=" -> true
                  | _ -> false) ->
            let fields = ResizeArray()

            while not (isSym ")") do
                let f = ident ()
                expect (KSym "=") "'='"
                fields.Add(f, pattern ())

                if isSym "," || isSym ";" then
                    advance ()
                elif not (isSym ")") then
                    err "',' or ')'"

            advance ()
            PNamed(List.ofSeq fields)
        | _ ->
            let p = pattern ()
            expect (KSym ")") "')'"
            p

    /// A function parameter: x, _, (), (x: T) or (pattern).
    let param () : Param =
        match peek (), peek2 () with
        | KSym "(", KId _ when (toks[min (pos.Value + 2) (toks.Length - 1)].tok = KSym ":") ->
            advance ()
            let xi = pos.Value
            let x = ident ()
            advance ()
            let t = ty ()
            expect (KSym ")") "')'"
            mark xi (PIdent(x, None)), Some t
        | _ -> patAtom (), None

    let startsParam t =
        match t with
        | KId _
        | KSym "("
        | KSym "[" -> true
        | _ -> false

    let parameters () =
        [ while startsParam (peek ()) do
              yield param () ]

    let rec block () =
        if peek () = KIndent then
            advance ()
            let e = seq ()
            expect KDedent "end of block"
            e
        else
            // a one-line block is a statement too, so its errors have a position
            let si = pos.Value
            let ln = line ()
            mark si (At(ln, assignment (expr ())))

    /// `lhs <- rhs` (statements, and single-line blocks such as `then x <- 1`)
    and assignment lhs =
        if isSym "<-" then
            advance ()
            Assign(lhs, expr ())
        else
            lhs

    /// After a binding: the rest of the block.
    and rest ln =
        if peek () <> KNewline then
            fail ln "'let' must be followed by an expression on the next line"

        advance ()
        seq ()

    and seq () =
        let ln = line ()
        let si = pos.Value
        let stmt (ln, e) = mark si (At(ln, e))

        if peek () = KKw "let" then
            advance ()
            let isRec = peek () = KKw "rec"

            if isRec then
                advance ()

            match peek (), peek2 () with
            | KKw "mutable", _ ->
                advance ()
                let x = ident ()
                let ann = optTy ()
                expect (KSym "=") "'='"
                let v = block ()
                stmt(ln, LetMut(x, ann, v, rest ln))
            | KId f, next when (isRec || Char.IsLower f[0] || f[0] = '_') && f <> "_" && startsParam next ->
                let fi = pos.Value
                advance ()
                let ps = parameters ()
                let ret = optTy ()
                expect (KSym "=") "'='"
                let body = block ()
                stmt(ln, mark fi (LetFun(f, isRec, ps, ret, body, rest ln)))
            | _ ->
                let p = pattern ()
                let ann = optTy ()
                expect (KSym "=") "'='"
                let v = block ()

                match v with
                | Question e
                | At(_, Question e) when ann.IsNone -> stmt(ln, TryBind(p, e, rest ln))
                | _ -> stmt(ln, Let(p, ann, v, rest ln))
        else
            match assignment (expr ()) with
            | Question q when peek () = KNewline ->
                advance ()
                stmt(ln, TryBind(PWild, q, seq ()))
            | e ->
                let e = stmt(ln, e)

                if peek () = KNewline then
                    advance ()
                    Seq(e, seq ())
                else
                    e

    and expr () =
        match peek () with
        | KKw "if" ->
            advance ()
            let c = expr ()
            expect (KKw "then") "'then'"
            let t = block ()

            if peek () = KNewline && peek2 () = KKw "else" then
                advance ()

            if peek () = KKw "else" then
                advance ()
                If(c, t, Some(block ()))
            else
                If(c, t, None)
        | KKw "match" ->
            advance ()
            let s = expr ()
            expect (KKw "with") "'with'"
            let indented = peek () = KIndent

            if indented then
                advance ()

            nextBar () |> ignore
            let cases = ResizeArray()
            let mutable go = true

            while go do
                let p = pattern ()

                let guard =
                    if peek () = KKw "when" then
                        advance ()
                        Some(expr ())
                    else
                        None

                expect (KSym "->") "'->'"
                cases.Add(p, guard, block ())
                go <- nextBar ()

            if indented then
                expect KDedent "end of block"

            Match(s, List.ofSeq cases)
        | KKw "fun" ->
            advance ()
            let ps = parameters ()

            if ps.IsEmpty then
                err "parameter"

            expect (KSym "->") "'->'"
            Lambda(ps, block ())
        | KKw "while" ->
            advance ()
            let c = expr ()
            expect (KKw "do") "'do'"
            While(c, block ())
        | KKw "for" ->
            advance ()
            let x = ident ()
            expect (KKw "in") "'in'"
            let a = pipe ()

            if peek () = KKw "do" then
                advance ()
                ForIn(x, a, block ())
            else
                expect (KSym "..") "'..'"
                let b = pipe ()

                let step, b =
                    if isSym ".." then
                        advance ()
                        Some b, pipe ()
                    else
                        None, b

                expect (KKw "do") "'do'"
                For(x, a, step, b, block ())
        | _ -> pipe ()

    // x |> f a  ==>  f a x
    and pipe () =
        let mutable l = compose ()

        while isSym "|>" do
            advance ()

            l <-
                match compose () with
                | Var f as v -> copyPos v (Call(f, [ l ]))
                | Call(f, args) -> Call(f, args @ [ l ])
                | App(h, args) -> App(h, args @ [ l ])
                | f -> App(f, [ l ])

        l

    // f >> g  ==>  fun x -> g (f x)
    and compose () =
        let mutable l = orE ()

        while isSym ">>" do
            advance ()
            let r = orE ()
            l <- Lambda([ PIdent("$c", None), None ], App(r, [ App(l, [ Var "$c" ]) ]))

        l

    and orE () =
        let l = andE ()

        if isSym "||" then
            advance ()
            If(l, BoolLit true, Some(orE ()))
        else
            l

    and andE () =
        let l = cmpE ()

        if isSym "&&" then
            advance ()
            If(l, andE (), Some(BoolLit false))
        else
            l

    and binary ops sub =
        let mutable l = sub ()
        let mutable go = true

        while go do
            match peek () with
            | KSym s when List.contains s ops ->
                advance ()
                l <- Bin(s, l, sub ())
            | _ -> go <- false

        l

    and cmpE () = binary [ "="; "<>"; "<"; ">"; "<="; ">=" ] consE

    // right-associative :: and @
    and consE () =
        let l = addE ()

        if isSym "::" then
            advance ()
            cons l (consE ())
        elif isSym "@" then
            advance ()
            Call("List.append", [ l; consE () ])
        else
            l

    and addE () = binary [ "+"; "-" ] mulE
    and mulE () = binary [ "*"; "/"; "%" ] unary

    and unary () =
        if isSym "-" || isSym "~-" then
            advance ()
            Neg(unary ())
        elif peek () = KKw "not" then
            advance ()
            Not(unary ())
        else
            app ()

    and startsAtom () =
        match peek () with
        | KInt _
        | KFloat _
        | KStr _
        | KInterp _
        | KId _
        | KKw "true"
        | KKw "false"
        | KSym "("
        | KSym "["
        | KSym "[|"
        | KSym "{"
        | KSym "~-" -> true
        | _ -> false

    // `f x?` applies ? to the whole application
    and app () =
        let e =
            match atom () with
            | Var f as v when startsAtom () -> copyPos v (Call(f, [ while startsAtom () do yield atom () ]))
            | head when startsAtom () -> App(head, [ while startsAtom () do yield atom () ])
            | head -> head

        if isSym "?" then
            advance ()
            Question e
        else
            e

    and atom () =
        let mutable e = primary ()

        while isSym "." || (isSym "(" && toks[pos.Value].adj) do
            if isSym "(" then
                // high-precedence application: f(x), x.M(a, b).N
                let arg = primary ()

                e <-
                    match e with
                    | Var f -> copyPos e (Call(f, [ arg ]))
                    | Call(f, args) -> Call(f, args @ [ arg ])
                    | _ -> App(e, [ arg ])
            else
                advance ()

                if isSym "[" then
                    advance ()
                    let i = expr ()
                    expect (KSym "]") "']'"
                    e <- Index(e, i)
                else
                    e <- mark pos.Value (Field(e, ident ()))

        e

    and items close =
        let xs = ResizeArray()

        while not (isSym close) do
            xs.Add(expr ())

            if isSym ";" then
                advance ()
            elif not (isSym close) then
                err (sprintf "';' or '%s'" close)

        advance ()
        List.ofSeq xs

    and primary () =
        if not (startsAtom ()) then
            err "expression"

        let t = peek ()
        let ln = line ()
        advance ()

        // 9.58<s>: a measure right after a number literal
        let measured (lit: Expr) =
            if isSym "<" && toks[pos.Value].adj then
                let save = pos.Value

                try
                    advance ()
                    let m = measure ()

                    if isSym ">" then
                        advance ()
                        Measured(lit, m)
                    else
                        pos.Value <- save
                        lit
                with CompileError _ ->
                    pos.Value <- save
                    lit
            else
                lit

        match t with
        | KInt n -> measured (Lit n)
        | KFloat f -> measured (FloatLit f)
        | KStr s -> StrLit s
        | KInterp parts -> interpolate ln parts
        | KId x -> mark (pos.Value - 1) (Var x)
        | KKw "true" -> BoolLit true
        | KKw "false" -> BoolLit false
        | KSym "{" -> record ()
        | KSym "~-" -> Neg(atom ())
        | KSym "[" -> List.foldBack cons (items "]") (Var "[]")
        | KSym "[|" -> ArrayLit(items "|]")
        | _ when isSym ")" ->
            advance ()
            UnitLit
        | _ ->
            let first = expr ()

            if isSym "," then
                let xs = ResizeArray [ first ]

                while isSym "," do
                    advance ()
                    xs.Add(expr ())

                expect (KSym ")") "')'"
                Tuple(List.ofSeq xs)
            else
                expect (KSym ")") "')'"
                first

    // $"a {x} b"  ==>  "a " + string x + " b"
    and interpolate ln parts =
        parts
        |> List.filter (fun (isExpr, s) -> isExpr || s <> "")
        |> List.map (fun (isExpr, s) ->
            if isExpr then
                let e =
                    try
                        (snd (parseTokens (lex s) true false)).Value
                    with
                    | CompileError(_, msg)
                    | CompileErrorPos(_, _, msg) -> fail ln msg

                Call("string", [ e ])
            else
                StrLit s)
        |> List.fold
            (fun acc e ->
                match acc with
                | None -> Some e
                | Some a -> Some(Bin("+", a, e)))
            None
        |> Option.defaultValue (StrLit "")
        |> fun e -> Bin("+", StrLit "", e) // forces type string

    // after '{':  { f = e; ... }  or  { e with f = e; ... }
    and record () =
        let fields () =
            let items = ResizeArray()
            let mutable go = true

            while go do
                let f = ident ()
                expect (KSym "=") "'='"
                items.Add(f, expr ())

                if isSym ";" then
                    advance ()

                go <- not (isSym "}")

            advance ()
            List.ofSeq items

        match peek (), peek2 () with
        | KId _, KSym "=" -> RecordLit(fields ())
        | _ ->
            let e = expr ()
            expect (KKw "with") "'with'"
            Update(e, fields ())

    let typeBody () =
        if peek () = KKw "member" || peek () = KKw "static" then
            UnionTy [] // only members: a type with no values
        elif isSym "{" then
            advance ()
            let fields = ResizeArray()
            let mutable go = true

            while go do
                let f = ident ()
                expect (KSym ":") "':'"
                let t = ty ()

                let def =
                    if isSym "=" then
                        advance ()
                        Some(expr ())
                    else
                        None

                fields.Add(f, t, def)

                if isSym ";" then
                    advance ()

                go <- not (isSym "}")

            advance ()
            RecordTy(List.ofSeq fields)
        else
            // payload field: optional 'name:' then a type; '*' separates fields
            let field () =
                match peek (), peek2 () with
                | KId n, KSym ":" ->
                    advance ()
                    advance ()
                    Some n, tyAtom ()
                | _ -> None, tyAtom ()

            let cases = ResizeArray()
            nextBar () |> ignore
            let mutable go = true

            while go do
                let c = ident ()
                let fields = ResizeArray()

                if peek () = KKw "of" then
                    advance ()
                    fields.Add(field ())

                    while isSym "*" do
                        advance ()
                        fields.Add(field ())

                cases.Add(c, List.ofSeq fields)
                go <- nextBar ()

            UnionTy(List.ofSeq cases)

    let memberDecl () : Member =
        let ln = line ()
        let isStatic = peek () = KKw "static"

        if isStatic then
            advance ()

        expect (KKw "member") "'member'"

        let self, name =
            if isStatic then
                None, ident ()
            else
                let a = ident ()

                if a.Contains "." then // `V.Name` lexes as one qualified identifier
                    Some(a.Substring(0, a.IndexOf '.')), a.Substring(a.IndexOf '.' + 1)
                else
                    expect (KSym ".") "'.'"
                    Some a, ident ()

        let pars =
            if isSym "(" then
                advance ()
                let ps = ResizeArray()

                while not (isSym ")") do
                    let optional = isSym "?"

                    if optional then
                        advance ()

                    let n = ident ()
                    let t = optTy ()

                    let d =
                        if isSym "=" then
                            if not optional then
                                fail (line ()) (sprintf "a parameter with a default must be optional: write ?%s = ..." n)

                            advance ()
                            Some(expr ())
                        else
                            None

                    ps.Add
                        { mname = n
                          mty = t
                          optional = optional
                          mdefault = d }

                    if isSym "," then advance ()
                    elif not (isSym ")") then err "',' or ')'"

                advance ()
                Some(List.ofSeq ps)
            else
                None

        let ret = optTy ()
        expect (KSym "=") "'='"

        { name = name
          isStatic = isStatic
          self = self
          mpars = pars
          mret = ret
          mbody = block ()
          mline = ln }

    /// Members after a type body: optional `with`, on following (possibly indented) lines.
    let members () =
        let ms = ResizeArray()
        let mutable opened = 0
        let mutable go = true

        while go do
            match peek (), peek2 () with
            | KNewline, KKw("member" | "static" | "with") -> advance ()
            | KIndent, KKw("member" | "static" | "with") ->
                advance ()
                opened <- opened + 1
            | KKw "with", _ -> advance ()
            | KKw("member" | "static"), _ -> ms.Add(memberDecl ())
            | _ -> go <- false

        for _ in 1..opened do
            expect KDedent "end of members"

        List.ofSeq ms

    let rec decl () =
        let ln = line ()

        match peek () with
        | KSym "[<" ->
            // [<Name; Name(arg, arg)>] before a declaration
            advance ()
            let attrs = ResizeArray()

            while not (isSym ">]") do
                let n = ident ()

                let args =
                    match peek () with
                    | KStr a -> // [<Export "name">]
                        advance ()
                        [ a ]
                    | _ ->
                        if isSym "(" then
                            advance ()
                            let xs = ResizeArray()

                            while not (isSym ")") do
                                match peek () with
                                | KId a
                                | KStr a ->
                                    advance ()
                                    xs.Add a
                                | _ -> err "attribute argument"

                                if isSym "," then
                                    advance ()

                            advance ()
                            List.ofSeq xs
                        else
                            []

                attrs.Add(n, args)

                if isSym ";" then
                    advance ()

            advance ()

            if peek () = KNewline then
                advance ()

            let _, d = decl ()
            ln, Attrs(List.ofSeq attrs, d)
        | KKw "open" ->
            advance ()
            ln, Open(ident ())
        | KKw "module" ->
            advance ()
            ln, ModuleHeader(ident ())
        | KKw "derive" ->
            // derive Json = let toJson (x: 'self) = ...
            advance ()
            let name = ident ()
            expect (KSym "=") "'='"
            expect KIndent "indented 'let' definitions"
            let defs = ResizeArray()

            while peek () = KKw "let" do
                let dl = line ()
                advance ()
                let f = ident ()
                let ps = parameters ()
                let ret = optTy ()
                expect (KSym "=") "'='"
                defs.Add(dl, f, ps, ret, block ())

                if peek () = KNewline then
                    advance ()

            expect KDedent "end of derive"
            ln, Derive(name, List.ofSeq defs)
        | KKw "type" when peek2 () = KKw "private" ->
            advance ()
            toks[pos.Value] <- { toks[pos.Value] with tok = KKw "type" }
            let _, d = decl ()
            ln, Private d
        | KKw "type" ->
            advance ()
            let name = ident ()
            let tparams = ResizeArray()

            if isSym "<" then
                advance ()

                let tv () =
                    match peek () with
                    | KTyVar v ->
                        advance ()
                        v
                    | _ -> err "type parameter"

                tparams.Add(tv ())

                while isSym "," do
                    advance ()
                    tparams.Add(tv ())

                closeAngle ()

            if peek () = KKw "with" then
                ln, TypeExt(name, List.ofSeq tparams, members ())
            elif peek () = KNewline || peek () = KEof then
                ln, TypeDecl(name, [], UnionTy [], []) // [<Measure>] type m
            else
                expect (KSym "=") "'='"
                let indented = peek () = KIndent

                if indented then
                    advance ()

                let body = typeBody ()
                let inner = members ()

                if indented then
                    expect KDedent "end of block"

                ln, TypeDecl(name, List.ofSeq tparams, body, inner @ members ())
        | KKw "trait" ->
            // trait Show<'a> = abstract show : 'a -> string ...
            advance ()
            let name = ident ()
            expect (KSym "<") "'<'"

            let tp =
                match peek () with
                | KTyVar v ->
                    advance ()
                    v
                | _ -> err "type parameter"

            closeAngle ()
            expect (KSym "=") "'='"
            expect KIndent "indented 'abstract' declarations"
            let methods = ResizeArray()

            while peek () = KKw "abstract" do
                advance ()
                let m = ident ()
                expect (KSym ":") "':'"
                methods.Add(m, ty ())

                if peek () = KNewline then
                    advance ()

            expect KDedent "end of trait"
            ln, Trait(name, tp, List.ofSeq methods)
        | KKw "impl" ->
            // impl Show<Point> = let show p = ...
            advance ()
            let tr = ident ()
            expect (KSym "<") "'<'"
            let head = ty ()
            closeAngle ()
            expect (KSym "=") "'='"
            expect KIndent "indented 'let' definitions"
            let defs = ResizeArray()

            while peek () = KKw "let" do
                let dl = line ()
                advance ()
                let name = ident ()
                let ps = parameters ()
                let ret = optTy ()
                expect (KSym "=") "'='"
                defs.Add(dl, name, ps, ret, block ())

                if peek () = KNewline then
                    advance ()

            expect KDedent "end of impl"
            ln, Impl(tr, head, List.ofSeq defs)
        | KKw "extern" ->
            // extern name : t1 -> t2 -> ... -> ret
            advance ()
            let name = ident ()
            expect (KSym ":") "':'"

            let item () =
                if isSym "..." then
                    advance ()
                    None
                else
                    Some(tupleTy ())

            let items = ResizeArray [ item () ]

            while isSym "->" do
                advance ()
                items.Add(item ())

            let ret =
                match items[items.Count - 1] with
                | Some t -> t
                | None -> fail ln "'...' cannot be the return type"

            let pars = List.ofSeq items |> List.take (items.Count - 1)
            let variadic = List.contains None pars

            if variadic && List.last pars <> None then
                fail ln "'...' must be the last parameter"

            let args = pars |> List.choose id |> List.filter (fun t -> t <> STName("unit", []))
            ln, Extern(name, args, variadic, ret)
        | KKw "let" ->
            advance ()
            let isRec = peek () = KKw "rec"

            if isRec then
                advance ()

            let isPrivate = peek () = KKw "private"

            if isPrivate then
                advance ()

            // an active pattern: (|Even|Odd|) or (|Int|_|)
            let ni = pos.Value

            let name =
                if isSym "(" && peek2 () = KSym "|" then
                    advance ()
                    advance ()
                    let names = ResizeArray [ ident () ]

                    while isSym "|" && peek2 () <> KSym ")" do
                        advance ()
                        names.Add(ident ())

                    expect (KSym "|") "'|'"
                    expect (KSym ")") "')'"
                    "|" + String.concat "|" names + "|"
                else
                    ident ()
            let ps = parameters ()

            if ps.IsEmpty then
                fail ln "top-level values are not supported yet; write 'let f () = ...'"

            let ret = optTy ()
            expect (KSym "=") "'='"
            let f = mark ni (Fun(name, isRec, ps, ret, block ()))
            ln, (if isPrivate then Private f else f)
        | _ -> err "'let', 'type' or 'extern'"

    if exprOnly then
        let e = expr ()

        if peek () <> KEof then
            err "end of expression"

        [], Some e
    else
        [ while peek () <> KEof do
              yield decl ()

              if peek () = KNewline then advance ()
              elif peek () <> KEof then err "end of line" ],
        None

let parse (toks: Token[]) : (int * Decl) list = fst (parseTokens toks false true)
