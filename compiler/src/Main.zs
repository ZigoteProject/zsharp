// zs, the compiler in Z# (phase 11): the commands. For now the syntax half's: `tokens` prints a
// file's tokens as the F# compiler's `zs tokens` does, for comparing the two lexers.
open Syntax
open Diag

let usage () =
  eprintln "usage: zs tokens <file.zs>"
  2

// a token as both compilers print it: its offset, its length and its text, or a layout
// token's name
let shown (src: string) (t: Token.Token) =
  match t.kind with
  | Token.Newline -> $"{t.offset} 0 <newline>"
  | Token.Indent -> $"{t.offset} 0 <indent>"
  | Token.Dedent -> $"{t.offset} 0 <dedent>"
  | Token.Eof -> $"{t.offset} 0 <eof>"
  | Token.Semi when t.length = 0 -> $"{t.offset} 0 <;>"
  | Token.Negate -> $"{t.offset} 1 ~-"
  | _ -> $"{t.offset} {t.length} {Token.text src t}"

let main () =
  match Environment.args () with
  | [ "tokens"; path ] ->
    match File.readAllText path with
    | Error e ->
      eprintln e
      1
    | Ok text ->
      let src = Source.make 0 path text
      let (toks, diags) = Report.collect (fun () -> Lexer.lex src)
      for t in toks do
        println (shown src.text t)
      for d in diags do
        let (line, col) = Source.position src d.at.offset
        eprintln $"{path}:{line}:{col}: error: {d.message}"
      if Array.length diags = 0 then 0 else 1
  | _ -> usage ()
