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
    /// A function's result with its effects: `T / E`, `T / <E, F | 'e>` (labels, the row
    /// variable it ends in). The result of a function type, or a function's annotated result.
    | STRow of SType * SType list * string option

type Pat =
    | PWild
    | PIdent of string * Pat option // variable, or constructor with optional payload
    | PInt of int64
    | PChar of int
    | PStr of string // "open": compared with =
    | PBool of bool
    | PUnit
    | PTuple of Pat list
    | POr of Pat * Pat
    | PAs of Pat * string
    | PNamed of (string * Pat) list // constructor fields by name: Rect(h = h)
    | PRecord of (string * Pat) list // { x = 0; y = y }: fields left out match anything
    | PArgs of Pat list // several atoms after a name: arguments of a parameterized active pattern

type Expr =
    | Lit of int64
    | CharLit of int
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
    | LetRecGroup of Expr list * Expr // let rec f … and g …: the members are LetFun nodes (their rest unused), then the rest
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
    | Slice of Expr * Expr option * Expr option // a.[i..j], a.[..j], a.[i..]
    | ArrayLit of Expr list
    | Match of Expr * (Pat * Expr option * Expr) list
    | Question of Expr // e? (only valid where TryBind can be formed)
    | TryBind of Pat * Expr * Expr // let p = e? ; rest  (rest runs only if e is Ok)
    | DeriveCtx of string * Expr // prefixes errors inside a derive expansion ("field name: ...")
    | Measured of Expr * SType // 9.58<s>
    | Typed of Expr * SType // (e: T)
    | Unsafe of Expr // unsafe e: raw pointers and C function pointers allowed inside
    | ListComp of isArray: bool * body: Expr // [ for x in xs -> e ], [| … |]: its body yields
    | Yield of Expr // yield e, in a list expression's body
    | YieldAll of Expr // yield! xs: each of xs
    /// handle e with | E.op p…, k -> b | return p -> b: the operations' clauses (the operation's
    /// qualified name, its arguments' patterns, the resumption's name) and the return clause
    | Handle of Expr * (string * Pat list * string * Expr) list * (Pat * Expr) option
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
    | FunGroup of (int * Decl) list // let rec f … and g …: Fun declarations (maybe Private) that may call each other
    | TypeDecl of name: string * tparams: string list * TypeBody * Member list
    | TypeExt of name: string * tparams: string list * Member list // type string with member ...
    | Trait of name: string * tparam: string * methods: (string * SType) list
    /// effect E<'a> = abstract op : T -> R …: operations a handler gives meaning to
    | Effect of name: string * tparams: string list * ops: (string * SType) list
    | Derive of name: string * defs: (int * string * Param list * SType option * Expr) list
    /// derive Json = ToJson, FromJson: applying it applies each
    | DeriveGroup of name: string * members: string list
    | Attrs of (string * string list) list * Decl // [<Derive(Json); NoEquality>]
    | Private of Decl // let private f / type private T
    | Open of string // open Module
    | ModuleHeader of string // module Name (first line of a file)
    | NestedModule of name: string * decls: (int * Decl) list // module Name = followed by indented declarations
    | Impl of traitName: string * head: SType * defs: (int * string * Param list * SType option * Expr) list
    | ImportC of header: string // import c "raylib.h", replaced by the header's declarations
    | Const of name: string * value: Expr // a C constant (enum value, #define): its uses are the literal
    | Value of name: string * ann: SType option * value: Expr // let name = expr at the top level

/// C names an `import c` left out, with the reason (shown when a program uses one).
let skippedC = System.Collections.Generic.Dictionary<string, string>()

/// What an editor shows for an imported C name: its C declaration, the header's comment for
/// it, and where it is declared.
type CInfo =
    { csig: string
      cdoc: string
      cfile: string
      cline: int }

let cInfo = System.Collections.Generic.Dictionary<string, CInfo>()

/// Rebuilds an expression with f applied to each direct child expression.
let mapExpr (f: Expr -> Expr) (e: Expr) : Expr =
    match e with
    | Lit _
    | CharLit _
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
    | LetRecGroup(fs, rest) -> LetRecGroup(List.map f fs, f rest)
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
    | Slice(a, i, j) -> Slice(f a, Option.map f i, Option.map f j)
    | ArrayLit xs -> ArrayLit(List.map f xs)
    | Match(s, cases) -> Match(f s, cases |> List.map (fun (p, g, b) -> p, Option.map f g, f b))
    | Question a -> Question(f a)
    | TryBind(p, a, b) -> TryBind(p, f a, f b)
    | DeriveCtx(c, a) -> DeriveCtx(c, f a)
    | Measured(a, m) -> Measured(f a, m)
    | Typed(a, t) -> Typed(f a, t)
    | Unsafe a -> Unsafe(f a)
    | ListComp(isArray, b) -> ListComp(isArray, f b)
    | Yield a -> Yield(f a)
    | YieldAll a -> YieldAll(f a)
    | Handle(b, cls, r) -> Handle(f b, cls |> List.map (fun (op, ps, k, c) -> op, ps, k, f c), r |> Option.map (fun (p, c) -> p, f c))
    | At(l, a) -> At(l, f a)

// ---------------------------------------------------------------- lexer

type Tok =
    | KInt of int64
    | KFloat of float
    | KStr of string
    | KInterp of (bool * string * int) list // (isExpr, text, 1-based column) parts of $"..."
    | KId of string
    | KTyVar of string
    | KChar of int // 'a', '\n', '\u{e9}': a Unicode scalar value
    | KKw of string
    | KSym of string
    | KNewline
    | KIndent
    | KDedent
    | KEof

/// What lies between tokens (0019): a token's trailing trivia runs to the end of its line, its
/// newline included; the rest (own-line comments, blank lines, indentation) leads the next token.
type Trivia =
    | Space of string // spaces and tabs
    | Newline
    | Comment of string // "// …", without its newline
    | DocComment of string // "/// …": what hover and zs doc show

type Token =
    { tok: Tok
      line: int
      col: int // 1-based; 0 for layout tokens
      len: int
      adj: bool // no whitespace before it (F#: `f(x)` binds tighter than `f (x)`)
      last: int // the line it ends on: a later one for a string that spans lines
      offset: int // in the source with "\r\n" read as "\n"
      text: string // as written; "" for a layout token (and the `;` a line break makes in { } or [ ])
      lead: Trivia list
      trail: Trivia list }

/// The lossless syntax tree (0019): every token in source order, with its trivia, under nodes by
/// kind (one per construct). Its tokens' text and trivia, in order, are the file's text.
type Node =
    { kind: string
      children: Child[] }

and Child =
    | T of Token
    | N of Node

let triviaText =
    function
    | Space s
    | Comment s
    | DocComment s -> s
    | Newline -> "\n"

/// A node's tokens, in source order.
let rec tokensOf (n: Node) : Token seq =
    seq {
        for c in n.children do
            match c with
            | T t -> yield t
            | N m -> yield! tokensOf m
    }

/// The source text a tree was parsed from, byte for byte.
let treeText (n: Node) =
    let sb = StringBuilder()

    for t in tokensOf n do
        for x in t.lead do
            sb.Append(triviaText x) |> ignore

        sb.Append t.text |> ignore

        for x in t.trail do
            sb.Append(triviaText x) |> ignore

    sb.ToString()

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
    | KChar _ -> "character literal"
    | KNewline -> "end of line"
    | KIndent -> "indented block"
    | KDedent -> "end of block"
    | KEof -> "end of file"

let keywords =
    set
        [ "let"; "rec"; "if"; "then"; "else"; "extern"; "true"; "false"; "not"; "match"; "with"; "when"
          "type"; "of"; "as"; "fun"; "function"; "for"; "in"; "do"; "while"; "mutable"; "member"; "static"; "trait"; "impl"; "abstract"; "derive"; "open"; "module"; "namespace"; "private"; "and"; "unsafe"
          "effect"; "handle" ]

// longest first
let symbols =
    [ "&&&="; "|||="; "^^^="; "&&&"; "|||"; "^^^"; "<<<"; ">>>"; "~~~"; "..."; ".."; "->"; "<-"; "+="; "-="; "*="; "/="; "%="; "|>"; "|]"; "[|"; "[<"; ">]"; "::"; ">>"; "<>"; "<="; ">="; "&&"; "||"
      "?"; "("; ")"; "{"; "}"; "["; "]"; ","; ";"; "|"; "."; ":"; "="; "<"; ">"; "+"; "-"; "*"; "/"; "%"; "@"; "^" ]

/// Compound assignment (`x += e`): the operator each applies.
let compoundOps = dict [ "+=", "+"; "-=", "-"; "*=", "*"; "/=", "/"; "%=", "%"; "&&&=", "&&&"; "|||=", "|||"; "^^^=", "^^^" ]

let private symbolSet = set symbols
let private opChars = set "!%&*+-./<=>?@^|~$"

/// The built-in binary operators that `(op)` turns into a function: (+) is fun a b -> a + b.
let private builtinOperators =
    set [ "+"; "-"; "*"; "/"; "%"; "="; "<>"; "<"; ">"; "<="; ">="; "&&&"; "|||"; "^^^"; "<<<"; ">>>"; "@"; "::" ]
let isOpChar (c: char) = opChars.Contains c

/// The run of operator characters at line[at], stopping at a // comment or a $"…" string.
let private opRun (line: string) (at: int) =
    let mutable j = at

    while j < line.Length
          && isOpChar line[j]
          && not (line[j] = '/' && j + 1 < line.Length && line[j + 1] = '/')
          && not (line[j] = '$' && j + 1 < line.Length && line[j + 1] = '"') do
        j <- j + 1

    line.Substring(at, j - at)

/// A custom operator: operator characters that aren't one of the language's own symbols,
/// such as >>=, <|> or .>>.
let isCustomOp (s: string) =
    s <> "" && not (symbolSet.Contains s) && Seq.forall isOpChar s && not (Seq.forall ((=) '.') s)

/// A prefix operator, as in F#: a custom operator starting with ! (but not !=) or ~, as in
/// !r or ~~x. It binds tighter than application: f !x is f (!x).
let isPrefixOp (s: string) =
    isCustomOp s && ((s.StartsWith "!" && not (s.StartsWith "!=")) || s.StartsWith "~")

/// A custom operator written between its operands.
let isInfixOp (s: string) = isCustomOp s && not (isPrefixOp s)

/// How tightly a custom operator binds, from its first character after any dots, as in F#:
/// 0 with |> and the comparisons (< > = | & $ ? and !=), 1 with :: (@ ^, right-associative),
/// 2 with + (+ -), 3 with * (* / %), 4 power (**, right-associative).
let opLevel (s: string) =
    let t = s.TrimStart '.'

    if t.StartsWith "**" then
        4
    else
        match t[0] with
        | '@'
        | '^' -> 1
        | '+'
        | '-' -> 2
        | '*'
        | '/'
        | '%' -> 3
        | _ -> 0

/// A line starting with |> or an infix custom operator continues the previous one.
let private continuesLine (rest: string) =
    let run = opRun rest 0
    run.StartsWith "|>" || isInfixOp run

/// An escape after a backslash at line[i]: its code point and the index after it. \n \r \t \0
/// \\ \" \' and \u{hex} (any Unicode scalar value).
let private unescapeAt ln (line: string) (i: int) : int * int =
    match line[i] with
    | 'n' -> 10, i + 1
    | 'r' -> 13, i + 1
    | 't' -> 9, i + 1
    | '0' -> 0, i + 1
    | '\\' -> int '\\', i + 1
    | '"' -> int '"', i + 1
    | '\'' -> int '\'', i + 1
    | 'u' when i + 1 < line.Length && line[i + 1] = '{' ->
        let close = line.IndexOf('}', i + 2)

        if close < 0 then
            fail ln "unterminated \\u{…} escape"

        let hex = line.Substring(i + 2, close - i - 2)

        match Int32.TryParse(hex, NumberStyles.HexNumber, CultureInfo.InvariantCulture) with
        | true, v when hex <> "" && v <= 0x10FFFF && not (v >= 0xD800 && v <= 0xDFFF) -> v, close + 1
        | _ -> fail ln (sprintf "\\u{%s} is not a Unicode scalar value" hex)
    | c -> fail ln (sprintf "unknown escape '\\%c'" c)

/// Offside rule: emits KIndent / KDedent / KNewline at line starts outside brackets. Inside one,
/// a line ending in -> (or then, else, do) and a deeper line after it open a block there too:
/// `(fun x ->` with its body below; such blocks end at a line left of them or at the closer.
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
    // per bracket: the indentation of the blocks open inside it (empty while there are none)
    let frames = Stack<Stack<int>>()
    let mutable lastIndent = 0 // of the last line with code
    let mutable resume: (int * int) option = None // a string that spans lines ends here: lexing goes on at (line index, column)
    let mutable first = true
    let text = src.Replace("\r\n", "\n")
    let lines = text.Split '\n'
    // where each line starts in the text
    let lineStart = Array.zeroCreate (lines.Length + 1)

    for li in 0 .. lines.Length - 1 do
        lineStart[li + 1] <- lineStart[li] + lines[li].Length + 1

    for li in 0 .. lines.Length - 1 do
        let line = lines[li]
        let ln = li + 1
        let mutable i = 0
        let mutable start = 0

        let token t written =
            toks.Add
                { tok = t
                  line = ln
                  col = start + 1
                  len = max 1 (i - start)
                  adj = start > 0 && line[start - 1] <> ' '
                  last = ln
                  offset = lineStart[li] + (if written then start else i)
                  text = (if written then line.Substring(start, i - start) else "")
                  lead = []
                  trail = [] }

        // a token as written, from start to i
        let add t = token t true
        // a layout token (or the `;` a line break makes), at i, with no text
        let layout t = token t false

        // a line inside a string that spans lines, or the line where one ends (lexing goes on
        // after it); neither starts a line of code
        let inString, resumeCol =
            match resume with
            | Some(rl, _) when li < rl -> true, -1
            | Some(rl, col) when li = rl ->
                resume <- None
                false, col
            | _ -> false, -1

        while i < line.Length && line[i] = ' ' do
            i <- i + 1

        let rest = line.Substring i
        let blank = rest = "" || rest.StartsWith "//" || inString || resumeCol >= 0

        if not blank && brackets.Count = 0 && not (continuesLine rest) then
            if rest[0] = '\t' then
                fail ln "tabs are not allowed for indentation"

            if first then
                if i <> 0 then
                    fail ln "top-level declarations must start at column 1"

                first <- false
            elif i > indents.Peek() then
                indents.Push i
                layout KIndent
            else
                while i < indents.Peek() do
                    indents.Pop() |> ignore
                    layout KDedent

                if i <> indents.Peek() then
                    fail ln "inconsistent indentation"

                layout KNewline
        elif not blank && brackets.Count > 0 && not (continuesLine rest) then
            let frame = frames.Peek()
            let closer = rest.StartsWith ")" || rest.StartsWith "}" || rest.StartsWith "]" || rest.StartsWith "|]"

            if not closer then
                let opensBlock =
                    match toks[toks.Count - 1].tok with
                    | KSym "->"
                    | KKw("then" | "else" | "do") -> true
                    // `task {` ending a line: a computation expression's body, a block
                    | KSym "{" when toks.Count > 1 && (match toks[toks.Count - 2].tok with
                                                       | KId _ -> true
                                                       | _ -> false) -> true
                    | _ -> false

                // a block inside the bracket, as at the top level: (fun x -> and a deeper line
                if frame.Count = 0 && opensBlock && i > lastIndent then
                    frame.Push i
                    layout KIndent
                elif frame.Count > 0 then
                    if i > frame.Peek() then
                        frame.Push i
                        layout KIndent
                    else
                        while frame.Count > 0 && i < frame.Peek() do
                            frame.Pop() |> ignore
                            layout KDedent

                        if frame.Count > 0 then
                            if i <> frame.Peek() then
                                fail ln "inconsistent indentation"

                            layout KNewline

                // outside such blocks, a new line inside { } or [ ] separates items
                if frame.Count = 0 && (brackets.Peek() = '{' || brackets.Peek() = '[') then
                    match toks[toks.Count - 1].tok with
                    | KSym(";" | "{" | "[" | "[|")
                    | KKw "with" -> ()
                    | _ -> layout (KSym ";")

        if not blank then
            lastIndent <- i

        if inString then i <- line.Length
        elif resumeCol >= 0 then i <- resumeCol

        while i < line.Length do
            let c = line[i]
            start <- i

            if c = ' ' then
                i <- i + 1
            elif c = '/' && i + 1 < line.Length && line[i + 1] = '/' then
                if keepComments then
                    comments.Add(ln, i + 1, line.Substring i)

                i <- line.Length
            elif c = '0' && i + 2 < line.Length && "xXbBoO".Contains line[i + 1] then
                // 0xFF, 0b1010, 0o17 (with _ separators); up to 64 bits, so 0xFFFF_FFFF_FFFF_FFFF is -1
                let radix =
                    match Char.ToLower line[i + 1] with
                    | 'x' -> 16
                    | 'b' -> 2
                    | _ -> 8

                let isDigit (d: char) = Uri.IsHexDigit d && Convert.ToInt32(string d, 16) < radix
                i <- i + 2
                let s = i

                while i < line.Length && (isDigit line[i] || line[i] = '_') do
                    i <- i + 1

                let digits = line.Substring(s, i - s).Replace("_", "")

                if digits = "" then
                    fail ln (sprintf "expected digits after 0%c" line[s - 1])

                if i < line.Length && Char.IsLetterOrDigit line[i] then
                    fail ln (sprintf "'%c' isn't a digit in base %d" line[i] radix)

                let value =
                    try
                        Convert.ToUInt64(digits, radix)
                    with :? OverflowException ->
                        fail ln "integer literal too large (more than 64 bits)"

                add (KInt(int64 value))
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
            elif c = '\'' && i + 2 < line.Length
                 && (line[i + 1] = '\\'
                     || line[i + 2] = '\''
                     || (Char.IsHighSurrogate line[i + 1] && i + 3 < line.Length && line[i + 3] = '\'')) then
                // a character literal: 'a', '\n', '\u{e9}' (a type variable 'a has no closing quote)
                let cp, next =
                    if line[i + 1] = '\\' then unescapeAt ln line (i + 2)
                    elif Char.IsHighSurrogate line[i + 1] then Char.ConvertToUtf32(line, i + 1), i + 3
                    else int line[i + 1], i + 2

                if next >= line.Length || line[next] <> '\'' then
                    fail ln "a character literal holds one character: 'a'"

                i <- next + 1
                add (KChar cp)
            elif c = '\'' && i + 1 < line.Length && Char.IsLetter(line[i + 1]) then
                let s = i + 1
                i <- i + 1

                while i < line.Length && (Char.IsLetterOrDigit(line[i]) || line[i] = '_') do
                    i <- i + 1

                add (KTyVar(line.Substring(s, i - s)))
            elif c = '`' && i + 1 < line.Length && line[i + 1] = '`' then
                // ``name``: a name that may be a keyword, as in F# (the library defines
                // Parallel.for as ``for``)
                let close = line.IndexOf("``", i + 2)

                if close < 0 then
                    fail ln "unterminated ``name``"

                let name = line.Substring(i + 2, close - i - 2)
                i <- close + 2
                add (KId name)
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
                // """…""": raw text, with quotes and backslashes as written
                let triple = not interp && i + 3 <= line.Length && line.Substring(i, 3) = "\"\"\""
                let parts = ResizeArray<bool * string * int>()
                let sb = StringBuilder()
                // a string can go on over the next lines: cur is the line being read
                let mutable cur = line
                let mutable curLine = li
                let mutable closed = false
                i <- i + (if interp then 2 elif triple then 3 else 1)

                while not closed do
                    if i >= cur.Length then
                        // the line ends inside the string: a newline in its text
                        if curLine + 1 >= lines.Length then
                            fail ln "unterminated string literal"

                        sb.Append '\n' |> ignore
                        curLine <- curLine + 1
                        cur <- lines[curLine]
                        i <- 0
                    elif triple then
                        if i + 3 <= cur.Length && cur.Substring(i, 3) = "\"\"\"" then
                            closed <- true
                            i <- i + 3
                        else
                            sb.Append(cur[i]) |> ignore
                            i <- i + 1
                    elif cur[i] = '"' then
                        closed <- true
                        i <- i + 1
                    elif cur[i] = '\\' && i + 1 < cur.Length then
                        let cp, next = unescapeAt (curLine + 1) cur (i + 1)
                        sb.Append(Char.ConvertFromUtf32 cp) |> ignore
                        i <- next
                    elif interp && cur[i] = '{' && i + 1 < cur.Length && cur[i + 1] = '{' then
                        sb.Append '{' |> ignore
                        i <- i + 2
                    elif interp && cur[i] = '}' && i + 1 < cur.Length && cur[i + 1] = '}' then
                        sb.Append '}' |> ignore
                        i <- i + 2
                    elif interp && cur[i] = '{' then
                        parts.Add(false, sb.ToString(), 0)
                        sb.Clear() |> ignore
                        let s = i + 1
                        let mutable depth = 0
                        i <- i + 1

                        // the hole may itself contain braces: {f { x = 1 }}
                        while i < cur.Length && (cur[i] <> '}' || depth > 0) do
                            if cur[i] = '{' then depth <- depth + 1
                            elif cur[i] = '}' then depth <- depth - 1
                            i <- i + 1

                        if i >= cur.Length then
                            fail (curLine + 1) "unterminated '{' in interpolated string"

                        parts.Add(true, cur.Substring(s, i - s), s + 1)
                        i <- i + 1
                    else
                        sb.Append(cur[i]) |> ignore
                        i <- i + 1

                let tok =
                    if interp then
                        parts.Add(false, sb.ToString(), 0)
                        KInterp(List.ofSeq parts)
                    else
                        KStr(sb.ToString())

                if curLine = li then
                    add tok
                else
                    // it ended on a later line: the token takes the rest of this line, and
                    // lexing goes on after the closing quote there
                    resume <- Some(curLine, i)
                    let until = lineStart[curLine] + i
                    i <- line.Length

                    toks.Add
                        { tok = tok
                          line = ln
                          col = start + 1
                          len = line.Length - start
                          adj = start > 0 && line[start - 1] <> ' '
                          last = curLine + 1
                          offset = lineStart[li] + start
                          text = text.Substring(lineStart[li] + start, until - lineStart[li] - start)
                          lead = []
                          trail = [] }
            else
                let at = i
                let two = if at + 1 < line.Length then line.Substring(at, 2) else ""

                let s =
                    if two = "|]" || two = ">]" then
                        two
                    elif isOpChar c then
                        // the longest run of operator characters: a symbol, or a custom operator
                        let run = opRun line at
                        let next = at + run.Length

                        // a symbol and then the sign of its operand: x=-1, a*-b (but not (<+) or
                        // (++), operators that end in a sign)
                        if run.Length > 1
                           && (run.EndsWith "-" || run.EndsWith "+")
                           && symbolSet.Contains(run.Substring(0, run.Length - 1))
                           && next < line.Length
                           && (Char.IsLetterOrDigit line[next] || line[next] = '_' || line[next] = '(') then
                            run.Substring(0, run.Length - 1)
                        else
                            run
                    else
                        match symbols |> List.tryFind (fun s -> at + s.Length <= line.Length && line.Substring(at, s.Length) = s) with
                        | Some s -> s
                        | None -> fail ln (sprintf "unexpected character '%c'" c)

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
                | "[" ->
                    brackets.Push s[0]
                    frames.Push(Stack())
                | "[|"
                | "[<" ->
                    brackets.Push '('
                    frames.Push(Stack())
                | ")"
                | "}"
                | "]"
                | "|]"
                | ">]" when brackets.Count > 0 ->
                    // the blocks opened inside the bracket end with it
                    for _ in 1 .. frames.Pop().Count do
                        layout KDedent

                    brackets.Pop() |> ignore
                | _ -> ()

                i <- i + s.Length
                add (KSym(if prefixMinus then "~-" else s))

    let eof t =
        { tok = t
          line = lines.Length
          col = 0
          len = 0
          adj = false
          last = lines.Length
          offset = text.Length
          text = ""
          lead = []
          trail = [] }

    for _ in 2 .. indents.Count do
        toks.Add(eof KDedent)

    toks.Add(eof KEof)
    withTrivia text (toks.ToArray())

/// Gives each written token the trivia around it: what follows it to the end of its line (its
/// newline included) trails it, and the rest leads the next written token, or the end of file.
and private withTrivia (text: string) (toks: Token[]) : Token[] =
    let pieces (from: int) (until: int) =
        let out = ResizeArray<Trivia>()
        let mutable i = from

        while i < until do
            let c = text[i]

            if c = '\n' then
                out.Add Newline
                i <- i + 1
            elif c = '/' && i + 1 < until && text[i + 1] = '/' then
                let e = text.IndexOf('\n', i)
                let e = if e < 0 || e > until then until else e
                let s = text.Substring(i, e - i)
                out.Add(if s.StartsWith "///" && not (s.StartsWith "////") then DocComment s else Comment s)
                i <- e
            else
                let s = i

                while i < until && text[i] <> '\n' && not (text[i] = '/' && i + 1 < until && text[i + 1] = '/') do
                    i <- i + 1

                out.Add(Space(text.Substring(s, i - s)))

        List.ofSeq out

    // what trails a token: up to its line's newline, included
    let split (ts: Trivia list) =
        match List.tryFindIndex ((=) Newline) ts with
        | Some k -> List.take (k + 1) ts, List.skip (k + 1) ts
        | None -> ts, []

    let written = [| for k in 0 .. toks.Length - 1 do if toks[k].text <> "" then k |]
    let toks = Array.copy toks
    let mutable prevEnd = 0

    for w in 0 .. written.Length - 1 do
        let k = written[w]
        let gap = pieces prevEnd toks[k].offset

        let lead =
            if w = 0 then
                gap
            else
                let p = written[w - 1]
                let trail, lead = split gap
                toks[p] <- { toks[p] with trail = trail }
                lead

        toks[k] <- { toks[k] with lead = lead }
        prevEnd <- toks[k].offset + toks[k].text.Length

    let rest = pieces prevEnd text.Length
    let e = toks.Length - 1

    if written.Length > 0 then
        let p = written[written.Length - 1]
        let trail, lead = split rest
        toks[p] <- { toks[p] with trail = trail }
        toks[e] <- { toks[e] with lead = lead }
    else
        toks[e] <- { toks[e] with lead = rest }

    toks

// ---------------------------------------------------------------- parser

let private cons a b = Call("::", [ Tuple [ a; b ] ])

/// Parses a whole program, or (exprOnly) a single expression, with its syntax tree.
let rec private parseTokens (toks: Token[]) (exprOnly: bool) (track: bool) : (int * Decl) list * Expr option * Node =
    let toks = Array.copy toks // closeAngle splits '>>' in place
    let pos = ref 0
    // the tree so far: the open nodes, innermost on top, each with its children
    let opened = Stack<string * ResizeArray<Child>>()
    opened.Push("File", ResizeArray())
    let start kind = opened.Push(kind, ResizeArray())

    let finish () =
        let kind, children = opened.Pop()
        (snd (opened.Peek())).Add(N { kind = kind; children = children.ToArray() })

    /// The open node's next child: startAt makes a node of the children from there on, for a
    /// construct found after its first part (an operator after its left operand).
    let here () = (snd (opened.Peek())).Count

    let startAt (at: int) kind =
        let children = snd (opened.Peek())
        let moved = children.GetRange(at, children.Count - at)
        children.RemoveRange(at, children.Count - at)
        opened.Push(kind, moved)

    let node kind (f: unit -> 'r) : 'r =
        start kind
        let r = f ()
        finish ()
        r

    // backtracking: the position, and the tree as it was
    let save () = pos.Value, opened.Count, here ()

    let restore (p, depth, count) =
        pos.Value <- p

        while opened.Count > depth do
            opened.Pop() |> ignore

        let children = snd (opened.Peek())
        children.RemoveRange(count, children.Count - count)
    // inside a task { }'s body: blocks take let!, do!, return and return! (the body is code in
    // direct style, compiled into a state machine)
    let inTask = ref 0
    // inside seq { } (and not in a list expression in it): yield is the sequence's
    let inSeq = ref 0
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
    let advance () =
        (snd (opened.Peek())).Add(T toks[pos.Value])
        pos.Value <- pos.Value + 1
    let err what =
        let t = toks[pos.Value]
        raise (CompileErrorPos(t.line, t.col, sprintf "expected %s, found %s" what (showTok t.tok)))

    let errAt msg =
        let t = toks[pos.Value]
        raise (CompileErrorPos(t.line, t.col, msg))

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

    /// Consumes one '>' closing a type argument list, splitting '>>' if needed: its first '>'
    /// goes into the tree, the rest stays to be read.
    let closeAngle () =
        let split rest =
            let t = toks[pos.Value]
            (snd (opened.Peek())).Add(T { t with tok = KSym ">"; text = ">"; len = 1; trail = [] })

            toks[pos.Value] <-
                { t with
                    tok = KSym rest
                    text = rest
                    col = t.col + 1
                    len = t.len - 1
                    adj = true
                    offset = t.offset + 1
                    lead = [] }

        match peek () with
        | KSym ">" -> advance ()
        | KSym ">>" -> split ">"
        | KSym ">>>" -> split ">>" // list<list<list<int>>>
        | _ -> err "'>'"

    /// A unit of measure: m, m/s^2, kg m/s^2, 'u, 1 (inside <...> after a numeric type).
    let rec measure () = node "Measure" measureOf

    and measureOf () =
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
        let at = here ()

        let t =
            match peek () with
            | KId n when isNumericName n && peek2 () = KSym "<" ->
                start "TypeName"
                advance ()
                advance ()
                let m = measure ()
                closeAngle ()
                finish ()
                STName(n, [ m ])
            | KTyVar v ->
                advance ()
                STVar v
            | KInt n ->
                // fixed<u8, 16>'s length (a number is a type argument of fixed only)
                advance ()
                STName(string n, [])
            | KId "dyn" when (match peek2 () with
                              | KId _ -> true
                              | _ -> false) ->
                // dyn Trait: a value of any type that implements the trait
                node "TypeName" (fun () ->
                    advance ()
                    STName("dyn", [ STName(ident (), []) ]))
            | KId n ->
                advance ()

                if isSym "<" then
                    startAt at "TypeName"
                    advance ()
                    let args = ResizeArray [ ty () ]

                    while isSym "," do
                        advance ()
                        args.Add(ty ())

                    closeAngle ()
                    finish ()
                    STName(n, List.ofSeq args)
                else
                    STName(n, [])
            | KSym "(" ->
                node "TypeParen" (fun () ->
                    advance ()
                    let t = ty ()
                    expect (KSym ")") "')'"
                    t)
            | _ -> err "type"

        // postfix application: int list, string option
        let mutable t = t

        while (match peek () with
               | KId _ -> true
               | _ -> false) do
            startAt at "TypeName"
            t <- STName(ident (), [ t ])
            finish ()

        t

    and tupleTy () =
        let at = here ()
        let first = tyAtom ()

        if isSym "*" then
            startAt at "TypeTuple"
            let items = ResizeArray [ first ]

            while isSym "*" do
                advance ()
                items.Add(tyAtom ())

            finish ()
            STTuple(List.ofSeq items)
        else
            first

    and ty () =
        let at = here ()
        let t = tupleTy ()

        if isSym "->" then
            startAt at "TypeFun"
            advance ()
            let r = ty ()
            finish ()
            STFun(t, r)
        elif isSym "/" then
            // the effects after a function's result: / E, / 'e, / <E, F | 'e>, / <>
            startAt at "TypeRow"
            advance ()

            let label () =
                match tyAtom () with
                | STName _ as l -> l
                | _ -> err "an effect"

            let r =
                match peek () with
                | KSym "<>" ->
                    advance ()
                    STRow(t, [], None)
                | KTyVar v ->
                    advance ()
                    STRow(t, [], Some v)
                | KSym "<" ->
                    advance ()
                    let labels = ResizeArray [ label () ]

                    while isSym "," do
                        advance ()
                        labels.Add(label ())

                    let tail =
                        if isSym "|" then
                            advance ()

                            match peek () with
                            | KTyVar v ->
                                advance ()
                                Some v
                            | _ -> err "a row variable ('e)"
                        else
                            None

                    closeAngle ()
                    STRow(t, List.ofSeq labels, tail)
                | _ -> STRow(t, [ label () ], None)

            finish ()
            r
        else
            t

    let optTy () =
        if isSym ":" then
            node "Annotation" (fun () ->
                advance ()
                Some(ty ()))
        else
            None

    let startsPatAtom t =
        match t with
        | KId _
        | KInt _
        | KChar _
        | KStr _
        | KSym("-" | "~-")
        | KKw "true"
        | KKw "false"
        | KSym "("
        | KSym "["
        | KSym "{" -> true
        | _ -> false

    let rec pattern () =
        let at = here ()
        let mutable p = orPat ()

        while peek () = KKw "as" do
            startAt at "PatternAs"
            advance ()
            p <- PAs(p, ident ())
            finish ()

        p

    // before '->', a line starting with '|' continues the or-pattern
    and orPat () =
        let at = here ()
        let mutable p = tuplePat ()
        let mutable chain = false

        while isSym "|" || (peek () = KNewline && peek2 () = KSym "|") do
            if not chain then
                chain <- true
                startAt at "PatternOr"

            if peek () = KNewline then
                advance ()

            advance ()
            p <- POr(p, tuplePat ())

        if chain then
            finish ()

        p

    and tuplePat () =
        let at = here ()
        let first = consPat ()

        if isSym "," then
            startAt at "PatternTuple"
            let items = ResizeArray [ first ]

            while isSym "," do
                advance ()
                items.Add(consPat ())

            finish ()
            PTuple(List.ofSeq items)
        else
            first

    and consPat () =
        let at = here ()
        let head = appPat ()

        if isSym "::" then
            startAt at "PatternCons"
            advance ()
            let tail = consPat ()
            finish ()
            PIdent("::", Some(PTuple [ head; tail ]))
        else
            head

    and appPat () =
        match peek () with
        | KId c when c <> "_" && startsPatAtom (peek2 ()) && (Char.IsUpper c[0] || c.Contains ".") ->
            node "PatternCase" (fun () ->
                advance ()

                match [ while startsPatAtom (peek ()) do
                            yield patAtom () ] with
                | [ p ] -> PIdent(c, Some p)
                | ps -> PIdent(c, Some(PArgs ps)))
        | _ -> patAtom ()

    and patAtom () =
        match peek () with
        | KSym "{" -> node "PatternRecord" patAtomOf
        | KSym "[" -> node "PatternList" patAtomOf
        | KSym "(" -> node "PatternParen" patAtomOf
        | KSym("-" | "~-") -> node "PatternNegative" patAtomOf
        | _ -> patAtomOf ()

    and patAtomOf () =
        let t = peek ()

        if not (startsPatAtom t) then
            err "pattern"

        advance ()

        match t with
        | KId "_" -> PWild
        | KId x -> mark (pos.Value - 1) (PIdent(x, None))
        | KInt n -> PInt n
        | KChar c -> PChar c
        | KStr s -> PStr s
        | KSym("-" | "~-") ->
            match peek () with
            | KInt n ->
                advance ()
                PInt -n
            | _ -> err "integer"
        | KKw "true" -> PBool true
        | KKw "false" -> PBool false
        | KSym "{" ->
            // a record pattern: { field = pattern; ... } (line breaks separate fields too)
            let fields = ResizeArray()

            while not (isSym "}") do
                let f = ident ()
                expect (KSym "=") "'='"
                fields.Add(f, pattern ())

                if isSym ";" then
                    advance ()
                elif not (isSym "}") then
                    err "';' or '}'"

            advance ()

            if fields.Count = 0 then
                fail (line ()) "a record pattern names at least one field: { x = x }"

            PRecord(List.ofSeq fields)
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

    /// A function parameter: x, _, (), (x: T), (pattern), [pattern] or { record pattern }.
    let param () : Param =
        match peek (), peek2 () with
        | KSym "(", KId _ when (toks[min (pos.Value + 2) (toks.Length - 1)].tok = KSym ":") ->
            node "Parameter" (fun () ->
                advance ()
                let xi = pos.Value
                let x = ident ()
                advance ()
                let t = ty ()
                expect (KSym ")") "')'"
                mark xi (PIdent(x, None)), Some t)
        | _ -> patAtom (), None

    let startsParam t =
        match t with
        | KId _
        | KSym "("
        | KSym "["
        | KSym "{" -> true // a record pattern: let norm { x = x; y = y } = …
        | _ -> false

    let parameters () =
        [ while startsParam (peek ()) do
              yield param () ]

    let rec block () =
        if peek () = KIndent then
            node "Block" (fun () ->
                advance ()
                let e = seq ()
                expect KDedent "end of block"
                e)
        else
            // a one-line block is a statement too, so its errors have a position
            let si = pos.Value
            let ln = line ()

            match taskForm () with
            | Some e -> mark si (At(ln, e))
            | None ->
                let at = here ()
                mark si (At(ln, assignment at (expr ())))

    /// In a task's body: `return e` (the task's result), `return! t` and `do! t` (waiting for t);
    /// None for anything else.
    and taskForm () =
        let bang () =
            if isSym "!" && toks[pos.Value].adj then
                advance ()
                true
            else
                false

        if inTask.Value = 0 then
            None
        else
            match peek () with
            | KId "return" ->
                // return! t: the task t's result, which at the end of the body is t handed this
                // task's waiter ($awaitLast)
                node "Return" (fun () ->
                    advance ()
                    if bang () then Some(Call("$awaitLast", [ block () ])) else Some(block ()))
            | KKw "do" when peek2 () = KSym "!" ->
                node "DoBang" (fun () ->
                    advance ()
                    advance ()
                    Some(Call("$await", [ block () ])))
            | _ -> None

    /// `lhs <- rhs` (statements, and single-line blocks such as `then x <- 1`), and compound
    /// assignment, `lhs += rhs`: lhs <- lhs + rhs with the place evaluated once, its receiver and
    /// index bound first (then the read, the operation and the write, in that order)
    and assignment (at: int) lhs =
        match peek () with
        | KSym "<-" ->
            startAt at "Assign"
            advance ()
            let rhs = expr ()
            finish ()
            Assign(lhs, rhs)
        | KSym s when compoundOps.ContainsKey s ->
            let oi = pos.Value
            let ln = line ()
            startAt at "Assign"
            advance ()
            let rhs = expr ()
            finish ()
            let temps = ResizeArray<string * Expr>()

            // a part of the place with no effects (a name, a literal) stays; any other is bound to a
            // temporary, once
            let bound (e: Expr) =
                match e with
                | Var _
                | Lit _ -> e
                | _ ->
                    let t = sprintf "$place%d.%d" oi temps.Count
                    temps.Add(t, e)
                    Var t

            // a place: a name, a field of a place (a ref's Value, a mutable record's field) or an
            // element of one; a receiver that isn't a place (a call giving a Buffer) is bound too
            let rec place (e: Expr) =
                match e with
                | Var _ -> e
                | Field(r, f) -> Field(receiver r, f)
                | Index(a, i) ->
                    let a = receiver a
                    Index(a, bound i)
                | At(_, inner) -> place inner
                | _ -> fail ln (sprintf "%s needs a place <- can assign: a let mutable, a ref's .Value, an element or a field" s)

            and receiver (e: Expr) =
                match e with
                | Var _
                | Field _
                | Index _ -> place e
                | _ -> bound e

            let p = place lhs
            let assign = mark oi (Assign(p, Bin(compoundOps[s], p, rhs)))
            List.foldBack (fun (t, v) acc -> Let(PIdent(t, None), None, v, acc)) (List.ofSeq temps) assign
        | _ -> lhs

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

        if peek () = KId "use" && (match peek2 () with
                                   | KId _ -> true
                                   | _ -> false) then
            // use x = e: x is disposed (Dispose.dispose) after the rest of the block; in a task,
            // also if the task is cancelled before then
            start "Use"
            advance ()
            let xi = pos.Value
            let x = ident ()
            expect (KSym "=") "'='"
            let v = block ()
            finish ()

            if peek () <> KNewline then
                fail ln "'use' must be followed by the rest of the block on the next line"

            advance ()
            let after = seq ()

            if inTask.Value > 0 then
                let id = sprintf "$use%d" xi
                let onCancel = Call("Threading.Task.disposeOnCancel", [ Var "$cancel"; Var x ])
                let finish = Call("Threading.Task.disposed", [ Var "$cancel"; Var id; Var x ])
                stmt(ln, Let(mark xi (PIdent(x, None)), None, v, Let(PIdent(id, None), None, onCancel, Let(PIdent("$use", None), None, after, Seq(finish, Var "$use")))))
            else
                stmt(ln, Let(mark xi (PIdent(x, None)), None, v, Let(PIdent("$use", None), None, after, Seq(Call("Dispose.dispose", [ Var x ]), Var "$use"))))
        elif inTask.Value > 0 && peek () = KKw "let" && peek2 () = KSym "!" then
            // let! p = t: the rest once the task t has given its result
            start "LetBang"
            advance ()
            advance ()
            let p = pattern ()
            expect (KSym "=") "'='"
            let v = block ()
            finish ()
            stmt(ln, Let(p, None, Call("$await", [ v ]), rest ln))
        elif inTask.Value > 0 && (peek () = KId "return" || (peek () = KKw "do" && peek2 () = KSym "!")) then
            // return e: the block's (and the task's) result, last; do! t: then the rest
            let isReturn = peek () = KId "return"
            let e = stmt (ln, (taskForm ()).Value)

            if peek () = KNewline then
                if isReturn then
                    fail (line ()) "nothing can follow return in a task"

                advance ()
                Seq(e, seq ())
            else
                e
        elif peek () = KKw "let" then
            start "Let"
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
                finish ()
                stmt(ln, LetMut(x, ann, v, rest ln))
            | KSym "(", _ when operatorAhead () ->
                // a local operator: let (<+>) a b = …
                advance ()
                let fi, f = operatorName ()
                localFun ln isRec stmt f fi
            | KId f, next when (isRec || Char.IsLower f[0] || f[0] = '_') && f <> "_" && startsParam next ->
                let fi = pos.Value
                advance ()
                localFun ln isRec stmt f fi
            | _ ->
                let p = pattern ()
                let ann = optTy ()
                expect (KSym "=") "'='"
                let v = block ()
                finish ()

                match v with
                | Question e as q
                | At(_, (Question e as q)) when ann.IsNone -> stmt(ln, copyPos q (TryBind(p, e, rest ln)))
                | _ -> stmt(ln, Let(p, ann, v, rest ln))
        else
            let at = here ()

            match assignment at (expr ()) with
            | Question e as q when peek () = KNewline ->
                advance ()
                stmt(ln, copyPos q (TryBind(PWild, e, seq ())))
            | e ->
                let e = stmt(ln, e)

                if peek () = KNewline then
                    advance ()
                    Seq(e, seq ())
                else
                    e

    /// At `let (`: whether an operator and `)` follow (a built-in one too, to say it can't be
    /// redefined; `(|` starts an active pattern instead).
    and operatorAhead () =
        match peek2 () with
        | KSym s when s <> "|" && Seq.forall isOpChar s -> toks[min (pos.Value + 2) (toks.Length - 1)].tok = KSym ")"
        | _ -> false

    /// The operator of `(op)` after its `(`, and its token's index; a built-in one can't be defined.
    and operatorName () =
        let oi = pos.Value

        let s =
            match peek () with
            | KSym s -> s
            | _ -> ""

        if not (isCustomOp s) then
            fail (line ()) (sprintf "'%s' is built in and can't be redefined; give the custom operator another name, such as '%s.'" s s)

        advance ()
        expect (KSym ")") "')'"
        oi, s

    /// A local function after its name: parameters, body, and any `and` functions joined to it.
    and localFun ln isRec stmt (f: string) (fi: int) =
        let ps = parameters ()
        let ret = optTy ()
        expect (KSym "=") "'='"
        let body = block ()

        if peek () = KNewline && peek2 () = KKw "and" then
            // let rec f … and g …: functions that call each other
            if not isRec then
                fail (line ()) "functions joined with 'and' call each other: write 'let rec f … and g …'"

            let members = ResizeArray [ mark fi (LetFun(f, true, ps, ret, body, UnitLit)) ]

            while peek () = KNewline && peek2 () = KKw "and" do
                advance ()
                advance ()
                let gi = pos.Value
                let g = ident ()
                let gps = parameters ()

                if gps.IsEmpty then
                    fail (line ()) "'and' defines a function: and g x = …"

                let gret = optTy ()
                expect (KSym "=") "'='"
                let gbody = block ()
                members.Add(mark gi (LetFun(g, true, gps, gret, gbody, UnitLit)))

            finish ()
            stmt(ln, LetRecGroup(List.ofSeq members, rest ln))
        else
            finish ()
            stmt(ln, mark fi (LetFun(f, isRec, ps, ret, body, rest ln)))

    and expr () =
        match peek () with
        | KId "yield" when inSeq.Value > 0 -> node "Yield" exprForm
        | KKw("if" | "match" | "handle" | "function" | "fun" | "unsafe" | "while" | "for" as k) ->
            node (if k = "fun" then "Lambda" else string (Char.ToUpper k[0]) + k.Substring 1) exprForm
        | _ -> exprForm ()

    and exprForm () =
        match peek () with
        | KId "yield" when inSeq.Value > 0 ->
            // in a seq { }: yield e performs Yield.yield e; yield! s yields s's elements
            let ln = line ()
            advance ()

            if isSym "!" && toks[pos.Value].adj then
                advance ()
                At(ln, Call("$yieldAll", [ expr () ]))
            else
                At(ln, Call("$yield", [ expr () ]))
        | KId "try" when (match peek2 () with
                          | KIndent
                          | KNewline -> true
                          | _ -> false) ->
            errAt "there's no try … with: a function that can fail returns a result (match on it, or use ? inside result { }), or throws a Throw effect, which Throw.catch turns into a result"
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
            Match(s, cases ())
        | KKw "handle" ->
            // handle e with | E.op p…, k -> … | return p -> …: e's operations of E given meaning
            advance ()

            let body =
                if peek () = KIndent then
                    let e =
                        node "Block" (fun () ->
                            advance ()
                            let e = seq ()
                            expect KDedent "end of block"
                            e)

                    if peek () = KNewline then
                        advance ()

                    e
                else
                    expr ()

            expect (KKw "with") "'with'"
            let ops, ret = handleCases ()
            Handle(body, ops, ret)
        | KKw "function" ->
            // function | p -> … | q -> …: fun x -> match x with …, x a fresh name
            let at = pos.Value
            advance ()
            let x = sprintf "$function%d" at
            Lambda([ PIdent(x, None), None ], Match(Var x, cases ()))
        | KKw "fun" ->
            advance ()
            let ps = parameters ()

            if ps.IsEmpty then
                err "parameter"

            expect (KSym "->") "'->'"
            Lambda(ps, block ())
        | KKw "unsafe" ->
            // unsafe e, or unsafe and an indented block: raw pointer operations allowed inside
            advance ()
            Unsafe(block ())
        | KKw "while" ->
            advance ()
            let c = expr ()
            expect (KKw "do") "'do'"
            While(c, block ())
        | KKw "for" ->
            advance ()

            // for x in …, or for <pattern> in xs (a fresh name, taken apart at the top of the body)
            let x, destructure =
                match peek () with
                | KId _ -> ident (), None
                | _ ->
                    let at = pos.Value
                    let p = pattern ()
                    sprintf "$for%d" at, Some p

            expect (KKw "in") "'in'"
            let a = pipe ()

            if peek () = KKw "do" then
                advance ()
                let body = block ()

                match destructure with
                | Some p -> ForIn(x, a, Let(p, None, Var x, body))
                | None -> ForIn(x, a, body)
            elif destructure.IsSome then
                fail (line ()) "a pattern needs 'for … in <collection> do'; a range loop takes a name"
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

    /// A match's cases, after its `with` (or after `function`): `| p when g -> e`, on one line
    /// each or in an indented block.
    and cases () = casesWith block

    /// A handle's clauses: `| E.op p…, k -> body` for an operation (its arguments' patterns, then
    /// the resumption's name, `_` when it's never resumed), `| return p -> body` for the result.
    and handleCases () =
        let indented = peek () = KIndent

        if indented then
            advance ()

        let ops = ResizeArray()
        let mutable ret = None

        while (if peek () = KNewline && peek2 () = KSym "|" then advance ()
               isSym "|") do
            start "Clause"
            advance ()

            match peek () with
            | KId "return" ->
                advance ()
                let p = pattern ()
                expect (KSym "->") "'->'"

                if ret.IsSome then
                    errAt "a handle has one return clause"

                ret <- Some(p, block ())
            | KId _ ->
                let op = mark pos.Value (ident ()) // its position: a reference to the operation
                let args = ResizeArray()

                while not (isSym ",") do
                    if not (startsPatAtom (peek ())) then
                        err "the operation's argument pattern, then ', k ->' (the resumption)"

                    args.Add(patAtom ())

                advance ()
                let k = ident ()
                expect (KSym "->") "'->'"
                ops.Add(op, List.ofSeq args, k, block ())
            | _ -> err "an operation (Effect.op p…, k -> …) or return p -> …"

            finish ()

        if indented then
            expect KDedent "end of block"

        List.ofSeq ops, ret

    and casesWith (body: unit -> Expr) =
        let indented = peek () = KIndent

        if indented then
            advance ()

        let cases = ResizeArray()

        // `| p when g -> e`, the first clause's '|' optional
        let clause () =
            start "Clause"

            if isSym "|" then
                advance ()

            let p = pattern ()

            let guard =
                if peek () = KKw "when" then
                    advance ()
                    Some(expr ())
                else
                    None

            expect (KSym "->") "'->'"
            cases.Add(p, guard, body ())
            finish ()

        if peek () = KNewline && peek2 () = KSym "|" then
            advance ()

        clause ()

        while isSym "|" || (peek () = KNewline && peek2 () = KSym "|") do
            if peek () = KNewline then
                advance ()

            clause ()

        if indented then
            expect KDedent "end of block"

        List.ofSeq cases

    /// A list or array expression's body, after `[` or `[|`, up to its closer: `for`s, `if`s,
    /// `let`s and `match`es whose statements `yield e` or `yield! xs` (or do something), and
    /// `for x in xs -> e` for `for x in xs do yield e`.
    and comprehension (isArray: bool) (close: string) =
        // its yields are its own, also inside a seq { }
        let outerSeq = inSeq.Value
        inSeq.Value <- 0

        let body =
            try
                compSeq (fun () -> isSym close)
            finally
                inSeq.Value <- outerSeq

        expect (KSym close) (sprintf "'%s'" close)
        ListComp(isArray, body)

    /// Statements one after another (`;`, or a line break), until stop: a `let` takes the rest.
    and compSeq (stop: unit -> bool) =
        if peek () = KKw "let" then
            start "Let"
            advance ()
            let p = pattern ()
            let ann = optTy ()
            expect (KSym "=") "'='"
            let v = block ()
            finish ()

            if peek () = KNewline || isSym ";" || peek () = KKw "in" then
                advance ()

            Let(p, ann, v, compSeq stop)
        else
            let first = compStmt ()

            if (peek () = KNewline || isSym ";") then
                advance ()
                if stop () then first else Seq(first, compSeq stop)
            else
                first

    /// The body of a list expression's `for`, `if` or match case: an indented block, or one
    /// statement.
    and compBlock () =
        if peek () = KIndent then
            node "Block" (fun () ->
                advance ()
                let e = compSeq (fun () -> peek () = KDedent)
                expect KDedent "end of block"
                e)
        else
            compStmt ()

    and compStmt () : Expr =
        match peek () with
        | KKw "for" -> node "For" compForm
        | KKw "if" -> node "If" compForm
        | KKw "match" -> node "Match" compForm
        | KId "yield" -> node "Yield" compForm
        | _ -> compForm ()

    and compForm () : Expr =
        let si = pos.Value
        let ln = line ()
        let stmt (e: Expr) = mark si (At(ln, e))

        match peek () with
        | KKw "for" ->
            advance ()

            let x, destructure =
                match peek () with
                | KId _ -> ident (), None
                | _ ->
                    let at = pos.Value
                    let p = pattern ()
                    sprintf "$for%d" at, Some p

            expect (KKw "in") "'in'"
            let a = pipe ()

            // for x in xs -> e yields e; for x in xs do … runs a body that yields
            let body () =
                if isSym "->" then
                    advance ()
                    let yi = pos.Value
                    let yl = line ()
                    mark yi (At(yl, Yield(node "Yield" block)))
                else
                    expect (KKw "do") "'do' or '->'"
                    compBlock ()

            if isSym ".." then
                advance ()
                let b = pipe ()

                let step, b =
                    if isSym ".." then
                        advance ()
                        Some b, pipe ()
                    else
                        None, b

                if destructure.IsSome then
                    fail ln "a range loop takes a name"

                stmt (For(x, a, step, b, body ()))
            else
                let b = body ()

                match destructure with
                | Some p -> stmt (ForIn(x, a, Let(p, None, Var x, b)))
                | None -> stmt (ForIn(x, a, b))
        | KKw "if" ->
            advance ()
            let c = expr ()
            expect (KKw "then") "'then'"
            let t = compBlock ()

            if peek () = KNewline && peek2 () = KKw "else" then
                advance ()

            if peek () = KKw "else" then
                advance ()
                stmt (If(c, t, Some(compBlock ())))
            else
                stmt (If(c, t, None))
        | KKw "match" ->
            advance ()
            let s = expr ()
            expect (KKw "with") "'with'"
            stmt (Match(s, casesWith compBlock))
        | KId "yield" ->
            advance ()

            if isSym "!" && toks[pos.Value].adj then
                advance ()
                stmt (YieldAll(expr ()))
            else
                stmt (Yield(expr ()))
        | _ ->
            let at = here ()
            stmt (assignment at (expr ()))

    // an expression without sequencing: the loosest level is ||
    and pipe () = orE ()

    /// The right operand of a binary operator: a lambda there extends to the end, as in
    /// `m >>= fun x -> …`.
    and operand (next: unit -> Expr) = if peek () = KKw "fun" || peek () = KKw "function" then expr () else next ()

    and orE () =
        let at = here ()
        let l = andE ()

        if isSym "||" then
            startAt at "Infix"
            advance ()
            let r = orE ()
            finish ()
            If(l, BoolLit true, Some r)
        else
            l

    and andE () =
        let at = here ()
        let l = cmpE ()

        if isSym "&&" then
            startAt at "Infix"
            advance ()
            let r = andE ()
            finish ()
            If(l, r, Some(BoolLit false))
        else
            l

    /// Left-associative operators at one level: `ops`, and the custom operators of `level`
    /// (-1 for none).
    and binary ops level sub =
        let at = here ()
        let mutable l = sub ()
        let mutable go = true
        let mutable chain = false

        // the chain's node, from its first operand, at its first operator
        let infix () =
            if not chain then
                chain <- true
                startAt at "Infix"

        while go do
            let oi = pos.Value

            match peek () with
            | KSym s when List.contains s ops ->
                infix ()
                advance ()
                l <- Bin(s, l, sub ())
            | KSym(("++" | "--") as s) when (match peek2 () with
                                             | KNewline
                                             | KDedent
                                             | KEof -> true
                                             | _ -> false) ->
                errAt (sprintf "'%s' isn't an operator: write x <- x %s 1, or x %s= 1" s (s.Substring(0, 1)) (s.Substring(0, 1)))
            | KSym s when level >= 0 && isInfixOp s && opLevel s = level ->
                infix ()
                advance ()
                l <- mark oi (Call(s, [ l; operand sub ]))
            | _ -> go <- false

        if chain then
            finish ()

        l

    // as in F#, |>, >>, the comparisons and custom operators starting with < > = | & $ share
    // one left-associative level: x |> parse >>= validate is (x |> parse) >>= validate
    and cmpE () =
        let at = here ()
        let mutable l = bitOrE ()
        let mutable go = true
        let mutable chain = false

        let infix () =
            if not chain then
                chain <- true
                startAt at "Infix"

        while go do
            let oi = pos.Value

            match peek () with
            | KSym "|>" ->
                // x |> f a  ==>  f a x
                infix ()
                advance ()

                l <-
                    match operand bitOrE with
                    | Lambda([ p, ann ], body) -> Let(p, ann, l, body) // x |> fun p -> body: let p = x, typed in order
                    | Var f as v -> copyPos v (Call(f, [ l ]))
                    | Call(f, args) -> Call(f, args @ [ l ])
                    | App(h, args) -> App(h, args @ [ l ])
                    | f -> App(f, [ l ])
            | KSym ">>" ->
                // f >> g  ==>  fun x -> g (f x)
                infix ()
                advance ()
                let r = operand bitOrE
                l <- Lambda([ PIdent("$c", None), None ], App(r, [ App(l, [ Var "$c" ]) ]))
            | KSym(("=" | "<>" | "<" | ">" | "<=" | ">=") as s) ->
                infix ()
                advance ()
                l <- Bin(s, l, bitOrE ())
            | KSym s when isInfixOp s && opLevel s = 0 ->
                infix ()
                advance ()
                l <- mark oi (Call(s, [ l; operand bitOrE ]))
            | _ -> go <- false

        if chain then
            finish ()

        l

    // bitwise operators on integers, tighter than comparison (so x &&& m = 0 needs no parentheses)
    and bitOrE () = binary [ "|||" ] -1 bitXorE
    and bitXorE () = binary [ "^^^" ] -1 bitAndE
    and bitAndE () = binary [ "&&&" ] -1 shiftE
    and shiftE () = binary [ "<<<"; ">>>" ] -1 consE

    // right-associative ::, @ and custom operators starting with @ or ^
    and consE () =
        let at = here ()
        let l = addE ()
        let oi = pos.Value

        match peek () with
        | KSym "::" ->
            startAt at "Infix"
            advance ()
            let r = consE ()
            finish ()
            cons l r
        | KSym "@" ->
            startAt at "Infix"
            advance ()
            let r = consE ()
            finish ()
            Call("Collections.List.append", [ l; r ])
        | KSym s when isInfixOp s && opLevel s = 1 ->
            startAt at "Infix"
            advance ()
            let r = operand consE
            finish ()
            mark oi (Call(s, [ l; r ]))
        | _ -> l

    and addE () = binary [ "+"; "-" ] 2 mulE
    and mulE () = binary [ "*"; "/"; "%" ] 3 powE

    // right-associative custom operators starting with **
    and powE () =
        let at = here ()
        let l = unary ()
        let oi = pos.Value

        match peek () with
        | KSym s when isInfixOp s && opLevel s = 4 ->
            startAt at "Infix"
            advance ()
            let r = operand powE
            finish ()
            mark oi (Call(s, [ l; r ]))
        | _ -> l

    and unary () =
        if isSym "-" || isSym "~-" then
            node "Prefix" (fun () ->
                advance ()
                Neg(unary ()))
        elif isSym "~~~" then
            // bitwise not: x ^^^ (all ones)
            node "Prefix" (fun () ->
                advance ()
                Bin("^^^", unary (), Lit -1L))
        elif peek () = KKw "not" then
            node "Prefix" (fun () ->
                advance ()
                Not(unary ()))
        else
            app ()

    and startsAtom () =
        match peek () with
        | KInt _
        | KChar _
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
        | KSym s -> isPrefixOp s
        | _ -> false

    // `f x?` applies ? to the whole application
    and app () =
        let at = here ()

        let args () =
            startAt at "Apply"
            let xs = [ while startsAtom () do yield atom () ]
            finish ()
            xs

        let e =
            match atom () with
            | Var f as v when startsAtom () -> copyPos v (Call(f, args ()))
            | head when startsAtom () -> App(head, args ())
            | head -> head

        if isSym "?" then
            let qi = pos.Value
            startAt at "Question"
            advance ()
            finish ()
            mark qi (Question e) // errors about it point at the `?`
        else
            e

    and atom () =
        let at = here ()
        let mutable e = primary ()

        while isSym "." || (isSym "(" && toks[pos.Value].adj) do
            if isSym "(" then
                // high-precedence application: f(x), x.M(a, b).N
                startAt at "Apply"
                let arg = primary ()
                finish ()

                e <-
                    match e with
                    | Var f -> copyPos e (Call(f, [ arg ]))
                    | Call(f, args) -> Call(f, args @ [ arg ])
                    | _ -> App(e, [ arg ])
            else
                advance ()

                if isSym "[" then
                    startAt at "Index"
                    advance ()

                    // a.[i], or a slice: a.[i..j], a.[..j], a.[i..]
                    if isSym ".." then
                        advance ()
                        let j = expr ()
                        expect (KSym "]") "']'"
                        e <- Slice(e, None, Some j)
                    else
                        let i = expr ()

                        if isSym ".." then
                            advance ()
                            let j = if isSym "]" then None else Some(expr ())
                            expect (KSym "]") "']'"
                            e <- Slice(e, Some i, j)
                        else
                            expect (KSym "]") "']'"
                            e <- Index(e, i)

                    finish ()
                else
                    startAt at "Field"
                    e <- mark pos.Value (Field(e, ident ()))
                    finish ()

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
        let at = here ()
        advance ()
        // a node of what primary read, from its first token
        let wrap kind (e: Expr) =
            startAt at kind
            finish ()
            e

        // 9.58<s>: a measure right after a number literal
        let measured (lit: Expr) =
            if isSym "<" && toks[pos.Value].adj then
                let saved = save ()

                try
                    startAt at "Measured"
                    advance ()
                    let m = measure ()

                    if isSym ">" then
                        advance ()
                        finish ()
                        Measured(lit, m)
                    else
                        restore saved
                        lit
                with CompileError _ ->
                    restore saved
                    lit
            else
                lit

        match t with
        | KInt n -> measured (Lit n)
        | KChar c -> CharLit c
        | KFloat f -> measured (FloatLit f)
        | KStr s -> StrLit s
        | KInterp parts -> interpolate ln parts
        | KId x when ceAhead () -> wrap "Computation" (computation ln x)
        | KId x -> mark (pos.Value - 1) (Var x)
        | KKw "true" -> BoolLit true
        | KKw "false" -> BoolLit false
        | KSym "{" -> wrap "Record" (record ())
        | KSym "~-" -> wrap "Prefix" (Neg(atom ()))
        | KSym s when isPrefixOp s -> wrap "Prefix" (mark (pos.Value - 1) (Call(s, [ atom () ]))) // !r, ~~x
        | KSym "[" when peek () = KKw "for" || peek () = KId "yield" -> wrap "ListComp" (comprehension false "]")
        | KSym "[|" when peek () = KKw "for" || peek () = KId "yield" -> wrap "ArrayComp" (comprehension true "|]")
        | KSym "[" -> wrap "List" (List.foldBack cons (items "]") (Var "[]"))
        | KSym "[|" -> wrap "Array" (ArrayLit(items "|]"))
        | KSym "(" when peek2 () = KSym ")" && (match peek () with
                                                | KSym s -> isCustomOp s || builtinOperators.Contains s
                                                | _ -> false) ->
            // an operator as a function: (>>=), or (+) for fun a b -> a + b
            let oi = pos.Value

            let s =
                match peek () with
                | KSym s -> s
                | _ -> ""

            advance ()
            advance ()

            wrap "OperatorValue"
            <| if isCustomOp s then
                   mark oi (Var s)
               else
                   let a, b = Var "$a", Var "$b"

                   let body =
                       match s with
                       | "::" -> cons a b
                       | "@" -> Call("Collections.List.append", [ a; b ])
                       | _ -> Bin(s, a, b)

                   Lambda([ PIdent("$a", None), None; PIdent("$b", None), None ], body)
        | _ when isSym ")" ->
            advance ()
            wrap "Unit" UnitLit
        | _ ->
            let first = expr ()

            if isSym "," then
                let xs = ResizeArray [ first ]

                while isSym "," do
                    advance ()
                    xs.Add(expr ())

                expect (KSym ")") "')'"
                wrap "Tuple" (Tuple(List.ofSeq xs))
            elif isSym ":" then
                // (e: T)
                advance ()
                let t = ty ()
                expect (KSym ")") "')'"
                wrap "Typed" (Typed(first, t))
            else
                expect (KSym ")") "')'"
                wrap "Paren" first

    // $"a {x} b"  ==>  "a " + string x + " b"
    and interpolate ln parts =
        parts
        |> List.filter (fun (isExpr, s, _) -> isExpr || s <> "")
        |> List.map (fun (isExpr, s, col) ->
            if isExpr then
                // the hole's tokens, moved to where they are in the file, so they get positions too
                let holeToks =
                    lex s
                    |> Array.map (fun t ->
                        if t.col > 0 then
                            { t with line = ln; col = t.col + col - 1 }
                        else
                            { t with line = ln })

                let e =
                    try
                        (let _, e, _ = parseTokens holeToks true track in e).Value
                    with
                    | CompileError(_, msg)
                    | CompileErrorPos(_, _, msg) -> fail ln msg

                Call("Show.show", [ e ]) // Show's, whatever `string` names where the hole is
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
                start "FieldValue"
                let f = ident ()
                expect (KSym "=") "'='"
                items.Add(f, expr ())
                finish ()

                if isSym ";" then
                    advance ()

                go <- not (isSym "}")

            advance ()
            List.ofSeq items

        match peek (), peek2 () with
        | KId _, KSym "=" -> RecordLit(fields ())
        | _ ->
            let e = expr ()

            if peek () <> KKw "with" then
                errAt "braces don't make a block: a function body is its indented lines, and { } makes a record ({ x = 1; y = 2 } or { r with x = 1 })"

            advance ()
            Update(e, fields ())

    /// After a name, at `{`: whether a computation expression's body follows rather than a
    /// record: an indented block, or a statement only a computation expression starts with.
    and ceAhead () =
        isSym "{"
        && (match toks[min (pos.Value + 1) (toks.Length - 1)].tok with
            | KIndent
            | KKw("let" | "do" | "for" | "if" | "match" | "while")
            | KId("return" | "use" | "yield") -> true
            | _ -> false)

    /// `w { … }`, a computation expression (DESIGN §4): its statements become calls of the
    /// builder module's functions (W.Builder: task { } uses Task.Builder): `let!` and `do!`
    /// bind, `return` ret, `use` using, `for` forEach, and an `if` without `else`, or a body
    /// ending in a plain statement, zero. `return!` is the computation itself. The whole body
    /// is given to delay as a function, so a cold computation (a task) runs it when it runs.
    and computation (ln: int) (w: string) =
        let builder = string (Char.ToUpper w[0]) + w.Substring 1 + ".Builder."
        advance () // {

        if w = "seq" then
            // a sequence: its body in direct style, run when the sequence is consumed; a yield
            // anywhere in it (in a lambda too) is the Yield effect's, yield! another's elements
            let outerTask = inTask.Value
            inSeq.Value <- inSeq.Value + 1
            inTask.Value <- 0

            let body =
                try
                    if peek () = KIndent then
                        node "Block" (fun () ->
                            advance ()
                            let e = seq ()
                            expect KDedent "end of block"
                            e)
                    else
                        block ()
                finally
                    inSeq.Value <- inSeq.Value - 1
                    inTask.Value <- outerTask

            expect (KSym "}") "'}'"
            At(ln, Call("$seq", [ Lambda([ PUnit, None ], body) ]))
        elif w = "task" then
            // a task: its body in direct style, with let!, do! and return!, which the compiler
            // makes a state machine of ($task, $await)
            inTask.Value <- inTask.Value + 1

            let body =
                try
                    if peek () = KIndent then
                        node "Block" (fun () ->
                            advance ()
                            let e = seq ()
                            expect KDedent "end of block"
                            e)
                    else
                        block ()
                finally
                    inTask.Value <- inTask.Value - 1

            expect (KSym "}") "'}'"
            At(ln, Call("$task", [ Lambda([ PUnit, None ], body) ]))
        else

        let body = ceBlock builder
        expect (KSym "}") "'}'"
        At(ln, Call(builder + "delay", [ Lambda([ PUnit, None ], body) ]))

    /// A block in a computation expression: after `then`, `else`, `do` or `->`.
    and ceBlock (builder: string) =
        if peek () = KIndent then
            node "Block" (fun () ->
                advance ()
                let e = ceStmts builder true
                expect KDedent "end of block"
                e)
        else
            ceStmts builder false

    /// A computation expression's statements: with many, every statement of the block (one
    /// per line), else one (a block on the line it starts).
    and ceStmts (builder: string) (many: bool) : Expr =
        let ln = line ()
        let si = pos.Value
        let stmt e = mark si (At(ln, e))

        let kind =
            match peek (), peek2 () with
            | KKw "let", KSym "!" -> "LetBang"
            | KKw "do", KSym "!" -> "DoBang"
            | KId "return", _ -> "Return"
            | KId "use", KId _ -> "Use"
            | KKw "let", _ -> "Let"
            | KKw "for", _ -> "For"
            | KKw "if", _ -> "If"
            | KKw "match", _ -> "Match"
            | _ -> ""

        // the statement's node ends before the statements after it
        let closed = ref (kind = "")

        let close () =
            if not closed.Value then
                closed.Value <- true
                finish ()

        if kind <> "" then
            start kind

        let call f args = Call(builder + f, args)
        let unitPat = PUnit, None

        // `!` right after the keyword: let!, do!, return!
        let bang () =
            if isSym "!" && toks[pos.Value].adj then
                advance ()
                true
            else
                false

        // the statements after this one, if any
        let next () =
            close ()

            if many && peek () = KNewline then
                advance ()
                Some(ceStmts builder true)
            else
                None

        let needNext what =
            match next () with
            | Some r -> r
            | None -> fail ln (sprintf "a computation expression can't end with %s: return something after it" what)

        // a statement giving the builder's unit, then the rest
        let thenRest (e: Expr) =
            match next () with
            | Some rest -> stmt (call "bind" [ e; Lambda([ unitPat ], rest) ])
            | None -> stmt e

        let r =
            match peek () with
            | KKw "let" when (match peek2 () with
                              | KSym "!" -> true
                              | _ -> false) ->
                advance ()
                advance ()
                let p = pattern ()
                expect (KSym "=") "'='"
                let v = block ()
                stmt (call "bind" [ v; Lambda([ p, None ], needNext "let!") ])
            | KKw "do" when peek2 () = KSym "!" ->
                advance ()
                advance ()
                let v = block ()

                let rest =
                    match next () with
                    | Some r -> r
                    | None -> call "ret" [ UnitLit ]

                stmt (call "bind" [ v; Lambda([ unitPat ], rest) ])
            | KId "return" ->
                advance ()
                let e = if bang () then block () else call "ret" [ block () ]

                if many && peek () = KNewline then
                    fail (line ()) "nothing can follow return in a computation expression"

                stmt e
            | KId "use" when (match peek2 () with
                              | KId _ -> true
                              | _ -> false) ->
                advance ()
                let xi = pos.Value
                let x = ident ()
                expect (KSym "=") "'='"
                let v = block ()

                let rest =
                    match next () with
                    | Some r -> r
                    | None -> call "zero" [ UnitLit ]

                stmt (call "using" [ v; Lambda([ mark xi (PIdent(x, None)), None ], rest) ])
            | KKw "for" when (
                // for x in xs do: the builder's forEach; a range (for i in a .. b) is a plain loop
                let saved = save ()
                advance ()
                pattern () |> ignore
                let ok = peek () = KKw "in" && (advance (); pipe () |> ignore; peek () = KKw "do")
                restore saved
                ok) ->
                advance ()
                let p = pattern ()
                expect (KKw "in") "'in'"
                let xs = pipe ()
                expect (KKw "do") "'do'"
                let body = ceBlock builder
                thenRest (call "forEach" [ xs; Lambda([ p, None ], body) ])
            | KKw "if" ->
                advance ()
                let c = expr ()
                expect (KKw "then") "'then'"
                let t = ceBlock builder

                if peek () = KNewline && peek2 () = KKw "else" then
                    advance ()

                let e =
                    if peek () = KKw "else" then
                        advance ()
                        ceBlock builder
                    else
                        call "zero" [ UnitLit ]

                thenRest (If(c, t, Some e))
            | KKw "match" ->
                advance ()
                let s = expr ()
                expect (KKw "with") "'with'"
                let cases = casesWith (fun () -> ceBlock builder)
                thenRest (Match(s, cases))
            | KKw "let" ->
                // a plain let: a value, or a local function
                advance ()
                let isRec = peek () = KKw "rec"

                if isRec then
                    advance ()

                match peek (), peek2 () with
                | KId f, nxt when (isRec || Char.IsLower f[0] || f[0] = '_') && f <> "_" && startsParam nxt ->
                    let fi = pos.Value
                    advance ()
                    let ps = parameters ()
                    let ret = optTy ()
                    expect (KSym "=") "'='"
                    let body = block ()
                    stmt (mark fi (LetFun(f, isRec, ps, ret, body, needNext "let")))
                | _ ->
                    let p = pattern ()
                    let ann = optTy ()
                    expect (KSym "=") "'='"
                    let v = block ()
                    stmt (Let(p, ann, v, needNext "let"))
            | _ ->
                // a plain statement (of type unit)
                let at = here ()
                let e = assignment at (expr ())

                match next () with
                | Some rest -> stmt (Seq(e, rest))
                | None -> stmt (Seq(e, call "zero" [ UnitLit ]))

        close ()
        r

    let typeBody () =
        if peek () = KKw "member" || peek () = KKw "static" then
            UnionTy [] // only members: a type with no values
        elif isSym "{" then
            start "RecordBody"
            advance ()
            let fields = ResizeArray()
            let mutable go = true

            while go do
                if peek () = KKw "mutable" then
                    errAt "record fields can't be mutable: a record is a value; change one with { r with x = … }, bind it with let mutable, or make the field a ref<T>"

                start "Field"
                let f = ident ()
                expect (KSym ":") "':'"
                let t = ty ()

                let def =
                    if isSym "=" then
                        advance ()
                        Some(expr ())
                    else
                        None

                finish ()
                fields.Add(f, t, def)

                if isSym ";" then
                    advance ()

                go <- not (isSym "}")

            advance ()
            finish ()
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
            start "UnionBody"

            let case () =
                start "Case"

                if isSym "|" then
                    advance ()

                let c = ident ()
                let fields = ResizeArray()

                if peek () = KKw "of" then
                    advance ()
                    fields.Add(field ())

                    while isSym "*" do
                        advance ()
                        fields.Add(field ())

                cases.Add(c, List.ofSeq fields)
                finish ()

            if peek () = KNewline && peek2 () = KSym "|" then
                advance ()

            case ()

            while isSym "|" || (peek () = KNewline && peek2 () = KSym "|") do
                if peek () = KNewline then
                    advance ()

                case ()

            finish ()
            UnionTy(List.ofSeq cases)

    let rec memberDecl () : Member = node "Member" memberOf

    and memberOf () : Member =
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
        let kind =
            match peek () with
            | KSym "[<" -> "Attributed"
            | KKw "open" -> "Open"
            | KKw "namespace" -> "Namespace"
            | KKw "module" -> "Module"
            | KKw "derive" -> "Derive"
            | KKw "type" -> "Type"
            | KKw "trait" -> "Trait"
            | KKw "effect" -> "Effect"
            | KKw "impl" -> "Impl"
            | KId "import" -> "Import"
            | KKw "extern" -> "Extern"
            | KKw "let" -> "Let"
            | _ -> ""

        if kind = "" then declOf () else node kind declOf

    and declOf () =
        let ln = line ()

        match peek () with
        | KSym "[<" ->
            // [<Name; Name(arg, arg)>] before a declaration
            start "Attributes"
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
            finish ()

            if peek () = KNewline then
                advance ()

            let _, d = decl ()
            ln, Attrs(List.ofSeq attrs, d)
        | KKw "open" ->
            advance ()
            ln, Open(ident ())
        | KKw "namespace" ->
            // namespace Collections: the file's types and modules are Collections.Name (one
            // namespace can span files, like a module header that several files share)
            advance ()
            ln, ModuleHeader(ident ())
        | KKw "module" ->
            advance ()
            let name = ident ()

            if isSym "=" then
                // module Inner =, then its declarations, indented
                advance ()
                expect KIndent "indented declarations"
                let decls = ResizeArray()

                while peek () <> KDedent && peek () <> KEof do
                    decls.Add(decl ())

                    if peek () = KNewline then
                        advance ()

                expect KDedent "end of module"
                ln, NestedModule(name, List.ofSeq decls)
            else
                ln, ModuleHeader name
        | KKw "derive" when (match toks[min (pos.Value + 3) (toks.Length - 1)].tok with
                             | KId _ -> true
                             | _ -> false) ->
            // derive Json = ToJson, FromJson: a name for several derives
            advance ()
            let name = ident ()
            expect (KSym "=") "'='"
            let members = ResizeArray [ ident () ]

            while isSym "," do
                advance ()
                members.Add(ident ())

            ln, DeriveGroup(name, List.ofSeq members)
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
            let _, d = declOf ()
            ln, Private d
        | KKw "type" ->
            advance ()
            let name = ident ()

            if isSym "(" then
                errAt "classes aren't in Z#: a type is a record { … }, a union | … or an alias; put its functions in a module, or add members to a record with `with`"

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
        | KKw "effect" ->
            // effect Yield<'a> = abstract yield : 'a -> unit …
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

            expect (KSym "=") "'='"
            let indented = peek () = KIndent

            if indented then
                advance ()

            let ops = ResizeArray()

            while peek () = KKw "abstract" do
                advance ()
                let m = mark pos.Value (ident ()) // its position: the operation's definition
                expect (KSym ":") "':'"
                ops.Add(m, ty ())

                if indented && peek () = KNewline then
                    advance ()

            if ops.Count = 0 then
                err "'abstract' operations (abstract op : T -> R)"

            if indented then
                expect KDedent "end of effect"

            ln, Effect(name, List.ofSeq tparams, List.ofSeq ops)
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
        | KId "import" ->
            // import c "header.h"
            advance ()

            if peek () <> KId "c" then
                fail ln "expected 'c' after 'import': import c \"header.h\""

            advance ()

            match peek () with
            | KStr h ->
                advance ()
                ln, ImportC h
            | _ -> fail ln "expected a header name: import c \"header.h\""
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

            // an active pattern: (|Even|Odd|) or (|Int|_|); an operator: (>>=)
            let ni = pos.Value

            let ni, name =
                if isSym "(" && peek2 () = KSym "|" then
                    advance ()
                    advance ()
                    let names = ResizeArray [ ident () ]

                    while isSym "|" && peek2 () <> KSym ")" do
                        advance ()
                        names.Add(ident ())

                    expect (KSym "|") "'|'"
                    expect (KSym ")") "')'"
                    ni, "|" + String.concat "|" names + "|"
                elif isSym "(" && operatorAhead () then
                    advance ()
                    operatorName ()
                else
                    ni, ident ()
            let ps = parameters ()

            if ps.IsEmpty then
                // a top-level value: let name [: T] = expr
                if isRec then
                    fail ln "'let rec' needs parameters; a value can't refer to itself"

                let ann = optTy ()
                expect (KSym "=") "'='"
                let v = mark ni (Value(name, ann, block ()))
                ln, (if isPrivate then Private v else v)
            else
                let ret = optTy ()
                expect (KSym "=") "'='"
                let f = mark ni (Fun(name, isRec, ps, ret, block ()))
                let first = if isPrivate then Private f else f

                if peek () = KNewline && peek2 () = KKw "and" then
                    // let rec f … and g …: functions that call each other
                    if not isRec then
                        fail (line ()) "functions joined with 'and' call each other: write 'let rec f … and g …'"

                    let members = ResizeArray [ ln, first ]

                    while peek () = KNewline && peek2 () = KKw "and" do
                        advance ()
                        let gl = line ()
                        advance ()
                        let gPrivate = peek () = KKw "private"

                        if gPrivate then
                            advance ()

                        let gi = pos.Value
                        let g = ident ()
                        let gps = parameters ()

                        if gps.IsEmpty then
                            fail gl "'and' defines a function: and g x = …"

                        let gret = optTy ()
                        expect (KSym "=") "'='"
                        let gf = mark gi (Fun(g, true, gps, gret, block ()))
                        members.Add(gl, (if gPrivate then Private gf else gf))

                    ln, FunGroup(List.ofSeq members)
                else
                    ln, first
        | _ -> err "'let', 'type' or 'extern'"

    let tree () =
        advance () // the end of file, with the trivia before it
        let _, children = opened.Pop()
        { kind = "File"; children = children.ToArray() }

    if exprOnly then
        let e = expr ()

        if peek () <> KEof then
            err "end of expression"

        [], Some e, tree ()
    else
        let decls =
            [ while peek () <> KEof do
                  yield decl ()

                  if peek () = KNewline then advance ()
                  elif peek () <> KEof then err "end of line" ]

        decls, None, tree ()

let parse (toks: Token[]) : (int * Decl) list =
    let decls, _, _ = parseTokens toks false true
    decls

/// A file's declarations and its syntax tree.
let parseWithTree (toks: Token[]) : (int * Decl) list * Node =
    let decls, _, tree = parseTokens toks false true
    decls, tree
