// wc: lines, words and bytes of each file (or standard input); -l for lines only.
let report (linesOnly: bool) (text: string) (name: string) =
  if linesOnly then println $"{Text.lineCount text} {name}"
  else println $"{Text.lineCount text} {Text.wordCount text} {String.length text} {name}"

let main () =
  let args = Environment.args ()
  let linesOnly = List.contains "-l" args
  let files = List.filter (fun a -> a <> "-l") args
  let mutable status = 0
  if List.isEmpty files then
    report linesOnly (String.join "\n" (Console.readLines ()) + "\n") ""
  for f in files do
    match File.readAllText f with
    | Ok text -> report linesOnly text f
    | Error e ->
      eprintln $"wc: {e}"
      status <- 1
  status
