// String patterns: a string literal in a pattern matches the equal string
let command (line: string) =
  match String.split " " line with
  | [ "open"; file ] -> $"opening {file}"
  | [ "quit" ] | [ "exit" ] -> "bye"
  | verb :: _ -> $"unknown command: {verb}"
  | [] -> "empty"

let greet name =
  match name with
  | "" -> "nobody"
  | "Z#" -> "hello, language"
  | n -> $"hello, {n}"

let main () =
  println $"{command "open a.txt"} | {command "quit"} | {command "exit"} | {command "jump high"}"
  println $"{greet ""} | {greet "Z#"} | {greet "Ada"}"
  0
