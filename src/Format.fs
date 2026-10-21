/// zs fmt: one canonical layout, no options. It re-indents from the block structure (2 spaces a
/// level; lines inside brackets line up one level past their opener), spaces operators and
/// punctuation the same way everywhere, trims trailing space and keeps at most one blank line.
/// Comments stay where they are. The token sequence never changes: the result is lexed again
/// and must give the same tokens, so formatting can't change what a program means.
// ponytail: works line by line on tokens; reflowing long lines (100 columns) needs a syntax tree
module Format

open System
open System.Text
open Syntax

let private openers = set [ "("; "["; "[|"; "{"; "[<" ]
let private closers = set [ ")"; "]"; "|]"; "}"; ">]" ]

/// Where spacing carries meaning (f(x) vs f (x), f -x, 9.58<s>, x?, list<int>) or is a matter
/// of taste the source already settled, it stays as written.
let private asWritten = set [ "("; ")"; "<"; ">"; "."; "?"; "^"; "|"; "~-"; ">>"; ":"; "<-" ]

let private isOperand (tok: Tok) =
    match tok with
    | KId _
    | KInt _
    | KFloat _
    | KStr _
    | KInterp _
    | KTyVar _
    | KKw("true" | "false") -> true
    | KSym s -> closers.Contains s
    | _ -> false

/// The source text of a token (layout tokens and the lexer's implied `;` have none).
let private textOf (lines: string[]) (t: Token) =
    if t.col <= 0 || t.line < 1 || t.line > lines.Length then
        None
    else
        let l = lines[t.line - 1]
        let start = t.col - 1

        if start + t.len > l.Length then
            None
        else
            let text = l.Substring(start, t.len)

            match t.tok with
            | KSym ";" when text <> ";" -> None // a line break inside { } or [ ], not a written ';'
            | KNewline
            | KIndent
            | KDedent
            | KEof -> None
            | _ -> Some text

let private symText (t: Tok) =
    match t with
    | KSym s -> s
    | KKw k -> k
    | _ -> ""

/// tight: inside a.[i] or between < > of type arguments and measures, where spacing stays as written.
let private space (prev: Token) (cur: Token) (unaryMinus: bool) (tight: bool) =
    let p, c = symText prev.tok, symText cur.tok

    if unaryMinus then ""
    elif tight || asWritten.Contains p || asWritten.Contains c || isPrefixOp p then (if cur.adj then "" else " ")
    elif openers.Contains p && closers.Contains c then "" // [] () {} [||]
    elif p = "[<" || c = ">]" then ""
    elif openers.Contains p || closers.Contains c then " "
    elif c = "," || c = ";" then ""
    else " "

/// Formats a source file; Error when the result would lex differently (a formatter bug).
let format (src: string) : Result<string, string> =
    let src = src.Replace("\r\n", "\n")
    let lines = src.Split '\n'
    let toks, comments = lexComments src
    let commentAt = comments |> List.map (fun (l, c, text) -> l, (c, text.TrimEnd())) |> Map.ofList

    // each code line: its indentation level and its tokens with their text
    let code = Collections.Generic.Dictionary<int, int * (Token * string) list>()
    let mutable layout = 0
    let mutable current = -1
    let mutable lineToks = []
    let mutable lineLevel = 0
    let mutable lastLine = 0
    // each open bracket: the line it opened on, whether a block opened inside it yet, and
    // whether that block took the bracket's level, so `(fun x ->` with its body below is one
    // level in, not two
    let opened = Collections.Generic.Stack<int * bool ref * bool ref>()
    let mutable absorbed = 0

    let flush () =
        if current > 0 then
            code[current] <- (lineLevel, List.rev lineToks)

        lineToks <- []

    for t in toks do
        match t.tok with
        | KIndent ->
            layout <- layout + 1

            if opened.Count > 0 then
                let line, framed, took = opened.Peek()

                if not framed.Value then
                    framed.Value <- true

                    if line = lastLine then
                        took.Value <- true
                        absorbed <- absorbed + 1
        | KDedent -> layout <- layout - 1
        | _ ->
            match textOf lines t with
            | None -> ()
            | Some text ->
                if t.line <> current then
                    flush ()
                    current <- t.line

                    // a closer lines up with its opener's line, unless a block took its level
                    let closesOwnLevel =
                        closers.Contains(symText t.tok)
                        && opened.Count > 0
                        && (let _, _, took = opened.Peek() in not took.Value)

                    lineLevel <- layout + opened.Count - absorbed - (if closesOwnLevel then 1 else 0)

                lineToks <- (t, text) :: lineToks
                lastLine <- t.line

                let s = symText t.tok

                if openers.Contains s then
                    opened.Push((t.line, ref false, ref false))
                elif closers.Contains s && opened.Count > 0 then
                    let _, _, took = opened.Pop()

                    if took.Value then
                        absorbed <- absorbed - 1

    flush ()

    let render (level: int) (ts: (Token * string) list) =
        let sb = StringBuilder(String.replicate (2 * level) " ")
        let mutable prev: (Token * string) option = None
        let mutable unaryNext = false
        let mutable tight = 0 // open a.[ … ] and f64< … > groups on this line

        for t, text in ts do
            match prev with
            | Some(p, _) -> sb.Append(space p t unaryNext (tight > 0)) |> ignore
            | None -> ()

            sb.Append text |> ignore

            if (text = "]" || text = ">") && tight > 0 then
                tight <- tight - 1

            match prev with
            | Some(_, ".") when text = "[" -> tight <- tight + 1
            | Some _ when text = "<" && t.adj -> tight <- tight + 1
            | _ -> ()

            // a '-' that doesn't follow an operand is a negation: nothing between it and its operand
            unaryNext <-
                (text = "-")
                && (match prev with
                    | Some(p, _) -> not (isOperand p.tok)
                    | None -> true)

            prev <- Some(t, text)

        sb.ToString()

    let nextLevel (from: int) =
        seq { from .. lines.Length }
        |> Seq.tryPick (fun l ->
            match code.TryGetValue l with
            | true, (level, _) -> Some level
            | _ -> None)
        |> Option.defaultValue 0

    let out = ResizeArray<string>()
    let mutable blank = 0

    for l in 1 .. lines.Length do
        let text =
            match code.TryGetValue l, commentAt.TryFind l with
            | (true, (level, ts)), Some(_, c) -> Some(render level ts + " " + c)
            | (true, (level, ts)), None -> Some(render level ts)
            | _, Some(_, c) -> Some(String.replicate (2 * nextLevel l) " " + c) // a comment on its own line
            | _ -> None

        match text with
        | Some t ->
            if blank > 0 && out.Count > 0 then
                out.Add ""

            blank <- 0
            out.Add t
        | None -> blank <- blank + 1

    let result = String.concat "\n" out + "\n"

    let same (a: Token[]) (b: Token[]) =
        let kinds (ts: Token[]) =
            ts
            |> Array.filter (fun t -> t.tok <> KEof)
            |> Array.map (fun t -> t.tok)

        kinds a = kinds b

    if same toks (lex result) then
        Ok result
    else
        Error "formatting would change the program's tokens (a zs fmt bug; the file was left alone)"
