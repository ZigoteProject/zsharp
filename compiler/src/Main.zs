// zs, the compiler in Z# (phase 11): the commands. For now the syntax half's: `tokens` and `tree`
// print a file's tokens and its syntax tree as the F# compiler's `zs tokens` and `zs tree` do, for
// comparing the two.
open Syntax
open Diag

let usage () =
  eprintln "usage: zs fmt [--check] <files…> | zs fmt --stdin | zs tokens <file.zs> | zs tree <file.zs>"
  2

// a diagnostic as the terminal shows it: where, what, and the line with a caret under the place
let printDiagnostic (src: Source.Source) (d: Diagnostic.Diagnostic) =
  Render.print (fun _ -> src) [| d |]

// zs check: a file's errors (its syntax's, for now), as zs build reports them
let check (path: string) : int =
  match File.readAllText path with
  | Error e ->
    eprintln e
    1
  | Ok text ->
    let src = Source.make 0 path text
    let (toks, lexed) = Report.collect (fun () -> Lexer.lex src)
    let (_, parsed) = Report.collect (fun () -> Parser.parse src toks)
    let diags = Array.append lexed parsed
    Render.print (fun _ -> src) diags
    if Array.length diags = 0 then 0 else 1

// zs fmt: files formatted in place (--check: the ones that aren't, listed), or standard input to
// standard output (--stdin); a file that doesn't parse is left alone, with its errors
let fmt (args: list<string>) : int =
  if List.contains "--stdin" args then
    let text =
      match Reader.readToEnd (Console.openStandardInput ()) with
      | Ok t -> t
      | Error _ -> ""
    let src = Source.make 0 "<stdin>" text
    let (result, diags) = Report.collect (fun () -> Format.format 0 "<stdin>" text)
    for d in diags do
      printDiagnostic src d
    match result with
    | Ok formatted ->
      print formatted
      0
    | Error why ->
      if why <> "" then
        eprintln $"<stdin>: {why}"
      1
  else
    let check = List.contains "--check" args
    let mutable status = 0
    for path in List.filter (fun (a: string) -> not (String.startsWith "--" a)) args do
      match File.readAllText path with
      | Error e ->
        eprintln e
        status <- 1
      | Ok text ->
        let src = Source.make 0 path text
        let (result, diags) = Report.collect (fun () -> Format.format 0 path text)
        for d in diags do
          printDiagnostic src d
        match result with
        | Ok formatted when formatted = src.text -> ()
        | Ok formatted ->
          if check then
            eprintln $"{path}: not formatted"
            status <- 1
          else
            match File.writeAllText path formatted with
            | Ok () -> ()
            | Error e ->
              eprintln e
              status <- 1
        | Error why ->
          if why <> "" then
            eprintln $"{path}: {why}"
          status <- 1
    status

// a file's text, its tokens and (for `tree`) its tree, printed as the F# compiler prints them;
// the errors on standard error
let syntax (command: string) (path: string) : int =
  match File.readAllText path with
  | Error e ->
    eprintln e
    1
  | Ok text ->
    let src = Source.make 0 path text
    let (toks, lexed) = Report.collect (fun () -> Lexer.lex src)
    let diags =
      if command = "tokens" then
        for t in toks do
          println (Token.display src.text t)
        lexed
      else
        let ((tree, _), parsed) = Report.collect (fun () -> Parser.parse src toks)
        Tree.print src.text tree
        Array.append lexed parsed
    for d in diags do
      printDiagnostic src d
    if Array.length diags = 0 then 0 else 1

// zs tree --check files…: each file's tree is lossless (tests/cst/roundtrip.sh); a file that
// doesn't parse only fails when its tree loses text
let treeCheck (paths: list<string>) : int =
  let mutable status = 0
  for path in paths do
    match File.readAllText path with
    | Error e ->
      eprintln e
      status <- 1
    | Ok text ->
      let src = Source.make 0 path (String.replace text "\r\n" "\n")
      let (toks, _) = Report.collect (fun () -> Lexer.lex src)
      let ((tree, _), _) = Report.collect (fun () -> Parser.parse src toks)
      if not (Tree.lossless tree) then
        eprintln $"{path}: the tree's text differs from the file"
        status <- 1
  status

// the milliseconds lexing and parsing files takes, the best of ten runs: against the F#
// compiler's `zs parse-time` (0020's criterion 2)
let parseTime (paths: list<string>) : int =
  let sources =
    paths
    |> List.choose (fun path ->
      match File.readAllText path with
      | Ok text -> Some(Source.make 0 path text)
      | Error _ -> None)
  let run () =
    for src in sources do
      let (toks, _) = Report.collect (fun () -> Lexer.lex src)
      Report.collect (fun () -> Parser.parse src toks) |> ignore
  run ()
  let mutable best = u64 0
  for i in 1 .. 10 do
    let sw = Diagnostics.Stopwatch.startNew ()
    run ()
    let t = sw.ElapsedNanoseconds
    if i = 1 || t < best then
      best <- t
  println $"{List.length sources} files, {float (int best) / 1000000.0:F1} ms"
  0

// the milliseconds checking a program takes, the library with it, the best of ten runs: against
// the F# compiler's `zs check-time` (0020's criterion 2, its second half)
let checkTime (path: string) : int =
  let run () = Build.Check.program path true true false true |> ignore
  run ()
  let mutable best = u64 0
  for i in 1 .. 10 do
    let sw = Diagnostics.Stopwatch.startNew ()
    run ()
    let t = sw.ElapsedNanoseconds
    if i = 1 || t < best then
      best <- t
  println $"{path}: {float (int best) / 1000000.0:F1} ms"
  0

// a command other than the build server's
let command (args: list<string>) : int =
  match args with
  | [ "tokens"; path ] -> syntax "tokens" path
  | "tree" :: "--check" :: paths -> treeCheck paths
  | [ "tree"; path ] -> syntax "tree" path
  | "parse-time" :: paths -> parseTime paths
  | [ "check-time"; path ] -> checkTime path
  | "fmt" :: args -> fmt args
  | [ "doc"; path ] -> Build.Doc.doc path
  // editors may add flags such as --stdio
  | "lsp" :: _ -> Lsp.Server.serve (Console.openStandardInput ()) None
  | "mcp" :: _ -> Lsp.Mcp.serve (Console.openStandardInput ()) None
  | [ "check"; path ] -> Build.Check.run path false
  | [ "check"; "--strict"; path ] -> Build.Check.run path true
  | "run" :: args -> Commands.run args
  | "test" :: args -> Commands.test args
  | [ "new"; name ] -> if Build.Project.newProject name then 0 else 1
  | [ "fetch" ] -> Commands.fetch false
  | [ "update" ] -> Commands.fetch true
  | [ "check-syntax"; path ] -> check path
  | [ "ast"; path ] ->
    match File.readAllText path with
    | Error e ->
      eprintln e
      1
    | Ok text ->
      let src = Source.make 0 path text
      let (toks, lexed) = Report.collect (fun () -> Lexer.lex src)
      let ((tree, decls), parsed) = Report.collect (fun () -> Parser.parse src toks)
      for l in AstDump.dump src tree.tokens decls do
        println l
      let diags = Array.append lexed parsed
      Render.print (fun _ -> src) diags
      if Array.length diags = 0 then 0 else 1
  | _ -> usage ()

extern isatty : i32 -> i32

// started by an editor with no arguments: an LSP message starts with a Content-Length header, an
// MCP message with '{'
let detect () : int =
  let input = Console.openStandardInput ()
  match IO.Reader.readLine input with
  | Ok(Some line) -> if String.startsWith "{" line then Lsp.Mcp.serve input (Some line) else Lsp.Server.serve input (Some line)
  | _ -> 2

// one command's work: as zs runs it, or as the build server does for a request (served)
let rec run (served: bool) (args: list<string>) : int =
  match args with
  | [] when isatty 0 = 0 -> detect ()
  | [ "server"; "stop" ] ->
    Server.viaServer [ "stop" ] |> ignore
    0
  | [ "server"; path ] -> Server.serve path (run true)
  | "build" :: rest ->
    if served || Option.isSome (Environment.getVariable "ZS_NO_SERVER") then
      Commands.build served rest
    else
      match Server.viaServer args with
      | Some code -> code
      | None -> Commands.build false rest
  | _ -> command args

let main () = run false (Environment.args ())
