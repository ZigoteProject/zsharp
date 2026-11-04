// grep: the lines of files, or of standard input, that contain a text; with several files, each
// line with its file. -i ignores case, -n numbers the lines, -v keeps the lines without the text.
// Exit 0 when a line matched, 1 when none did, 2 for a usage error or a file that can't be read.
let usage () =
  Console.Error.writeLine "usage: grep [-i] [-n] [-v] <text> [files…]"
  2

let main () =
  let args = Environment.args ()
  let flags = List.filter (fun a -> String.startsWith "-" a) args
  match List.filter (fun a -> not (String.startsWith "-" a)) args with
  | [] -> usage ()
  | pattern :: files ->
    let ignoreCase = List.contains "-i" flags
    let numbered = List.contains "-n" flags
    let inverted = List.contains "-v" flags
    let needle = if ignoreCase then String.toLower pattern else pattern
    let matches (line: string) =
      String.contains needle (if ignoreCase then String.toLower line else line) <> inverted
    let found = ref 0
    let failed = ref false
    // a file's lines (or standard input's for "-"), each that matches printed
    let scan (name: string) (lines: list<string>) =
      let prefix = if List.length files > 1 then name + ":" else ""
      List.iteri (fun i line ->
        if matches line then
          found.Value <- found.Value + 1
          println (prefix + (if numbered then $"{i + 1}:" else "") + line)) lines
    match files with
    | [] -> scan "-" (Console.readLines ())
    | _ ->
      for f in files do
        match File.readAllLines f with
        | Ok lines -> scan f lines
        | Error e ->
          Console.Error.writeLine $"grep: {f}: {e}"
          failed.Value <- true
    if failed.Value then 2 else if found.Value > 0 then 0 else 1
