/// Doc tests (0009, track D8): a fenced zsharp block in a `///` comment is a program, the body of
/// its `main`, and its `// => text` lines are what it prints, in order. `zs test --doc` runs each
/// one, and with `--update` rewrites a failing block's `// =>` lines to what it printed.
///   /// The elements in order.
///   ///
///   /// ```zsharp
///   /// println $"{List.sort [ 3; 1; 2 ]}"
///   /// // => [1; 2; 3]
///   /// ```
///   let sort (xs: list<'a>) = …

/// A block: the line of its opening fence (from 1), the declaration its comment is on, the lines
/// of its code (the comment's `/// ` taken off), and what it expects printed.
type Block = { line: int; decl: string; code: list<string>; expected: list<string> }

// a line's text after its `///` and one space, if it's a doc comment's line
let private docText (line: string) : option<string> =
  let t = String.trim line
  if String.startsWith "///" t then
    let rest = String.sub t 3 (String.length t - 3)
    Some(if String.startsWith " " rest then String.sub rest 1 (String.length rest - 1) else rest)
  else
    None

// the expectation a code line gives, if it's one
let private expectation (code: string) : option<string> =
  let t = String.trim code
  if t = "// =>" then Some ""
  else if String.startsWith "// => " t then Some(String.sub t 6 (String.length t - 6))
  else None

// the name a declaration's line gives: what follows let, type, module, … (rec, private and the
// like skipped), up to the first character a name can't have
let private declName (line: string) : string =
  let skip = Set.ofList [ "let"; "type"; "and"; "module"; "trait"; "impl"; "rec"; "private"; "inline"; "mutable" ]
  let words = List.filter (fun (w: string) -> w <> "") (String.split " " (String.trim line))
  match List.tryFind (fun (w: string) -> not (Set.contains w skip)) words with
  | Some w ->
    let isName (i: int) =
      let b = String.byte w i
      (b >= u8 48 && b <= u8 57) || (b >= u8 65 && b <= u8 90) || (b >= u8 97 && b <= u8 122) || b = u8 95 || b = u8 46
    let mutable n = 0
    while n < String.length w && isName n do
      n <- n + 1
    String.sub w 0 n
  | None -> ""

/// The blocks in a file's text, in order.
let blocks (text: string) : list<Block> =
  let lines = Array.ofList (String.split "\n" text)
  let found = Buffer.empty
  let mutable i = 0
  while i < Array.length lines do
    match docText lines.[i] with
    | Some t when String.trim t = "```zsharp" ->
      let start = i
      let code = Buffer.empty
      i <- i + 1
      while i < Array.length lines && Option.map String.trim (docText lines.[i]) <> Some "```" && Option.isSome (docText lines.[i]) do
        Buffer.push (Option.get (docText lines.[i])) code
        i <- i + 1
      // the declaration: the first line after the comment that isn't an attribute
      let mutable d = i
      while d < Array.length lines && (Option.isSome (docText lines.[d]) || String.startsWith "[<" (String.trim lines.[d]) || String.trim lines.[d] = "") do
        d <- d + 1
      let decl = if d < Array.length lines then declName lines.[d] else ""
      let codeLines = Array.toList (Buffer.toArray code)
      Buffer.push { line = start + 1; decl = decl; code = codeLines; expected = List.choose expectation codeLines } found
    | _ -> ()
    i <- i + 1
  Array.toList (Buffer.toArray found)

/// The program a block is: its code as main's body, after `open` of the documented module.
let program (opens: option<string>) (b: Block) : string =
  let header =
    match opens with
    | Some m -> $"open {m}\n\n"
    | None -> ""
  let body = String.join "\n" (List.map (fun (l: string) -> if l = "" then "" else "  " + l) b.code)
  $"{header}let main () =\n{body}\n  0\n"

/// A file's text with a block's `// =>` lines replaced by `printed`, where its first one was (or
/// before its closing fence), with the same comment prefix.
let update (text: string) (b: Block) (printed: list<string>) : string =
  let lines = String.split "\n" text
  // the block's lines: from its fence's next to its closing fence
  let inside (i: int) = i >= b.line && i < b.line + List.length b.code
  let prefixOf (line: string) =
    let at = Option.get (String.indexOf "///" line)
    String.sub line 0 at + "/// "
  let isExpectation (i: int) (line: string) = inside i && Option.isSome (Option.bind expectation (docText line))
  let first = List.tryFindIndex (fun (il: int * string) -> isExpectation (fst il) (snd il)) (List.indexed lines)
  let at = Option.defaultValue (b.line + List.length b.code) first
  let prefix = prefixOf (List.item (b.line - 1) lines)
  let fresh = List.map (fun (p: string) -> if p = "" then prefix + "// =>" else prefix + "// => " + p) printed
  let keep = List.indexed lines |> List.filter (fun (il: int * string) -> not (isExpectation (fst il) (snd il)))
  let before = List.map snd (List.filter (fun (il: int * string) -> fst il < at) keep)
  let after = List.map snd (List.filter (fun (il: int * string) -> fst il >= at) keep)
  String.join "\n" (List.concat [ before; fresh; after ])
