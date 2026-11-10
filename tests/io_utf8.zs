// Reader.readLine and readToEnd keep a character a read cut short for the next read, rather than
// make each of its bytes a U+FFFD: a file with an é across its 65,536th byte (where the reader's
// first read ends), and a pipe written in pieces that split characters
let fromFile (path: string) : result<unit, string> =
  let one = (File.openRead path)?
  use r = one
  let line = (Reader.readLine r)?
  let first = Option.defaultValue "" line
  println $"readLine: {String.length first} {String.endsWith "aé" first}"
  let two = (File.openRead path)?
  use all = two
  let text = (Reader.readToEnd all)?
  println $"readToEnd: {String.length text} {String.endsWith "aé\nnext\n" text}"
  Ok ()

let fromPipe () : result<string * string, string> =
  let script = "printf 'caf\\303'; sleep 1; printf '\\251\\nna\\303'; sleep 1; printf '\\257ve\\n'"
  let started = (Process.start { program = "sh"; args = [ "-c"; script ]; stdout = Piped })?
  use proc = started
  match proc.stdout with
  | Some r ->
    let line = (Reader.readLine r)?
    let rest = (Reader.readToEnd r)?
    Task.run (Process.wait proc) |> ignore
    Ok (Option.defaultValue "" line, String.trim rest)
  | None -> Error "no pipe"

let run () : result<unit, string> =
  let dir = (Directory.createTemp "zsutf8")?
  let path = Path.combine dir "long.txt"
  // 65,535 bytes of a, then the é
  let filler = String.repeat 4095 "aaaaaaaaaaaaaaaa" + "aaaaaaaaaaaaaaa"
  (File.writeAllText path (filler + "é\nnext\n"))?
  (fromFile path)?
  (Directory.deleteRecursive dir)?
  let read = (fromPipe ())?
  let (line, rest) = read
  println $"pipe: {line} {rest}"
  Ok ()

let main () =
  match run () with
  | Ok () -> 0
  | Error e ->
    println e
    1
