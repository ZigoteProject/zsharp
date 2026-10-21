module Main

open System
open System.Diagnostics
open System.Collections.Generic
open System.IO
open Syntax

open Driver

/// file:line:col: error: msg, then the line with a caret under the column.
let private printError (file: string) (line: int) (col: int) (msg: string) =
    if line > 0 && col > 0 then eprintfn "%s:%d:%d: error: %s" file line col msg
    elif line > 0 then eprintfn "%s:%d: error: %s" file line msg
    else eprintfn "%s: error: %s" file msg

    let text =
        try
            if file = "prelude.zs" then None else Some(readSource file)
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

/// .zs -> LLVM IR -> clang (with the runtime) -> native executable, or with isLib a static
/// library (.a) plus its header (.h). Returns false on any error.
/// Builds and prints any errors; true on success.
let private build (src: string) (out: string) (emitLlvm: bool) (sanitize: bool) (isLib: bool) =
    match Driver.build src out emitLlvm sanitize isLib with
    | Ok() -> true
    | Error errors ->
        for e in errors do
            printError e.file e.line e.col e.msg

        if errors.Length > 1 then
            eprintfn "%d errors" errors.Length

        false

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

/// Builds a file's [<Test>] functions and runs each in its own process, so a failed assert or
/// panic fails that test only. Returns (passed, failed), or None when it didn't build.
let private runTests (src: string) (filter: string list) =
    let names =
        try
            (check src false false).tests
        with CompileErrorAt(file, line, col, msg) ->
            printError file line col msg
            []

    let exe = Path.Combine(Path.GetTempPath(), "zs-test-" + Guid.NewGuid().ToString("N"))
    testBuild <- true

    if names.IsEmpty then
        Some(0, 0)
    elif not (build src exe false false false) then
        None
    else
        Environment.SetEnvironmentVariable("ZS_BACKTRACE", "0")

        let chosen =
            names
            |> List.indexed
            |> List.filter (fun (_, n) -> filter.IsEmpty || filter |> List.exists (fun f -> n.Contains f))

        let mutable failed = 0

        for i, name in chosen do
            let code, output = exec exe [ string i ] true

            if code = 0 then
                printfn "ok   %s" name
            else
                failed <- failed + 1
                printfn "FAIL %s" name

                for l in output.Trim().Split '\n' do
                    if l <> "" then printfn "       %s" l

        File.Delete exe
        Some(chosen.Length - failed, failed)

let private newProject (name: string) =
    if Directory.Exists name then
        eprintfn "%s already exists" name
        1
    else
        Directory.CreateDirectory(Path.Combine(name, "src")) |> ignore
        File.WriteAllText(Path.Combine(name, "zs.toml"), sprintf "[package]\nname = \"%s\"\nversion = \"0.1.0\"\nmain = \"src/main.zs\"\n\n[dependencies]\n# text = { path = \"../text\" }\n" (Path.GetFileName(Path.GetFullPath name)))

        File.WriteAllText(
            Path.Combine(name, "src", "main.zs"),
            "let greeting (who: string) = $\"Hello, {who}!\"\n\nlet main () =\n  match Env.args () with\n  | [] -> println (greeting \"world\")\n  | who :: _ -> println (greeting who)\n  0\n\n[<Test>]\nlet greets () =\n  assert (greeting \"Z#\" = \"Hello, Z#!\")\n"
        )

        File.WriteAllText(Path.Combine(name, ".gitignore"), "build/\n")
        printfn "created %s: zs.toml, src/main.zs (cd %s && zs run)" name name
        0

[<EntryPoint>]
let main argv =
    Codegen.debugInfo <- Array.contains "-g" argv

    if Array.contains "-Os" argv then
        optLevel <- "-Os"
        Codegen.optimizeSize <- true

    let argv = argv |> Array.filter ((<>) "-Os")

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
            let ok = build m.main out (List.contains "--emit-llvm" rest) (List.contains "--sanitize" rest) false

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
                |> List.filter (fun f -> (File.ReadAllText f).Contains "[<Test>]")

            let results =
                files
                |> List.map (fun f ->
                    printfn "%s" (Path.GetRelativePath(Environment.CurrentDirectory, f))
                    runTests f filter)

            let passed = results |> List.sumBy (Option.map fst >> Option.defaultValue 0)
            let failed = results |> List.sumBy (Option.map snd >> Option.defaultValue 0)
            let broken = results |> List.filter Option.isNone |> List.length
            printfn "%d passed, %d failed%s" passed failed (if broken > 0 then sprintf ", %d file(s) didn't build" broken else "")
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
        let ok = build src out (List.contains "--emit-llvm" rest) (List.contains "--sanitize" rest) isLib

        if List.contains "--time" rest then
            for phase, ms in timings do
                eprintfn "%-20s %8.1f ms" phase ms

            eprintfn "%-20s %8.1f ms" "total" (Seq.sumBy snd timings)

        if ok then 0 else 1
    | [ "check"; src ] ->
        // type-check only: every error, nothing built
        try
            let prog = check src true true

            for e in prog.errors do
                printError e.file e.line e.col e.msg

            if prog.errors.IsEmpty then 0 else 1
        with CompileErrorAt(file, line, col, msg) ->
            printError file line col msg
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
                    h.name, sprintf "%s : %s%s" h.name (Core.show h.hty) needs)
                |> dict

            let items = docItems src
            let section (title: string) (kinds: string list) =
                let chosen = items |> List.filter (fun d -> List.contains d.kind kinds)

                if not chosen.IsEmpty then
                    printfn "## %s\n" title

                    for d in chosen do
                        let shown =
                            match d.kind with
                            | "function" when signatures.ContainsKey d.key -> signatures[d.key]
                            | _ -> d.title

                        let heading = if List.contains d.kind [ "case"; "method"; "member" ] then "####" else "###"
                        printfn "%s `%s`\n\n```zsharp\n%s\n```\n" heading d.key shown

                        match d.doc with
                        | Some doc -> printfn "%s\n" doc
                        | None -> printfn "_Undocumented._\n"

            printfn "# %s\n" (Path.GetFileNameWithoutExtension full)
            section "Traits" [ "trait"; "method" ]
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
        | Some(0, 0) ->
            eprintfn "%s: no [<Test>] functions" src
            1
        | Some(passed, failed) ->
            printfn "%d passed, %d failed" passed failed
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

        if build src exe false (List.contains "--sanitize" rest) false then
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
        eprintfn "usage: zs new <name>\n       zs fetch | zs update\n       zs build [<file.zs> [-o <out>] [--lib]] [-g] [--target <triple>] [--emit-llvm] [--sanitize] [--time]\n       zs run [<file.zs> [-g] [--sanitize] --] [program arguments…]\n       zs check <file.zs>\n       zs test [<file.zs>] [name filters…]\n       zs doc <file.zs>\n       zs fmt [--check] <files…>\n       zs lsp\n       zs mcp"
        2
