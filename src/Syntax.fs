module Syntax

open System
open System.Collections.Generic
open System.Text

exception CompileError of line: int * msg: string

/// line 0 = "unknown here"; the nearest enclosing statement/declaration fills it in.
let fail line msg = raise (CompileError(line, msg))

type SType =
    | STName of string
    | STTuple of SType list

type Pat =
    | PWild
    | PIdent of string * Pat option // variable, or constructor with optional payload
    | PInt of int64
    | PBool of bool
    | PUnit
    | PTuple of Pat list
    | POr of Pat * Pat
    | PAs of Pat * string

type Expr =
    | Lit of int64
    | BoolLit of bool
    | StrLit of string
    | UnitLit
    | Var of string
    | Call of string * Expr list // phase 1: only named functions and constructors are callable
    | Bin of string * Expr * Expr
    | Neg of Expr
    | Not of Expr
    | If of Expr * Expr * Expr option
    | Let of Pat * SType option * Expr * Expr
    | Seq of Expr * Expr
    | Tuple of Expr list
    | RecordLit of (string * Expr) list
    | Update of Expr * (string * Expr) list
    | Field of Expr * string
    | Match of Expr * (Pat * Expr option * Expr) list
    | At of int * Expr // source line, for error messages

type TypeBody =
    | RecordTy of (string * SType) list
    | UnionTy of (string * SType list) list

type Decl =
    | Extern of name: string * args: SType list * variadic: bool * ret: SType
    | Fun of name: string * isRec: bool * pars: (string * SType option) list * ret: SType option * body: Expr
    | TypeDecl of name: string * TypeBody

// ---------------------------------------------------------------- lexer

type Tok =
    | KInt of int64
    | KStr of string
    | KId of string
    | KKw of string
    | KSym of string
    | KNewline
    | KIndent
    | KDedent
    | KEof

type Token = { tok: Tok; line: int }

let showTok =
    function
    | KInt n -> string n
    | KStr _ -> "string literal"
    | KId s
    | KKw s
    | KSym s -> sprintf "'%s'" s
    | KNewline -> "end of line"
    | KIndent -> "indented block"
    | KDedent -> "end of block"
    | KEof -> "end of file"

let keywords =
    set
        [ "let"; "rec"; "if"; "then"; "else"; "extern"; "true"; "false"; "not"
          "match"; "with"; "when"; "type"; "of"; "as" ]

// longest first
let symbols =
    [ "..."; "->"; "|>"; "<>"; "<="; ">="; "&&"; "||"
      "("; ")"; "{"; "}"; ","; ";"; "|"; "."; ":"; "="; "<"; ">"; "+"; "-"; "*"; "/"; "%" ]

let private unescape ln =
    function
    | 'n' -> '\n'
    | 't' -> '\t'
    | '0' -> '\000'
    | '\\' -> '\\'
    | '"' -> '"'
    | c -> fail ln (sprintf "unknown escape '\\%c'" c)

/// Offside rule: emits KIndent / KDedent / KNewline at line starts outside brackets.
/// A line starting with '|>' continues the previous one; a new line inside '{ }' acts as ';'.
let lex (src: string) : Token[] =
    let toks = ResizeArray<Token>()
    let indents = Stack<int>()
    indents.Push 0
    let brackets = Stack<char>()
    let mutable first = true
    let lines = src.Replace("\r\n", "\n").Split '\n'

    for li in 0 .. lines.Length - 1 do
        let line = lines[li]
        let ln = li + 1
        let add t = toks.Add { tok = t; line = ln }
        let mutable i = 0

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
        elif not blank && brackets.Count > 0 && brackets.Peek() = '{' && not (rest.StartsWith "}") then
            match toks[toks.Count - 1].tok with
            | KSym ";"
            | KSym "{"
            | KKw "with" -> ()
            | _ -> add (KSym ";")

        while i < line.Length do
            let c = line[i]

            if c = ' ' then
                i <- i + 1
            elif c = '/' && i + 1 < line.Length && line[i + 1] = '/' then
                i <- line.Length
            elif Char.IsDigit c then
                let s = i

                while i < line.Length && (Char.IsDigit(line[i]) || line[i] = '_') do
                    i <- i + 1

                let ok, n = Int64.TryParse(line.Substring(s, i - s).Replace("_", ""))

                if not ok then
                    fail ln "integer literal too large"

                add (KInt n)
            elif Char.IsLetter c || c = '_' then
                let s = i

                while i < line.Length && (Char.IsLetterOrDigit(line[i]) || line[i] = '_') do
                    i <- i + 1

                let w = line.Substring(s, i - s)
                add (if keywords.Contains w then KKw w else KId w)
            elif c = '"' then
                let sb = StringBuilder()
                i <- i + 1

                while i < line.Length && line[i] <> '"' do
                    if line[i] = '\\' && i + 1 < line.Length then
                        i <- i + 1
                        sb.Append(unescape ln (line[i])) |> ignore
                    else
                        sb.Append(line[i]) |> ignore

                    i <- i + 1

                if i >= line.Length then
                    fail ln "unterminated string literal"

                i <- i + 1
                add (KStr(sb.ToString()))
            else
                let at = i

                let sym =
                    symbols
                    |> List.tryFind (fun s -> at + s.Length <= line.Length && line.Substring(at, s.Length) = s)

                if sym.IsNone then
                    fail ln (sprintf "unexpected character '%c'" c)

                let s = sym.Value

                if s = "(" || s = "{" then brackets.Push s[0]
                if (s = ")" || s = "}") && brackets.Count > 0 then brackets.Pop() |> ignore
                add (KSym s)
                i <- i + s.Length

    for _ in 2 .. indents.Count do
        toks.Add { tok = KDedent; line = lines.Length }

    toks.Add { tok = KEof; line = lines.Length }
    toks.ToArray()

// ---------------------------------------------------------------- parser

let parse (toks: Token[]) : (int * Decl) list =
    let pos = ref 0
    let peek () = toks[pos.Value].tok
    let peek2 () = toks[min (pos.Value + 1) (toks.Length - 1)].tok
    let line () = toks[pos.Value].line
    let advance () = pos.Value <- pos.Value + 1
    let err what = fail (line ()) (sprintf "expected %s, found %s" what (showTok (peek ())))

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

    let rec tyAtom () =
        match peek () with
        | KId n ->
            advance ()
            STName n
        | KSym "(" ->
            advance ()
            let t = ty ()
            expect (KSym ")") "')'"
            t
        | _ -> err "type"

    and ty () =
        let first = tyAtom ()

        if isSym "*" then
            let items = ResizeArray [ first ]

            while isSym "*" do
                advance ()
                items.Add(tyAtom ())

            STTuple(List.ofSeq items)
        else
            first

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
        | KSym "-"
        | KKw "true"
        | KKw "false"
        | KSym "(" -> true
        | _ -> false

    let rec pattern () =
        let mutable p = orPat ()

        while peek () = KKw "as" do
            advance ()
            p <- PAs(p, ident ())

        p

    and orPat () =
        let mutable p = tuplePat ()

        while isSym "|" do
            advance ()
            p <- POr(p, tuplePat ())

        p

    and tuplePat () =
        let first = appPat ()

        if isSym "," then
            let items = ResizeArray [ first ]

            while isSym "," do
                advance ()
                items.Add(appPat ())

            PTuple(List.ofSeq items)
        else
            first

    and appPat () =
        match peek () with
        | KId c when c <> "_" && startsPatAtom (peek2 ()) ->
            advance ()
            PIdent(c, Some(patAtom ()))
        | _ -> patAtom ()

    and patAtom () =
        let t = peek ()

        if not (startsPatAtom t) then
            err "pattern"

        advance ()

        match t with
        | KId "_" -> PWild
        | KId x -> PIdent(x, None)
        | KInt n -> PInt n
        | KSym "-" ->
            match peek () with
            | KInt n ->
                advance ()
                PInt -n
            | _ -> err "integer"
        | KKw "true" -> PBool true
        | KKw "false" -> PBool false
        | _ when isSym ")" ->
            advance ()
            PUnit
        | _ ->
            let p = pattern ()
            expect (KSym ")") "')'"
            p

    let rec block () =
        if peek () = KIndent then
            advance ()
            let e = seq ()
            expect KDedent "end of block"
            e
        else
            expr ()

    and seq () =
        let ln = line ()

        if peek () = KKw "let" then
            advance ()
            let p = pattern ()
            let ann = optTy ()
            expect (KSym "=") "'='"
            let v = block ()

            if peek () <> KNewline then
                fail ln "'let' must be followed by an expression on the next line"

            advance ()
            At(ln, Let(p, ann, v, seq ()))
        else
            let e = At(ln, expr ())

            if peek () = KNewline then
                advance ()
                Seq(e, seq ())
            else
                e

    and expr () =
        if peek () = KKw "if" then
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
        elif peek () = KKw "match" then
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
        else
            pipe ()

    // x |> f a  ==>  f a x
    and pipe () =
        let mutable l = orE ()

        while isSym "|>" do
            let ln = line ()
            advance ()

            l <-
                match orE () with
                | Var f -> Call(f, [ l ])
                | Call(f, args) -> Call(f, args @ [ l ])
                | _ -> fail ln "right side of '|>' must be a function call"

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

    and cmpE () = binary [ "="; "<>"; "<"; ">"; "<="; ">=" ] addE
    and addE () = binary [ "+"; "-" ] mulE
    and mulE () = binary [ "*"; "/"; "%" ] unary

    and unary () =
        if isSym "-" then
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
        | KStr _
        | KId _
        | KKw "true"
        | KKw "false"
        | KSym "("
        | KSym "{" -> true
        | _ -> false

    and app () =
        match atom () with
        | Var f when startsAtom () -> Call(f, [ while startsAtom () do yield atom () ])
        | head -> head

    and atom () =
        let mutable e = primary ()

        while isSym "." do
            advance ()
            e <- Field(e, ident ())

        e

    and primary () =
        if not (startsAtom ()) then
            err "expression"

        let t = peek ()
        advance ()

        match t with
        | KInt n -> Lit n
        | KStr s -> StrLit s
        | KId x -> Var x
        | KKw "true" -> BoolLit true
        | KKw "false" -> BoolLit false
        | KSym "{" -> record ()
        | _ when isSym ")" ->
            advance ()
            UnitLit
        | _ ->
            let first = expr ()

            if isSym "," then
                let items = ResizeArray [ first ]

                while isSym "," do
                    advance ()
                    items.Add(expr ())

                expect (KSym ")") "')'"
                Tuple(List.ofSeq items)
            else
                expect (KSym ")") "')'"
                first

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
        if isSym "{" then
            advance ()
            let fields = ResizeArray()
            let mutable go = true

            while go do
                let f = ident ()
                expect (KSym ":") "':'"
                fields.Add(f, ty ())

                if isSym ";" then
                    advance ()

                go <- not (isSym "}")

            advance ()
            RecordTy(List.ofSeq fields)
        else
            // payload field: optional 'name:' then a type; '*' separates fields
            let field () =
                match peek (), peek2 () with
                | KId _, KSym ":" ->
                    advance ()
                    advance ()
                | _ -> ()

                tyAtom ()

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

    let decl () =
        let ln = line ()

        match peek () with
        | KKw "type" ->
            advance ()
            let name = ident ()
            expect (KSym "=") "'='"
            let indented = peek () = KIndent

            if indented then
                advance ()

            let body = typeBody ()

            if indented then
                expect KDedent "end of block"

            ln, TypeDecl(name, body)
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
                    Some(ty ())

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

            let args =
                pars |> List.choose id |> List.filter (fun t -> t <> STName "unit")

            ln, Extern(name, args, variadic, ret)
        | KKw "let" ->
            advance ()
            let isRec = peek () = KKw "rec"

            if isRec then
                advance ()

            let name = ident ()
            let pars = ResizeArray()
            let mutable unitParam = false
            let mutable go = true

            while go do
                match peek (), peek2 () with
                | KId x, _ ->
                    advance ()
                    pars.Add(x, None)
                | KSym "(", KSym ")" ->
                    advance ()
                    advance ()
                    unitParam <- true
                | KSym "(", _ ->
                    advance ()
                    let x = ident ()
                    expect (KSym ":") "':'"
                    let t = ty ()
                    expect (KSym ")") "')'"
                    pars.Add(x, Some t)
                | _ -> go <- false

            if pars.Count = 0 && not unitParam then
                fail ln "top-level values are not supported yet; write 'let f () = ...'"

            let ret = optTy ()
            expect (KSym "=") "'='"
            ln, Fun(name, isRec, List.ofSeq pars, ret, block ())
        | _ -> err "'let', 'type' or 'extern'"

    [ while peek () <> KEof do
          yield decl ()

          if peek () = KNewline then advance ()
          elif peek () <> KEof then err "end of line" ]
