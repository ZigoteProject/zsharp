// The shout provider: a word per line in the file, each a constant with the word in capitals,
// named with --prefix= in front. Run by the compiler in the importing file's directory with the
// import's string and options; the module on standard output, errors on standard error.
let main () =
  match Environment.args () with
  | [] ->
    eprintln "usage: zs-provider-shout <file> [--prefix=<name>]"
    2
  | file :: opts ->
    let prefix = ref ""
    let bad = ref None
    for o in opts do
      if String.startsWith "--prefix=" o then prefix.Value <- String.sub o 9 (String.length o - 9)
      else bad.Value <- Some o
    match bad.Value with
    | Some o ->
      eprintln $"unknown option '{o}' (prefix)"
      1
    | None ->
      match File.readAllText file with
      | Error _ ->
        eprintln $"{file} not found"
        1
      | Ok text ->
        println $"// provided by shout 0.1 from {file}"
        println $"// input: {file}"
        println ""
        for w in List.filter (fun (l: string) -> l <> "") (List.map String.trim (String.split "\n" text)) do
          println $"let {prefix.Value}{w} = \"{String.toUpper w}\""
        0
