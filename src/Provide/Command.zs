/// zs provide (proposal 0001): a provider's module printed, to read or to keep in place of an
/// import: `zs provide json weather.json`, `zs provide csv stocks.csv --separator=;` and
/// `zs provide --list`. The providers are zs's own, json and csv, and run in this process; the
/// `import` form, the cache, the editor's side and providers on PATH follow.

/// zs's own providers: each by name, with what it does and the options it takes.
let private providers : list<string * string * list<string>> =
  [ ("json", "a document's records with the Json derive, from a sample", Provide.JsonProvider.options)
    ("csv", "a file's rows as a Row record, from the header and the rows", Provide.CsvProvider.options) ]

let private names () = String.join " and " (List.map (fun (n, _, _) -> n) providers)

/// The options after the file: each `--name=value` with a name the provider knows.
let private parseOptions (known: list<string>) (args: list<string>) : result<list<string * string>, string> =
  let rec go (args: list<string>) (acc: list<string * string>) =
    match args with
    | [] -> Ok(List.rev acc)
    | a :: rest ->
      let body = if String.startsWith "--" a then String.sub a 2 (String.length a - 2) else ""
      match String.indexOf "=" body with
      | None -> Error ("'" + a + "' isn't an option: --name=value, with name one of " + String.join ", " known)
      | Some i ->
        let name = String.sub body 0 i
        let value = String.sub body (i + 1) (String.length body - i - 1)
        if List.contains name known then go rest ((name, value) :: acc)
        else Error ("unknown option '" + name + "' (" + String.join ", " known + ")")
  go args []

/// The arguments after `provide`: `--list`, or a provider, its file and its options; the exit code.
let run (args: list<string>) : int =
  match args with
  | [ "--list" ] ->
    for (name, what, options) in providers do
      let listed = String.join ", " options
      println $"{name,-6} {what} (options: {listed})"
    0
  | name :: file :: opts ->
    match List.tryFind (fun (n, _, _) -> n = name) providers with
    | None ->
      eprintln ("no provider '" + name + "': zs has " + names ())
      1
    | Some(_, _, known) ->
      match parseOptions known opts with
      | Error e ->
        eprintln (name + ": " + e)
        1
      | Ok options ->
        match File.readAllText file with
        | Error e ->
          eprintln (name + ": " + e)
          1
        | Ok text ->
          let provided = if name = "json" then Provide.JsonProvider.provide file text options else Provide.CsvProvider.provide file text options
          match provided with
          | Ok text ->
            print text
            0
          | Error e ->
            eprintln (name + ": " + e)
            1
  | _ ->
    eprintln ("usage: zs provide <provider> <file> [--option=value]…, or zs provide --list; the providers are " + names ())
    2
