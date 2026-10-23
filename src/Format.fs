/// zs fmt: one canonical layout, no options (decision 33). Each line keeps the breaks it was written
/// with and is re-indented from the block structure (2 spaces a level; lines inside brackets one
/// level past their opener's line), spaced the same way everywhere, trimmed, with at most one blank
/// line between; comments stay where they are. A line over 100 columns is then broken on the
/// syntax tree (0019), outermost construct first: after a binding's `=` or a lambda's `->`, at an
/// `if`'s branches, before a pipeline's `|>`, between a match's clauses and between the items of a
/// tuple, list, array or record, and between a call's arguments inside brackets. String literals
/// and comments never break, so a line long because of one stays long. A break is kept only when
/// the program parses to the same tree, so formatting can't change what a program means.
module Format

open System
open System.Text
open System.Collections.Generic
open Syntax

/// The width a line is broken to fit.
let width = 100

let private openers = set [ "("; "["; "[|"; "{"; "[<" ]
let private closers = set [ ")"; "]"; "|]"; "}"; ">]" ]

/// Where spacing carries meaning (f(x) vs f (x), f -x, 9.58<s>, x?, list<int>, let!) or is a matter
/// of taste the source already settled, it stays as written.
let private asWritten = set [ "("; ")"; "<"; ">"; "."; "?"; "^"; "|"; "~-"; ">>"; ":"; "<-"; "!" ]

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

/// A token's text on the line it starts on (a string can span lines).
let private firstLine (s: string) =
    match s.IndexOf '\n' with
    | -1 -> s
    | i -> s.Substring(0, i)

/// The `//` comment on each line, from the tokens' trivia.
let private commentsOf (toks: Token[]) =
    let found = Dictionary<int, string>()
    let line = ref 1

    let count (s: string) =
        for c in s do
            if c = '\n' then
                line.Value <- line.Value + 1

    let trivia (ts: Trivia list) =
        for x in ts do
            match x with
            | Comment s
            | DocComment s -> found[line.Value] <- s.TrimEnd()
            | Space _
            | Newline -> count (triviaText x)

    for t in toks do
        trivia t.lead
        count t.text
        trivia t.trail

    found

/// Each line as written, laid out: its indentation from the blocks and brackets it is in, its
/// tokens spaced, its comment; at most one blank line between.
let private layout (src: string) (toks: Token[]) : string =
    let lines = src.Split '\n'
    let commentAt = commentsOf toks

    // each code line: its indentation level and its tokens with their text
    let code = Dictionary<int, int * (Token * string) list>()
    let mutable depth = 0
    let mutable current = -1
    let mutable lineToks = []
    let mutable lineLevel = 0
    let mutable lastLine = 0
    // each open bracket: the line it opened on, whether a block opened inside it yet, and
    // whether that block took the bracket's level, so `(fun x ->` with its body below is one
    // level in, not two
    let opened = Stack<int * bool ref * bool ref>()
    let mutable absorbed = 0

    let flush () =
        if current > 0 then
            code[current] <- (lineLevel, List.rev lineToks)

        lineToks <- []

    // the lines after the first of a string that spans lines are its text: they stay as written
    let verbatim = HashSet<int>()

    for t in toks do
        for l in t.line + 1 .. t.last do
            verbatim.Add l |> ignore

    for t in toks do
        match t.tok with
        | KIndent ->
            depth <- depth + 1

            if opened.Count > 0 then
                let line, framed, took = opened.Peek()

                if not framed.Value then
                    framed.Value <- true

                    if line = lastLine then
                        took.Value <- true
                        absorbed <- absorbed + 1
        | KDedent -> depth <- depth - 1
        | _ when verbatim.Contains t.line || t.text = "" -> ()
        | _ ->
            let text = firstLine t.text

            if t.line <> current then
                flush ()
                current <- t.line

                // a closer lines up with its opener's line, unless a block took its level
                let closesOwnLevel =
                    closers.Contains(symText t.tok)
                    && opened.Count > 0
                    && (let _, _, took = opened.Peek() in not took.Value)

                lineLevel <- depth + opened.Count - absorbed - (if closesOwnLevel then 1 else 0)

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
            match code.TryGetValue l, commentAt.TryGetValue l with
            | _ when verbatim.Contains l -> Some lines[l - 1]
            | (true, (level, ts)), (true, c) -> Some(render level ts + " " + c)
            | (true, (level, ts)), _ -> Some(render level ts)
            | _, (true, c) -> Some(String.replicate (2 * nextLevel l) " " + c) // a comment on its own line
            | _ -> None

        match text with
        | Some t ->
            if blank > 0 && out.Count > 0 then
                out.Add ""

            blank <- 0
            out.Add t
        | None -> blank <- blank + 1

    String.concat "\n" out + "\n"

/// The tree without what layout decides: layout tokens, `;` (a line break is one inside [ ] and
/// { }) and blocks (a body below its `=` rather than beside it), so two layouts of one program
/// have the same shape, and a break that changed the program doesn't.
let rec private shape (n: Node) : string list =
    [ if n.kind <> "Block" then
          yield "(" + n.kind

      for c in n.children do
          match c with
          | T t when t.text = "" || t.text = ";" -> ()
          | T t -> yield t.text
          | N m -> yield! shape m

      if n.kind <> "Block" then
          yield ")" ]

let private firstToken (c: Child) =
    match c with
    | T t when t.text <> "" -> Some t
    | T _ -> None
    | N n -> tokensOf n |> Seq.tryFind (fun t -> t.text <> "")

/// Where a node may break: the written tokens a line break may go before, each with the token
/// whose end the break starts from (a `;` it replaces is skipped over) and whether the line after
/// it is a level deeper (a block: after `=`, `->`, `then` and `else`) or at the line's own level
/// (`else`, a match's `|`, a pipeline's `|>`); and whether the breaks are of the program's
/// structure, taken whenever they parse, or between a bracket's items, taken only when every line
/// they make fits. Z#'s offside rule allows no other: a call's arguments can't continue on the
/// next line outside brackets.
let rec private breaks (n: Node) : (Token * Token * bool) list * bool =
    let cs = n.children
    let written = cs |> Array.map firstToken
    // the written token before child k
    let before k =
        Seq.init k (fun j -> cs[k - 1 - j])
        |> Seq.tryPick (fun c ->
            match c with
            | T t when t.text <> "" -> Some t
            | N m -> tokensOf m |> Seq.filter (fun t -> t.text <> "") |> Seq.tryLast
            | _ -> None)

    let atLevel deeper k =
        match before k, written[k] with
        | Some p, Some t -> [ p, t, deeper ]
        | _ -> []

    let at = atLevel true
    let same = atLevel false

    let isTok s (c: Child) =
        match c with
        | T t -> t.text = s
        | _ -> false

    let after s = [ for k in 1 .. cs.Length - 1 do if isTok s cs[k - 1] && not (isTok "" cs[k]) then yield! at k ]

    match n.kind with
    | "Let"
    | "Member"
    | "Use"
    | "LetBang" -> after "=", true
    | "Lambda"
    | "Clause" -> after "->", true
    | "If" ->
        // the branches, and `else` on its own line; an `else if` stays on one line, and its
        // `if` breaks with this one
        [ for k in 1 .. cs.Length - 1 do
              if isTok "then" cs[k - 1] then
                  yield! at k
              elif isTok "else" cs[k] then
                  yield! same k
              elif isTok "else" cs[k - 1] then
                  match cs[k] with
                  | N m when m.kind = "If" -> yield! fst (breaks m)
                  | _ -> yield! at k ],
        true
    | "Infix" ->
        // before a pipeline's |> or a custom operator: a line starting with one continues the
        // line before
        [ for k in 1 .. cs.Length - 1 do
              match cs[k] with
              | T t when t.text = "|>" || isInfixOp t.text -> yield! same k
              | _ -> () ],
        true
    | "Match"
    | "Function"
    | "Handle" -> [ for k in 1 .. cs.Length - 1 do match cs[k] with N m when m.kind = "Clause" -> yield! same k | _ -> () ], true
    | "Tuple" -> after ",", false
    // a line break inside [ ] and { } is a `;`; inside [| |] it's only space, so the `;` stays
    | "List"
    | "Record" ->
        [ for k in 2 .. cs.Length - 1 do
              if isTok ";" cs[k - 1] && not (isTok "" cs[k]) then
                  match before (k - 1), written[k] with
                  | Some p, Some t -> yield p, t, true
                  | _ -> () ],
        false
    | "Array" -> after ";", false
    | _ -> [], true

/// Breaks the lines of a laid-out text that are over the width, outermost construct first (and
/// only one that runs past the width, as a Wadler group breaks), keeping each break only when the
/// text still parses to the same shape.
let private reflow (text: string) (expected: string list) : string =
    let rec loop (text: string) (rejected: Set<int list>) =
        let toks = lex text
        let _, tree = parseWithTree toks
        // each line's code width (a line holding a string that spans lines is left alone)
        let widthOf = Dictionary<int, int>()
        let multi = HashSet<int>()
        let firstOn = Dictionary<int, Token>() // the line's first written token
        let endOf (t: Token) = t.col - 1 + t.text.Length

        for t in toks do
            if t.text <> "" then
                if t.last > t.line then
                    multi.Add t.line |> ignore

                widthOf[t.line] <- max (match widthOf.TryGetValue t.line with | true, w -> w | _ -> 0) (endOf t)

                if not (firstOn.ContainsKey t.line) then
                    firstOn[t.line] <- t

        let long =
            widthOf
            |> Seq.filter (fun kv -> kv.Value > width && not (multi.Contains kv.Key))
            |> Seq.map (fun kv -> kv.Key)
            |> Seq.sort
            |> List.ofSeq

        // the candidates on a line: each node's breaks there, outermost first, of the nodes that
        // run past the width on it
        let candidates (line: int) =
            let found = ResizeArray<int * ((Token * Token * bool) list * bool)>()

            let rec walk (n: Node) (depth: int) =
                let reach = tokensOf n |> Seq.filter (fun t -> t.text <> "" && t.line = line) |> Seq.map endOf |> Seq.fold max 0
                let continues = tokensOf n |> Seq.exists (fun t -> t.text <> "" && t.line > line)

                if reach > width || (continues && widthOf[line] > width && reach > 0) then
                    let points, structural = breaks n

                    // never before a token written against the one before it: f(x), x?, a.[i]
                    let here =
                        points
                        |> List.filter (fun (p, t, _) -> t.line = line && p.line = line && firstOn[line].offset <> t.offset && not t.adj)

                    if not here.IsEmpty then
                        found.Add(depth, (here, structural))

                    for c in n.children do
                        match c with
                        | N m -> walk m (depth + 1)
                        | T _ -> ()

            walk tree 0
            found |> Seq.sortBy fst |> Seq.map snd |> List.ofSeq

        let attempt (line: int) (cut: (Token * Token * bool) list, structural: bool) =
            let sb = StringBuilder()
            let mutable from = 0

            for p, t, deeper in cut |> List.sortBy (fun (_, t, _) -> t.offset) do
                // the new line's indentation: the lexer reads a block from it
                let indent = firstOn[p.line].col - 1 + (if deeper then 2 else 0)
                sb.Append(text, from, p.offset + p.text.Length - from).Append('\n').Append(' ', indent) |> ignore
                from <- t.offset

            sb.Append(text, from, text.Length - from) |> ignore
            let broken = sb.ToString()

            try
                let laid = layout broken (lex broken)
                let _, t = parseWithTree (lex laid)
                // a bracket's items break only into lines that fit
                let made = (laid.Split '\n').Length - (text.Split '\n').Length

                let fits () =
                    (laid.Split '\n')[line - 1 .. line - 1 + made]
                    |> Array.forall (fun l -> l.Length <= width || l.TrimStart().StartsWith "//")

                if shape t = expected && (structural || fits ()) then Some laid else None
            with
            | CompileError _
            | CompileErrorPos _ -> None

        let next =
            long
            |> Seq.collect (fun l -> candidates l |> Seq.map (fun c -> l, c))
            |> Seq.map (fun (l, (cut, structural)) -> (l, (cut, structural)), cut |> List.map (fun (_, t, _) -> t.offset))
            |> Seq.filter (fun (_, key) -> not (rejected.Contains key))
            |> Seq.tryHead

        match next with
        | None -> text
        | Some((l, cut), key) ->
            match attempt l cut with
            | Some laid -> loop laid Set.empty
            | None -> loop text (rejected.Add key)

    loop text Set.empty

/// Formats a source file; Error when the result would read differently (a formatter bug). A file
/// that doesn't parse raises its error.
let format (src: string) : Result<string, string> =
    let src = src.Replace("\r\n", "\n")
    let toks = lex src
    let _, tree = parseWithTree toks
    let expected = shape tree
    let laid = layout src toks

    let same (a: Token[]) (b: Token[]) =
        // a hole's column in $"…" moves with the indentation
        let kinds (ts: Token[]) =
            ts
            |> Array.filter (fun t -> t.tok <> KEof)
            |> Array.map (fun t ->
                match t.tok with
                | KInterp parts -> KInterp(parts |> List.map (fun (e, s, _) -> e, s, 0))
                | k -> k)

        kinds a = kinds b

    if not (same toks (lex laid)) then
        Error "formatting would change the program's tokens (a zs fmt bug; the file was left alone)"
    else
        let result = reflow laid expected
        let _, after = parseWithTree (lex result)

        if shape after = expected then
            Ok result
        else
            Error "formatting would change the program (a zs fmt bug; the file was left alone)"

/// Range formatting: the lines first..last (1-based) widened to the declarations and statements
/// they touch, and what those lines become, as (first line, last line, new text); None when the
/// lines are already formatted or the file doesn't parse.
let formatRange (src: string) (first: int) (last: int) : (int * int * string) option =
    let src = src.Replace("\r\n", "\n")

    try
        match format src with
        | Error _ -> None
        | Ok formatted ->
            let _, tree = parseWithTree (lex src)
            // the statements and declarations: the children of the file and of blocks
            let spans = ResizeArray<int * int>()

            let rec walk (n: Node) =
                for c in n.children do
                    match c with
                    | N m ->
                        if n.kind = "File" || n.kind = "Block" then
                            let ts = tokensOf m |> Seq.filter (fun t -> t.text <> "") |> Array.ofSeq

                            if ts.Length > 0 then
                                spans.Add(ts[0].line, ts[ts.Length - 1].last)

                        walk m
                    | T _ -> ()

            walk tree
            // the smallest statements covering each end of the range
            let cover (line: int) =
                spans
                |> Seq.filter (fun (a, b) -> a <= line && line <= b)
                |> Seq.sortBy (fun (a, b) -> b - a)
                |> Seq.tryHead
                |> Option.defaultValue (line, line)

            let a = min (fst (cover first)) (fst (cover last))
            let b = max (snd (cover first)) (snd (cover last))
            // the same tokens in the formatted text: written ones but `;`, counted from the start
            let written (text: string) =
                lex text |> Array.filter (fun t -> t.text <> "" && t.text <> ";")

            let before, after = written src, written formatted
            let inRange = [ for k in 0 .. before.Length - 1 do if before[k].line >= a && before[k].last <= b then k ]

            match inRange with
            | [] -> None
            | ks ->
                let lo, hi = List.head ks, List.last ks
                let lines = formatted.Split '\n'
                let text = String.concat "\n" lines[after[lo].line - 1 .. after[hi].last - 1]
                let old = String.concat "\n" (src.Split '\n')[a - 1 .. b - 1]
                if text = old then None else Some(a, b, text)
    with
    | CompileError _
    | CompileErrorPos _ -> None
