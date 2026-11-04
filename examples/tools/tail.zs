// tail: the last lines of a file (10, or -n's count), and with -f the lines added to it after,
// as they come: the file is read again every 200 ms, and what's new since the lines shown is
// printed; a file rewritten shorter is printed from its start, and -f stops when the file is
// gone.
let usage () =
  Console.Error.writeLine "usage: tail [-n <count>] [-f] <file>"
  2

let rec parse (args: list<string>) (count: int) (follow: bool) : option<int * bool * string> =
  match args with
  | "-n" :: n :: rest ->
    match Int.parse n with
    | Some k when k >= 0 -> parse rest k follow
    | _ -> None
  | "-f" :: rest -> parse rest count true
  | [ file ] -> Some(count, follow, file)
  | _ -> None

let lastLines (count: int) (lines: list<string>) : list<string> =
  let n = List.length lines
  if n <= count then lines else List.skip (n - count) lines

let main () =
  match parse (Environment.args ()) 10 false with
  | None -> usage ()
  | Some(count, follow, file) ->
    match File.readAllLines file with
    | Error e ->
      Console.Error.writeLine $"tail: {file}: {e}"
      1
    | Ok lines ->
      for l in lastLines count lines do
        println l
      let mutable shown = List.length lines
      let mutable gone = false
      while follow && not gone do
        Task.run (Task.sleep 200)
        match File.readAllLines file with
        | Ok now ->
          let n = List.length now
          if n < shown then
            shown <- 0
          for l in List.skip shown now do
            println l
          shown <- n
        | Error _ ->
          Console.Error.writeLine $"tail: {file}: gone"
          gone <- true
      0
