module Main

open System
open System.Diagnostics
open System.Collections.Generic
open System.IO
open Syntax

open Driver

/// file:line:col: <word>: msg (error, warning or note), then the line with a caret under the
/// column.
let private printAt (word: string) (file: string) (line: int) (col: int) (msg: string) =
    if line > 0 && col > 0 then eprintfn "%s:%d:%d: %s: %s" file line col word msg
    elif line > 0 then eprintfn "%s:%d: %s: %s" file line word msg
    else eprintfn "%s: %s: %s" file word msg

    let text =
        try
            Some(readSource file)
        with _ ->
            None

    match text with
    | Some text when line > 0 ->
        let lines = text.Replace("\r\n", "\n").Split '\n'

        if line <= lines.Length then
            let src = lines[line - 1]
            let col = if col > 0 then col else src.Length - src.TrimStart().Length + 1
            let gutter = string line
            eprintfn " %s | %s" gutter src
            eprintfn " %s | %s^" (String.replicate gutter.Length " ") (String.replicate (col - 1) " ")
    | _ -> ()

let private printError (file: string) (line: int) (col: int) (msg: string) = printAt "error" file line col msg

/// An error, or a warning with its kind after the message (what [<NoWarn>] takes), then its notes.
let private printDiagnostic (d: Core.Diagnostic) =
    match d.severity with
    | Core.Severity.Error -> printError d.file d.line d.col d.msg
    | Core.Severity.Warning -> printAt "warning" d.file d.line d.col (sprintf "%s [%s]" d.msg d.name)

    for n in d.notes do
        printAt "note" n.nfile n.nline n.ncol n.ntext

/// --strict (0021): warnings fail the command, for CI and ./test.sh.
let mutable private strict = false

/// Prints a command's diagnostics and, when there's more than one, how many of each; false when
/// they fail it (an error, or a warning under --strict).
let private report (ds: Core.Diagnostic list) =
    for d in ds do
        printDiagnostic d

    let errors = ds |> List.filter Core.isError |> List.length
    let warnings = ds.Length - errors
    let count n (what: string) = if n = 1 then "1 " + what else sprintf "%d %ss" n what

    let counted =
        match errors, warnings with
        | 0, 0 -> ""
        | e, 0 -> if e > 1 then count e "error" else ""
        | 0, w -> if w > 1 then count w "warning" else ""
        | e, w -> count e "error" + ", " + count w "warning"

    if strict && warnings > 0 && errors = 0 then
        eprintfn "%s, %s under --strict" (count warnings "warning") (if warnings = 1 then "an error" else "errors")
    elif counted <> "" then
        eprintfn "%s" counted

    errors = 0 && not (strict && warnings > 0)

/// --sanitize, or --sanitize=thread for data races
let private sanitizing (args: string list) =
    Driver.threadSanitizer <- List.contains "--sanitize=thread" args
    List.contains "--sanitize" args || Driver.threadSanitizer

/// .zs -> LLVM IR -> clang (with the runtime) -> native executable, or with isLib a static
/// library (.a) plus its header (.h). Returns false on any error.
/// Builds and prints its warnings or errors; true on success.
let private build (src: string) (out: string) (emitLlvm: bool) (sanitize: bool) (isLib: bool) =
    match Driver.build src out emitLlvm sanitize isLib with
    | Ok warnings -> report warnings
    | Error errors -> report errors && false

/// The project around the current directory, or an error message.
let private project () =
    try
        match findProject Environment.CurrentDirectory with
        | Some m -> Ok m
        | None -> Error "no file given and no zs.toml here or above (zs new <name> creates a project)"
    with CompileErrorAt(file, line, col, msg) ->
        printError file line col msg
        Error "invalid zs.toml"

let private isFile (a: string) = a.EndsWith ".zs"

/// Fetches the git dependencies of the project around `dir` (if any) before a build; false on
/// failure, with the reasons printed.
let private fetched (dir: string) =
    try
        match findProject dir with
        | Some m ->
            let errors = fetchDeps m false

            for e in errors do
                eprintfn "zs: %s" e

            errors.IsEmpty
        | None -> true
    with CompileErrorAt(file, line, col, msg) ->
        printError file line col msg
        false

let private dirOf (src: string) = Path.GetDirectoryName(Path.GetFullPath src)

/// A test of a built test binary (0009): its path, focus, time limit and sequenced group.
type private Leaf =
    { path: string
      focus: string
      timeout: int
      sequence: string }

/// Runs a test binary on one test, killed after its time limit: the exit code (None when it
/// timed out), its output (standard output, then standard error) and how long it took.
let private runLeaf (exe: string) (l: Leaf) : int option * string * float =
    let psi = ProcessStartInfo exe
    psi.ArgumentList.Add l.path
    psi.RedirectStandardOutput <- true
    psi.RedirectStandardError <- true
    psi.RedirectStandardInput <- true
    let sw = Stopwatch.StartNew()
    use p = Process.Start psi
    p.StandardInput.Close()
    let out = p.StandardOutput.ReadToEndAsync()
    let err = p.StandardError.ReadToEndAsync()

    if p.WaitForExit l.timeout then
        p.WaitForExit()
        Some p.ExitCode, out.Result + err.Result, sw.Elapsed.TotalSeconds
    else
        (try p.Kill true with _ -> ())
        p.WaitForExit()
        None, out.Result + err.Result, sw.Elapsed.TotalSeconds

// what expectAt prints for zs test --update: the place, the text, an end line (Testing.zs)
let private expectRecord = Text.RegularExpressions.Regex(@"zs-expect ([^\n]*):(\d+)\n((?:.|\n)*?)\nzs-expect-end\n?")

/// Rewrites an expect test's literal (the last argument of the `expect` on that line) to the
/// text, through the lossless tree: a plain string when it fits on its line, else a raw string
/// on lines of its own.
let private updateExpect (file: string) (line: int) (text: string) =
    let source = File.ReadAllText file
    let toks = lex source

    match toks |> Array.tryFindIndex (fun t -> t.line = line && (t.tok = KId "expect" || t.tok = KId "Testing.expect")) with
    | None -> false
    | Some i ->
        // the call's literal: the first string token after the value at the call's depth
        let rec find (j: int) (depth: int) (seen: bool) =
            if j >= toks.Length then None
            else
                match toks[j].tok with
                | KSym("(" | "[" | "[|" | "{") -> find (j + 1) (depth + 1) true
                | KSym(")" | "]" | "|]" | "}") -> find (j + 1) (depth - 1) true
                | KStr _ when depth = 0 && seen -> Some toks[j]
                | KNewline | KEof when depth = 0 -> None
                | _ -> find (j + 1) depth true

        match find (i + 1) 0 false with
        | None -> false
        | Some lit ->
            let indent = String(' ', toks[i].col - 1 + 2)

            let literal =
                if not (text.Contains '\n' || text.Contains '"' || text.Contains '\\') then "\"" + text + "\""
                else "\"\"\"\n" + (text.Split '\n' |> Array.map (fun l -> if l = "" then l else indent + l) |> String.concat "\n") + "\n" + indent + "\"\"\""

            File.WriteAllText(file, source.Substring(0, lit.offset) + literal + source.Substring(lit.offset + lit.text.Length))
            true

/// A run's last line: "3 passed, 1 failed, 2 skipped".
let private summaryLine (passed: int) (failed: int) (skipped: int) (broken: int) =
    sprintf "%d passed, %d failed%s%s" passed failed (if skipped > 0 then sprintf ", %d skipped" skipped else "") (if broken > 0 then sprintf ", %d file(s) didn't build" broken else "")

/// Builds a file's [<Tests>] values and runs each test in its own process (0009), at once up to
/// the number of cores, a sequenced group's tests one at a time, each within its time limit.
/// args: filters (a path ending in / is a prefix; else a part of the path), --summary,
/// --fail-on-focused, --update. Returns (passed, failed, skipped), or None when it didn't build.
let private runTests (src: string) (args: string list) =
    let filters = args |> List.filter (fun a -> not (a.StartsWith "--"))

    let names =
        try
            (Driver.checkProgram false src false false).tests
        with CompileErrorAt(file, line, col, msg) ->
            printError file line col msg
            []

    let exe = Path.Combine(Path.GetTempPath(), "zs-test-" + Guid.NewGuid().ToString("N"))
    testBuild <- true

    if names.IsEmpty then
        eprintfn "%s: no [<Tests>] values" src
        Some(0, 0, 0)
    elif not (build src exe false false false) then
        None
    else
        Environment.SetEnvironmentVariable("ZS_BACKTRACE", "0")
        let _, listed = exec exe [ "--list" ] true

        let leaves =
            [ for line in listed.Split('\n', StringSplitOptions.RemoveEmptyEntries) do
                  match line.Split '\t' with
                  | [| p; f; t; s |] ->
                      yield
                          { path = p
                            focus = f
                            timeout = int t
                            sequence = s }
                  | _ -> () ]

        let wanted (l: Leaf) =
            filters.IsEmpty || filters |> List.exists (fun f -> if f.EndsWith "/" then l.path.StartsWith f else l.path.Contains f)

        let chosen = leaves |> List.filter wanted

        if chosen.IsEmpty then
            printfn "no test's path matches %s (they start with %s)" (String.concat " " filters) (leaves |> List.map (fun l -> l.path.Split('/')[0] + "/") |> List.distinct |> String.concat ", ")
        let focused = chosen |> List.exists (fun l -> l.focus = "focused")
        let runs (l: Leaf) = l.focus <> "pending" && (not focused || l.focus = "focused")
        let results = Collections.Concurrent.ConcurrentDictionary<string, int option * string * float>()

        // a sequenced group's tests one after another, each other test on its own
        let groups =
            chosen
            |> List.filter runs
            |> List.groupBy (fun l -> if l.sequence = "" then "\u0000" + l.path else l.sequence)
            |> List.map snd

        Threading.Tasks.Parallel.ForEach(
            groups,
            Threading.Tasks.ParallelOptions(MaxDegreeOfParallelism = Environment.ProcessorCount),
            fun (g: Leaf list) ->
                for l in g do
                    results[l.path] <- runLeaf exe l
        )
        |> ignore

        let mutable failed = 0
        let mutable skipped = 0
        let updates = ResizeArray<string * int * string>()

        for l in chosen do
            match results.TryGetValue l.path with
            | true, (Some 0, _, _) -> printfn "ok   %s" l.path
            | true, (code, output, _) ->
                failed <- failed + 1
                printfn "FAIL %s" l.path

                for m in expectRecord.Matches output do
                    updates.Add(m.Groups[1].Value, int m.Groups[2].Value, m.Groups[3].Value)

                let output = expectRecord.Replace(output, "").Trim()

                for line in output.Split '\n' do
                    if line <> "" then printfn "       %s" line

                if code.IsNone then
                    printfn "       timed out after %g s" (float l.timeout / 1000.0)
            | _ ->
                skipped <- skipped + 1
                printfn "skip %s%s" l.path (if l.focus = "pending" then " (pending)" else "")

        if List.contains "--update" args then
            for file, line, text in updates do
                let path = Path.Combine(dirOf src, file)

                if File.Exists path && updateExpect path line text then
                    printfn "updated %s:%d" file line

        if List.contains "--summary" args then
            printfn "times:"

            for path, (_, _, secs) in results |> Seq.map (fun kv -> kv.Key, kv.Value) |> Seq.sortByDescending (fun (_, (_, _, s)) -> s) do
                printfn "  %8.3f s  %s" secs path

        File.Delete exe

        if focused && List.contains "--fail-on-focused" args then
            printfn "focused tests are left (--fail-on-focused)"
            failed <- failed + 1

        let passed = results.Values |> Seq.filter (fun (code, _, _) -> code = Some 0) |> Seq.length
        Some(passed, failed, skipped)

let private newProject (name: string) =
    if Directory.Exists name then
        eprintfn "%s already exists" name
        1
    else
        Directory.CreateDirectory(Path.Combine(name, "src")) |> ignore
        File.WriteAllText(Path.Combine(name, "zs.toml"), sprintf "[package]\nname = \"%s\"\nversion = \"0.1.0\"\nmain = \"src/main.zs\"\n\n[dependencies]\n# text = { path = \"../text\" }\n" (Path.GetFileName(Path.GetFullPath name)))

        File.WriteAllText(
            Path.Combine(name, "src", "main.zs"),
            "open Testing\n\nlet greeting (who: string) = $\"Hello, {who}!\"\n\nlet main () =\n  match Environment.args () with\n  | [] -> println (greeting \"world\")\n  | who :: _ -> println (greeting who)\n  0\n\n[<Tests>]\nlet tests = testList \"greeting\" [ test \"greets\" (fun () -> assert (greeting \"Z#\" = \"Hello, Z#!\")) ]\n"
        )

        File.WriteAllText(Path.Combine(name, ".gitignore"), "build/\n")
        printfn "created %s: zs.toml, src/main.zs (cd %s && zs run)" name name
        0

/// Whether this process is the build server (zs build --time says so).
let mutable private served = false

/// One command's work, as zs runs it: from the defaults, so a build server (serve) can run
/// many in a row.
let private run (argv: string[]) =
    Driver.release <- false
    Driver.optAsked <- None
    Driver.profileGenerate <- false
    Driver.profileUse <- None
    Driver.cpu <- None
    Driver.mcu <- None
    Driver.testBuild <- false
    Driver.threadSanitizer <- false
    Codegen.optimizeSize <- false
    Codegen.target <- ""
    Codegen.debugInfo <- Array.contains "-g" argv

    if Array.contains "-Os" argv then
        Driver.optAsked <- Some "-Os"
        Codegen.optimizeSize <- true

    // -O0 … -O3: clang's optimization level, in place of the build's (-O0 for a debug build,
    // -O2 for --release)
    for o in [ "-O0"; "-O1"; "-O2"; "-O3" ] do
        if Array.contains o argv then
            Driver.optAsked <- Some o

    // --release: optimized, with ThinLTO; profiles are for release builds
    Driver.release <- Array.contains "--release" argv || Array.contains "--profile-generate" argv || Array.contains "--profile-use" argv
    strict <- Array.contains "--strict" argv
    let argv = argv |> Array.filter ((<>) "--strict")

    let argv = argv |> Array.filter (fun a -> not (List.contains a [ "-Os"; "-O0"; "-O1"; "-O2"; "-O3"; "--release" ]))

    // --profile-generate, --profile-use <file>: profile-guided optimization, taken out of the
    // arguments
    if Array.contains "--profile-generate" argv then
        Driver.profileGenerate <- true

    let argv = argv |> Array.filter ((<>) "--profile-generate")

    let argv =
        match Array.tryFindIndex ((=) "--profile-use") argv with
        | Some i when i + 1 < argv.Length ->
            Driver.profileUse <- Some argv[i + 1]
            Array.append argv[.. i - 1] argv[i + 2 ..]
        | _ -> argv

    // --cpu <name> or --cpu=<name> (native, x86-64-v3, neoverse-n1, …): the processor to
    // compile for, taken out of the arguments
    let argv =
        match Array.tryFindIndex (fun (a: string) -> a = "--cpu" || a.StartsWith "--cpu=") argv with
        | Some i when argv[i].StartsWith "--cpu=" ->
            Driver.cpu <- Some(argv[i].Substring 6)
            Array.append argv[.. i - 1] argv[i + 1 ..]
        | Some i when i + 1 < argv.Length ->
            Driver.cpu <- Some argv[i + 1]
            Array.append argv[.. i - 1] argv[i + 2 ..]
        | _ -> argv

    // --target <triple> (e.g. aarch64-linux-musl): a cross build, taken out of the arguments
    let argv =
        match Array.tryFindIndex ((=) "--target") argv with
        | Some i when i + 1 < argv.Length ->
            // a chip name selects the bare-metal runtime; Codegen sees its triple
            match mcus.TryGetValue argv[i + 1] with
            | true, m ->
                mcu <- Some m
                Codegen.target <- m.triple
            | _ -> Codegen.target <- argv[i + 1]

            Array.append argv[.. i - 1] argv[i + 2 ..]
        | _ -> argv

    match List.ofArray argv |> List.filter ((<>) "-g") with
    | "build" :: rest when not (List.exists isFile rest) ->
        // the project: its main, built as build/<name>
        match project () with
        | Error msg ->
            eprintfn "zs: %s" msg
            1
        | Ok m when not (fetched m.root) -> 1
        | Ok m ->
            let out = Path.Combine(m.root, "build", m.name)
            Directory.CreateDirectory(Path.GetDirectoryName out) |> ignore
            let ok = build m.main out (List.contains "--emit-llvm" rest) (sanitizing rest) false

            if ok then
                printfn "built %s" (Path.GetRelativePath(Environment.CurrentDirectory, out))

            if ok then 0 else 1
    | "run" :: rest when not (List.exists isFile rest) ->
        // the project's program, with the arguments
        match project () with
        | Error msg ->
            eprintfn "zs: %s" msg
            1
        | Ok m when not (fetched m.root) -> 1
        | Ok m ->
            let exe = Path.Combine(Path.GetTempPath(), "zs-" + Guid.NewGuid().ToString("N"))

            let args =
                match rest with
                | "--" :: args -> args
                | args -> args

            if build m.main exe false false false then
                let code, _ = exec exe args false
                File.Delete exe
                code
            else
                1
    | "test" :: filter when not (List.exists isFile filter) ->
        // every .zs file under the project's src/ and tests/ that has tests
        match project () with
        | Error msg ->
            eprintfn "zs: %s" msg
            1
        | Ok m when not (fetched m.root) -> 1
        | Ok m ->
            let files =
                [ "src"; "tests" ]
                |> List.map (fun d -> Path.Combine(m.root, d))
                |> List.filter Directory.Exists
                |> List.collect (fun d -> Directory.GetFiles(d, "*.zs", SearchOption.AllDirectories) |> List.ofArray |> List.sort)
                |> List.filter (fun f -> (File.ReadAllText f).Contains "[<Tests>]")

            let results =
                files
                |> List.map (fun f ->
                    printfn "%s" (Path.GetRelativePath(Environment.CurrentDirectory, f))
                    runTests f filter)

            let passed = results |> List.sumBy (function Some(p, _, _) -> p | None -> 0)
            let failed = results |> List.sumBy (function Some(_, f, _) -> f | None -> 0)
            let skipped = results |> List.sumBy (function Some(_, _, s) -> s | None -> 0)
            let broken = results |> List.filter Option.isNone |> List.length
            printfn "%s" (summaryLine passed failed skipped broken)
            if failed = 0 && broken = 0 then 0 else 1
    | [ "new"; name ] -> newProject name
    | [ ("fetch" | "update") as cmd ] ->
        // fetch: check out git dependencies at their locked commits; update: move them to the
        // newest commit of their rev, and rewrite zs.lock
        match project () with
        | Error msg ->
            eprintfn "zs: %s" msg
            1
        | Ok m ->
            let errors = fetchDeps m (cmd = "update")

            for e in errors do
                eprintfn "zs: %s" e

            if errors.IsEmpty then 0 else 1
    | ("build" | "run" | "check" | "test") :: src :: _ when isFile src && not (fetched (dirOf src)) -> 1
    | "build" :: src :: rest ->
        let out =
            match List.tryFindIndex ((=) "-o") rest with
            | Some i when i + 1 < rest.Length -> rest[i + 1]
            | _ -> Path.GetFileNameWithoutExtension src

        let isLib = List.contains "--lib" rest
        let ok = build src out (List.contains "--emit-llvm" rest) (sanitizing rest) isLib

        if List.contains "--time" rest then
            for phase, ms in timings do
                eprintfn "%-20s %8.1f ms" phase ms

            eprintfn "%-20s %8.1f ms" (if served then "total (build server)" else "total") (Seq.sumBy snd timings)

        if ok then 0 else 1
    | [ "check"; src ] ->
        // type-check only: every error, nothing built
        try
            let prog = Driver.checkProgram false src true true
            if report prog.diagnostics then 0 else 1
        with CompileErrorAt(file, line, col, msg) ->
            printError file line col msg
            1
    | "tree" :: rest ->
        // zs tree file: the syntax tree (0019), for debugging; --check files…: each one's tree
        // gives back its text byte for byte (tests/cst/roundtrip.sh)
        let check = List.contains "--check" rest
        let mutable status = 0

        for f in rest |> List.filter (fun a -> not (a.StartsWith "--")) do
            try
                let src = (File.ReadAllText f).Replace("\r\n", "\n")
                let _, tree = Syntax.parseWithTree (Syntax.lex src)

                if check then
                    if Syntax.treeText tree <> src then
                        eprintfn "%s: the tree's text differs from the file" f
                        status <- 1
                else
                    let rec dump (indent: string) (n: Syntax.Node) =
                        printfn "%s%s" indent n.kind

                        for c in n.children do
                            match c with
                            | Syntax.N m -> dump (indent + "  ") m
                            | Syntax.T t -> printfn "%s  %s" indent (if t.text = "" then sprintf "<%A>" t.tok else sprintf "%A" t.text)

                    dump "" tree
            with
            // a file that doesn't parse has no tree yet (until 0019's recovery): only a tree
            // that loses text fails the check
            | CompileError(l, m) ->
                printError f l 0 m
                status <- if check then status else 1
            | CompileErrorPos(l, c, m) ->
                printError f l c m
                status <- if check then status else 1

        status
    | "fmt" :: rest when List.contains "--stdin" rest ->
        // zs fmt --stdin: standard input formatted to standard output, for editors and git filters;
        // on an error, nothing on standard output (a pipe mustn't empty a buffer) and exit 1
        let src = Console.In.ReadToEnd()

        try
            match Format.format src with
            | Ok formatted ->
                Console.Out.Write formatted
                0
            | Error msg ->
                eprintfn "<stdin>: %s" msg
                1
        with
        | CompileError(l, m) ->
            printError "<stdin>" l 0 m
            1
        | CompileErrorPos(l, c, m) ->
            printError "<stdin>" l c m
            1
    | "fmt" :: rest ->
        // zs fmt files… rewrites them; --check lists the ones that aren't formatted
        let check = List.contains "--check" rest
        let files = rest |> List.filter (fun a -> not (a.StartsWith "--"))
        let mutable status = 0

        for f in files do
            try
                let src = File.ReadAllText f

                match Format.format src with
                | Ok formatted when formatted = src.Replace("\r\n", "\n") -> ()
                | Ok formatted ->
                    if check then
                        eprintfn "%s: not formatted" f
                        status <- 1
                    else
                        File.WriteAllText(f, formatted)
                | Error msg ->
                    eprintfn "%s: %s" f msg
                    status <- 1
            with
            | CompileError(l, m) ->
                printError f l 0 m
                status <- 1
            | CompileErrorPos(l, c, m) ->
                printError f l c m
                status <- 1

        status
    | [ "doc"; src ] ->
        // a Markdown reference: every documented item, with inferred types for functions
        try
            let prog = check src false true
            let full = Path.GetFullPath src

            let signatures =
                prog.hovers
                |> List.filter (fun h -> h.decl)
                |> List.map (fun h ->
                    let needs = if h.constraints = "" then "" else " when " + h.constraints
                    let words = if h.explain = "" then "" else "\n  " + h.explain
                    h.name, sprintf "%s : %s%s%s" (Core.shortName h.name) (Core.show h.hty) needs words)
                |> dict

            let stem = Path.GetFileNameWithoutExtension full
            let header = docItems src |> List.tryFind (fun d -> d.kind = "module" || d.kind = "namespace")

            // the page's module: a namespace file holds the one named after the file
            let moduleName =
                match header with
                | Some h when h.kind = "namespace" -> Some(h.key + "." + stem)
                | Some h -> Some h.key
                | None -> None

            // functions built into the compiler that belong to this module (the prelude's: the
            // global ones), after the file's own
            let builtins =
                [ for KeyValue(name, doc) in builtinDocs do
                      let inModule =
                          match moduleName with
                          | Some m -> name.StartsWith(m + ".") && not (name.Substring(m.Length + 1).Contains ".")
                          | None -> stem = "prelude" && not (name.Contains ".")

                      match Typer.builtinType name with
                      | Some t when inModule ->
                          yield
                              { kind = "function"
                                key = name
                                title = ""
                                line = 0
                                doc = Some doc },
                              sprintf "%s : %s%s" (Core.shortName name) (Core.show t) (match Core.explain [] t with
                                                                                       | "" -> ""
                                                                                       | w -> "\n  " + w)
                      | _ -> () ]

            let signatures = Dictionary<string, string>(signatures)

            for d, s in builtins do
                signatures[d.key] <- s

            let items = docItems src @ (builtins |> List.map fst |> List.sortBy (fun d -> d.key))

            let section (title: string) (kinds: string list) =
                let chosen = items |> List.filter (fun d -> List.contains d.kind kinds)

                if not chosen.IsEmpty then
                    printfn "## %s\n" title

                    for d in chosen do
                        let shown =
                            match d.kind with
                            | "function" when signatures.ContainsKey d.key -> signatures[d.key]
                            | _ -> d.title

                        let heading = if List.contains d.kind [ "case"; "method"; "member"; "operation" ] then "####" else "###"
                        printfn "%s `%s`\n\n```zsharp\n%s\n```\n" heading (Core.shortName d.key) shown

                        match d.doc with
                        | Some doc -> printfn "%s\n" doc
                        | None -> printfn "_Undocumented._\n"

            // the page is the file's module, with the doc comment above its header
            printfn "# %s\n" (defaultArg moduleName stem)
            header |> Option.bind (fun h -> h.doc) |> Option.iter (printfn "%s\n")

            section "Traits" [ "trait"; "method" ]
            section "Effects" [ "effect"; "operation" ]
            section "Types" [ "type"; "case"; "member" ]
            section "Derives and impls" [ "derive"; "impl" ]
            section "Functions" [ "function" ]
            0
        with CompileErrorAt(file, line, col, msg) ->
            printError file line col msg
            1
    | "test" :: src :: filter ->
        match runTests src filter with
        | None -> 1
        | Some(0, 0, 0) -> 1
        | Some(passed, failed, skipped) ->
            printfn "%s" (summaryLine passed failed skipped 0)
            if failed = 0 then 0 else 1
    | "lsp" :: _ -> Lsp.serve () // editors may add flags such as --stdio
    | "mcp" :: _ -> Mcp.serve ()
    | "run" :: src :: rest ->
        // zs run file.zs [--sanitize] [-- program arguments]
        let exe = Path.Combine(Path.GetTempPath(), "zs-" + Guid.NewGuid().ToString("N"))

        let args =
            match List.tryFindIndex ((=) "--") rest with
            | Some i -> rest[i + 1 ..]
            | None -> []

        if build src exe false (sanitizing rest) false then
            let code, _ = exec exe args false
            File.Delete exe
            code
        else
            1
    | [] when Console.IsInputRedirected ->
        // started by an editor without arguments: an LSP message starts with a
        // Content-Length header, an MCP message with '{'
        let stdin = Console.OpenStandardInput()
        let first = stdin.ReadByte()

        if first < 0 then
            2
        else
            Rpc.input <- new Rpc.PrefixedStream([| byte first |], stdin)
            if char first = '{' then Mcp.serve () else Lsp.serve ()
    | _ ->
        eprintfn "usage: zs new <name>\n       zs fetch | zs update\n       zs build [<file.zs> [-o <out>] [--lib]] [--release] [-g] [-O0|-O1|-O2|-O3|-Os] [--target <triple>] [--emit-llvm] [--sanitize[=thread]] [--cpu <name>] [--profile-generate | --profile-use <file>] [--time]\n       zs run [<file.zs> [--release] [-g] [--sanitize[=thread]] --] [program arguments…]\n       zs check <file.zs>\n       zs test [<file.zs>] [path/ | name…] [--summary] [--update] [--fail-on-focused]\n       zs doc <file.zs>\n       zs fmt [--check] <files…>\n       zs lsp\n       zs mcp"
        2

/// The build server: zs build asks it to build (one build at a time, in the request's
/// directory, its output sent back), so a rebuild finds the compiler started and warm: its
/// code compiled, the library's results and the program's in memory. It ends after ten idle
/// minutes, or when asked to (zs server stop). A request is the directory and the arguments,
/// a reply the exit code and the output, each NUL-separated UTF-8 read to the end.
let private unixSocket () =
    new Net.Sockets.Socket(Net.Sockets.AddressFamily.Unix, Net.Sockets.SocketType.Stream, Net.Sockets.ProtocolType.Unspecified)

let private readAll (socket: Net.Sockets.Socket) =
    use mem = new MemoryStream()
    let buf = Array.zeroCreate<byte> 65536
    let mutable n = socket.Receive buf

    while n > 0 do
        mem.Write(buf, 0, n)
        n <- socket.Receive buf

    Text.Encoding.UTF8.GetString(mem.ToArray()).Split '\000'

let private sendAll (socket: Net.Sockets.Socket) (fields: string list) =
    socket.Send(Text.Encoding.UTF8.GetBytes(String.concat "\000" fields)) |> ignore
    socket.Shutdown Net.Sockets.SocketShutdown.Send

let rec private serve (path: string) =
    served <- true
    Directory.CreateDirectory(Path.GetDirectoryName path) |> ignore

    // another server started first (two builds found none): it answers, this one ends
    let answered =
        try
            use probe = unixSocket ()
            probe.Connect(Net.Sockets.UnixDomainSocketEndPoint path)
            sendAll probe [ ""; "ping" ]
            true
        with _ -> false

    if not answered then
        if File.Exists path then
            File.Delete path // a server that ended without removing it: nothing answers there

        serveAt path

and private serveAt (path: string) =
    use listener = unixSocket ()
    listener.Bind(Net.Sockets.UnixDomainSocketEndPoint path)
    listener.Listen 16
    let mutable go = true

    while go && listener.Poll(600_000_000, Net.Sockets.SelectMode.SelectRead) do
        try
            use conn = listener.Accept()

            match List.ofArray (readAll conn) with
            | [ _; "stop" ] -> go <- false
            | [ _; "ping" ] -> ()
            | cwd :: argv ->
                let out, err = new StringWriter(), new StringWriter()
                let stdout, stderr = Console.Out, Console.Error
                Console.SetOut out
                Console.SetError err
                Environment.CurrentDirectory <- cwd

                let code =
                    try
                        try
                            run (Array.ofList argv)
                        with e ->
                            eprintfn "zs: %s" (string e)
                            70
                    finally
                        Console.SetOut stdout
                        Console.SetError stderr

                sendAll conn [ string code; string out; string err ]
            | [] -> ()
        with _ -> () // a client that went away

    try File.Delete path with _ -> ()

/// Sends a command to the build server; None when there's none (one is started for the next).
let private viaServer (argv: string[]) : int option =
    let path = serverSocket ()

    try
        use socket = unixSocket ()
        socket.Connect(Net.Sockets.UnixDomainSocketEndPoint path)
        sendAll socket (Environment.CurrentDirectory :: List.ofArray argv)

        match readAll socket with
        | [| code; out; err |] ->
            Console.Out.Write out
            Console.Error.Write err
            Some(int code)
        | _ -> None
    with _ ->
        if argv <> [| "stop" |] then
            // started apart from this process (its own pipes, so a caller reading this one's
            // output isn't kept waiting), with this environment
            try
                let info = ProcessStartInfo(Environment.ProcessPath, [ "server"; path ])
                info.RedirectStandardInput <- true
                info.RedirectStandardOutput <- true
                info.RedirectStandardError <- true
                Process.Start info |> ignore
            with _ -> ()

        None

[<EntryPoint>]
let main argv =
    match List.ofArray argv with
    | [ "server"; "stop" ] -> viaServer [| "stop" |] |> ignore; 0
    | [ "server"; path ] -> serve path; 0
    | "build" :: _ when isNull (Environment.GetEnvironmentVariable "ZS_NO_SERVER") ->
        match viaServer argv with
        | Some code -> code
        | None -> run argv
    | _ -> run argv
