module Syntax

open System
open System.Collections.Generic
open System.Text

exception CompileError of line: int * msg: string

/// line 0 = "unknown here"; the nearest enclosing statement/declaration fills it in.
let fail line msg = raise (CompileError(line, msg))

type Ty =
    | TInt
    | TCInt
    | TBool
    | TCStr
    | TUnit

let tyName =
    function
    | TInt -> "int"
    | TCInt -> "c_int"
    | TBool -> "bool"
    | TCStr -> "cstr"
    | TUnit -> "unit"

type Expr =
    | Lit of int64
    | BoolLit of bool
    | StrLit of string
    | UnitLit
    | Var of string
    | Call of string * Expr list // phase 0: only named functions are callable
    | Bin of string * Expr * Expr
    | Neg of Expr
    | Not of Expr
    | If of Expr * Expr * Expr option
    | Let of string * Ty option * Expr * Expr
    | Seq of Expr * Expr
    | At of int * Expr // source line, for error messages

type Decl =
    | Extern of name: string * args: Ty list * variadic: bool * ret: Ty
    | Fun of name: string * isRec: bool * pars: (string * Ty) list * ret: Ty option * body: Expr

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
    set [ "let"; "rec"; "if"; "then"; "else"; "extern"; "true"; "false"; "not" ]

// longest first
let symbols =
    [ "..."; "->"; "|>"; "<>"; "<="; ">="; "&&"; "||"; "("; ")"; ":"; "="; "<"; ">"; "+"; "-"; "*"; "/"; "%" ]

let private unescape ln =
    function
    | 'n' -> '\n'
    | 't' -> '\t'
    | '0' -> '\000'
    | '\\' -> '\\'
    | '"' -> '"'
    | c -> fail ln (sprintf "unknown escape '\\%c'" c)

/// Offside rule: emits KIndent / KDedent / KNewline at line starts outside parentheses.
/// A line starting with '|>' continues the previous one.
let lex (src: string) : Token[] =
    let toks = ResizeArray<Token>()
    let indents = Stack<int>()
    indents.Push 0
    let mutable depth = 0
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

        if not blank && depth = 0 && not (rest.StartsWith "|>") then
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

                if s = "(" then depth <- depth + 1
                if s = ")" then depth <- max 0 (depth - 1)
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

    let ty () =
        let t =
            match peek () with
            | KId "int" -> TInt
            | KId "c_int" -> TCInt
            | KId "bool" -> TBool
            | KId "cstr" -> TCStr
            | KId "unit" -> TUnit
            | _ -> err "type"

        advance ()
        t

    let optTy () =
        if isSym ":" then
            advance ()
            Some(ty ())
        else
            None

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
            let name = ident ()
            let ann = optTy ()
            expect (KSym "=") "'='"
            let v = block ()

            if peek () <> KNewline then
                fail ln "'let' must be followed by an expression on the next line"

            advance ()
            At(ln, Let(name, ann, v, seq ()))
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
        | KSym "(" -> true
        | _ -> false

    and app () =
        match peek () with
        | KId f ->
            advance ()
            let args = [ while startsAtom () do yield atom () ]

            if args.IsEmpty then Var f
            elif args = [ UnitLit ] then Call(f, [])
            else Call(f, args)
        | _ -> atom ()

    and atom () =
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
        | _ when isSym ")" ->
            advance ()
            UnitLit
        | _ ->
            let e = expr ()
            expect (KSym ")") "')'"
            e

    let decl () =
        let ln = line ()

        match peek () with
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

            let args = pars |> List.choose id |> List.filter (fun t -> t <> TUnit)
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
                    pars.Add(x, TInt)
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
                    pars.Add(x, t)
                | _ -> go <- false

            if pars.Count = 0 && not unitParam then
                fail ln "top-level values are not supported yet; write 'let f () = ...'"

            let ret = optTy ()
            expect (KSym "=") "'='"
            ln, Fun(name, isRec, List.ofSeq pars, ret, block ())
        | _ -> err "'let' or 'extern'"

    [ while peek () <> KEof do
          yield decl ()

          if peek () = KNewline then advance ()
          elif peek () <> KEof then err "end of line" ]
