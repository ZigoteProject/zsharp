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
  let ns = "c" :: List.map (fun (n, _, _) -> n) providers
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

// how long a provider program may run, in seconds: $ZS_PROVIDER_TIMEOUT (a day at most), else a
// minute
let private limit () : int =
  match Environment.getVariable "ZS_PROVIDER_TIMEOUT" with
  | Some v ->
    let given : option<int> = Int.parse v
    match given with
    | Some n when n > 0 -> min n 86400
    | _ -> 60
  | None -> 60

// a provider program run in `dir` with the string and each option as --name=value: its standard
// output is the module, its standard error the errors (the first line named), a non-zero exit
// a failure. Both streams are read as they come (one that fills can't block it), and one that
// runs past the limit is stopped, so a provider can't hang a build or the language server.
let private runProvider (program: string) (dir: string) (arg: string) (opts: list<string * string>) : result<string, string> =
  let name = Path.getFileName program
  match Build.Tools.runFor program (arg :: List.map (fun (n, v) -> "--" + n + "=" + v) opts) (Some dir) (limit ()) with
  | Error e when String.startsWith "didn't finish" e -> Error $"{name} {e} (ZS_PROVIDER_TIMEOUT=<seconds> gives it longer)"
  | Error e -> Error $"{name}: {e}"
  | Ok r ->
    if r.code <> 0 then
      let lines = List.filter (fun (l: string) -> String.trim l <> "") (String.split "\n" r.err)
      Error(if List.isEmpty lines then $"{name} exited with {r.code}" else String.trim (List.head lines))
    else Ok r.out

// a provider on PATH, zs-provider-<name>; None when there's no such program
let private external (provider: string) (dir: string) (arg: string) (opts: list<string * string>) : option<result<string, string>> =
  if List.contains provider (onPath ()) then Some(runProvider ("zs-provider-" + provider) dir arg opts) else None

/// The module `provider` writes for `arg`, a file in `dir` (`where` names the place in an
/// error: "next to main.zs"), with `opts` checked against what it takes: zs's own providers run
/// here, else a program from `packaged` (the program's dependencies with a [provider] section,
/// each by name with its built program), else zs-provider-<name> on PATH. Error names an
/// unknown provider ("no provider …"), an unknown option, a file not found, or what the
/// provider found wrong.
let provide (provider: string) (dir: string) (where: string) (arg: string) (opts: list<string * string>) (packaged: list<string * string>) : result<string, string> =
  match List.tryFind (fun (n, _, _) -> n = provider) providers with
  | Some(_, _, known) ->
    match List.tryFind (fun (n, _) -> not (List.contains n known)) opts with
    | Some(n, _) -> Error ("unknown option '" + n + "' (" + String.join ", " known + ")")
    | None ->
      match Provide.Input.read (Path.combine dir arg) with
      | Error "not found" -> Error (arg + " not found " + where)
      | Error why -> Error (arg + " " + why)
      | Ok text ->
        match provider with
        | "json" -> Provide.JsonProvider.provide arg text opts
        | "csv" -> Provide.CsvProvider.provide arg text opts
        | "sql" -> Provide.SqlProvider.provide dir arg text opts
        | _ -> Provide.SvdProvider.provide arg text opts
  | None ->
    match List.tryFind (fun (n, _) -> n = provider) packaged with
    | Some(_, program) -> runProvider program dir arg opts
    | None ->
      match external provider dir arg opts with
      | Some r -> r
      | None -> Error ("no provider '" + provider + "': zs has " + names () + ", no zs-provider-" + provider + " is on PATH, and no dependency named " + provider + " has a [provider] section")

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
    println $"{"c",-6} a C header's declarations, as import c reads them (options: none; a package's include directories through import c)"
    for (name, what, options) in providers do
      let listed = String.join ", " options
      println $"{name,-6} {what} (options: {listed})"
    for name in onPath () do
      println $"{name,-6} zs-provider-{name}, on PATH"
    0
  | [ "c"; header ] ->
    // the header beside the working directory or on the system's path, with this machine's flags
    match Provide.CProvider.provide header (Environment.currentDirectory ()) [] (Path.combine ".zs-cache" "cimport") with
    | Ok text ->
      print text
      0
    | Error e ->
      eprintln e
      1
  | name :: file :: opts ->
    match parseOptions opts with
    | Error e ->
      eprintln (name + ": " + e)
      1
    | Ok options ->
      match provide name "." "here" file options [] with
      | Ok text ->
        print text
        0
      | Error e ->
        eprintln (if String.startsWith "no provider" e then e else name + ": " + e)
        1
  | _ ->
    eprintln ("usage: zs provide <provider> <file> [--option=value]…, or zs provide --list; the providers are " + names () + ", and any zs-provider-<name> on PATH")
    2
