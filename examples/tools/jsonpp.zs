// jsonpp: a JSON file, or standard input, printed indented; --compact prints it on one line.
// Exit 1 with the parse error, and where it is, when the text isn't JSON.
let main () =
  let args = Environment.args ()
  let compact = List.contains "--compact" args
  let text =
    match List.filter (fun a -> a <> "--compact") args with
    | file :: _ -> File.readAllText file
    | [] -> Ok(String.join "\n" (Console.readLines ()))
  match Result.bind Json.parse text with
  | Ok json ->
    println (if compact then Json.print json else Json.pretty json)
    0
  | Error e ->
    Console.Error.writeLine $"jsonpp: {e}"
    1
