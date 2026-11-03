/// zs provide (proposal 0001): a provider's module printed, to read or to keep in place of an
/// import: `zs provide json weather.json`, `zs provide csv stocks.csv --separator=;` and
/// `zs provide --list`. zs's own providers (json, csv, sql, svd) run in this process; a
/// `zs-provider-<name>` on PATH is a process, given the string and each option as `--name=value`,
/// whose standard output is the module.

/// zs's own providers: each by name, with what it does and the options it takes.
let private providers : list<string * string * list<string>> =
  [ ("json", "a document's records with the Json derive, from a sample", Provide.JsonProvider.options)
    ("csv", "a file's rows as a Row record, from the header and the rows", Provide.CsvProvider.options)
    ("sql", "a schema's tables as records, from its CREATE TABLEs", Provide.SqlProvider.options)
    ("svd", "a microcontroller's peripherals as modules of [<Bits>] registers, from its SVD file", Provide.SvdProvider.options) ]

let private names () =
  let ns = List.map (fun (n, _, _) -> n) providers
  String.join ", " (List.take (List.length ns - 1) ns) + " and " + List.last ns

/// The providers on PATH: each program named zs-provider-<name>, by its name.
let onPath () : list<string> =
  match Environment.getVariable "PATH" with
  | Some path ->
    let inDir (d: string) : list<string> =
      match Directory.list d with
      | Ok files -> List.choose (fun (f: string) -> if String.startsWith "zs-provider-" f then Some(String.sub f 12 (String.length f - 12)) else None) files
      | Error _ -> []
    List.distinct (List.collect inDir (List.filter (fun (d: string) -> d <> "") (String.split ":" path)))
  | None -> []

// a provider on PATH run in `dir` with the string and each option as --name=value: its standard
// output is the module, its standard error the errors (the first line named), a non-zero exit
// a failure; None when there's no such program
let private external (provider: string) (dir: string) (arg: string) (opts: list<string * string>) : option<result<string, string>> =
  let program = "zs-provider-" + provider
  if not (List.contains provider (onPath ())) then None
  else
    let s : Diagnostics.ProcessStart =
      { program = program
        args = arg :: List.map (fun (n, v) -> "--" + n + "=" + v) opts
        directory = Some dir
        stdin = Diagnostics.Null
        stdout = Diagnostics.Piped
        stderr = Diagnostics.Piped }
    match Diagnostics.Process.start s with
    | Error e -> Some(Error $"{program}: {e}")
    | Ok p ->
      let read (r: option<IO.Reader>) : string =
        match r with
        | Some reader ->
          match IO.Reader.readToEnd reader with
          | Ok t -> t
          | Error _ -> ""
        | None -> ""
      let out = read p.stdout
      let err = read p.stderr
      let code = Task.run (Diagnostics.Process.wait p)
      Dispose.dispose p
      if code <> 0 then
        let lines = List.filter (fun (l: string) -> String.trim l <> "") (String.split "\n" err)
        Some(Error(if List.isEmpty lines then $"{program} exited with {code}" else String.trim (List.head lines)))
      else Some(Ok out)

/// The module `provider` writes for `arg`, a file in `dir` (`where` names the place in an
/// error: "next to main.zs"), with `opts` checked against what it takes: zs's own providers run
/// here, else zs-provider-<name> on PATH. Error names an unknown provider ("no provider …"), an
/// unknown option, a file not found, or what the provider found wrong.
let provide (provider: string) (dir: string) (where: string) (arg: string) (opts: list<string * string>) : result<string, string> =
  match List.tryFind (fun (n, _, _) -> n = provider) providers with
  | Some(_, _, known) ->
    match List.tryFind (fun (n, _) -> not (List.contains n known)) opts with
    | Some(n, _) -> Error ("unknown option '" + n + "' (" + String.join ", " known + ")")
    | None ->
      match File.readAllText (Path.combine dir arg) with
      | Error _ -> Error (arg + " not found " + where)
      | Ok text ->
        match provider with
        | "json" -> Provide.JsonProvider.provide arg text opts
        | "csv" -> Provide.CsvProvider.provide arg text opts
        | "sql" -> Provide.SqlProvider.provide arg text opts
        | _ -> Provide.SvdProvider.provide arg text opts
  | None ->
    match external provider dir arg opts with
    | Some r -> r
    | None -> Error ("no provider '" + provider + "': zs has " + names () + ", and no zs-provider-" + provider + " is on PATH")

/// The options after the file: each `--name=value`.
let private parseOptions (args: list<string>) : result<list<string * string>, string> =
  let rec go (args: list<string>) (acc: list<string * string>) =
    match args with
    | [] -> Ok(List.rev acc)
    | a :: rest ->
      let body = if String.startsWith "--" a then String.sub a 2 (String.length a - 2) else ""
      match String.indexOf "=" body with
      | None -> Error ("'" + a + "' isn't an option: --name=value")
      | Some i -> go rest ((String.sub body 0 i, String.sub body (i + 1) (String.length body - i - 1)) :: acc)
  go args []

/// The arguments after `provide`: `--list`, or a provider, its file and its options; the exit code.
let run (args: list<string>) : int =
  match args with
  | [ "--list" ] ->
    for (name, what, options) in providers do
      let listed = String.join ", " options
      println $"{name,-6} {what} (options: {listed})"
    for name in onPath () do
      println $"{name,-6} zs-provider-{name}, on PATH"
    0
  | name :: file :: opts ->
    match parseOptions opts with
    | Error e ->
      eprintln (name + ": " + e)
      1
    | Ok options ->
      match provide name "." "here" file options with
      | Ok text ->
        print text
        0
      | Error e ->
        eprintln (if String.startsWith "no provider" e then e else name + ": " + e)
        1
  | _ ->
    eprintln ("usage: zs provide <provider> <file> [--option=value]…, or zs provide --list; the providers are " + names () + ", and any zs-provider-<name> on PATH")
    2
