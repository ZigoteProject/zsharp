/// The compiler front end shared by the command line and the language server: loading the
/// main file's modules (from disk, or from an editor's unsaved buffers), and the full pipeline.
module Driver

open System
open System.Collections.Generic
open System.Diagnostics
open System.IO
open Syntax

let runtimeFile name = Path.Combine(AppContext.BaseDirectory, name)

/// Unsaved editor buffers by full path; read instead of the file on disk.
let overlay = Dictionary<string, string>()

let readSource (path: string) =
    match overlay.TryGetValue(Path.GetFullPath path) with
    | true, text -> text
    | _ -> File.ReadAllText path

let parseFile (path: string) =
    try
        let toks = readSource path |> lex
        toks, parse toks
    with
    | CompileError(l, m) -> raise (CompileErrorAt(path, l, 0, m))
    | CompileErrorPos(l, c, m) -> raise (CompileErrorAt(path, l, c, m))

/// The main file and the modules it uses (`open M` or `M.name`, found as M.zs or m.zs next to
/// it), dependencies first. Each module is named after its file unless it has a `module` header.
let loadModules (mainPath: string) : (string * string option * (int * Decl) list) list =
    let dir = Path.GetDirectoryName(Path.GetFullPath mainPath)
    let order = ResizeArray<string * string option * (int * Decl) list>()
    let finished = Dictionary<string, bool>() // module -> fully loaded?
    let display (p: string) = Path.GetRelativePath(Environment.CurrentDirectory, p)

    let fileOf (m: string) =
        [ m + ".zs"; string (Char.ToLower m[0]) + m.Substring 1 + ".zs" ]
        |> List.map (fun f -> Path.Combine(dir, f))
        |> List.tryFind (fun f -> File.Exists f || overlay.ContainsKey f)

    let rec visit (path: string) (modName: string option) (stack: string list) =
        let toks, decls = parseFile path

        let modName =
            match decls, modName with
            | (_, ModuleHeader h) :: _, Some _ -> Some h
            | _ -> modName

        let deps =
            [ for _, d in decls do
                  match d with
                  | Open m -> yield m
                  | _ -> ()

              let rec qualified (toks: Token[]) =
                  [ for t in toks do
                        match t.tok with
                        | KId s when s.Contains "." && Char.IsUpper s[0] -> yield s.Substring(0, s.IndexOf '.')
                        | KInterp parts ->
                            for isExpr, text, _ in parts do
                                if isExpr then
                                    yield! qualified (lex text)
                        | _ -> () ]

              yield! qualified toks ]
            |> List.distinct
            |> List.filter (fun m ->
                match fileOf m with
                | Some f -> Some m <> modName && f <> path && f <> Path.GetFullPath mainPath
                | None -> false)

        for m in deps do
            match finished.TryGetValue m with
            | true, true -> ()
            | true, false ->
                raise (CompileErrorAt(display path, 0, 0, sprintf "import cycle: %s" (String.concat " -> " (List.rev (m :: stack)))))
            | _ ->
                finished[m] <- false
                visit (fileOf m).Value (Some m) (m :: stack)
                finished[m] <- true

        order.Add(display path, modName, decls)

    visit (Path.GetFullPath mainPath) None [ Path.GetFileNameWithoutExtension mainPath ]
    // the main file keeps the path the user gave
    let last = order.Count - 1
    let _, m, ds = order[last]
    order[last] <- (mainPath, m, ds)
    List.ofSeq order

/// Parses and type-checks; with collect, every declaration's error is in the result.
let check (mainPath: string) (requireMain: bool) (collect: bool) : Core.Program =
    positions.Clear()
    let full = Path.GetFullPath mainPath

    // checking the prelude itself (the installed one, or runtime/prelude.zs in a checkout):
    // it is the prelude, not a program that would define everything a second time
    let isPrelude =
        full = Path.GetFullPath(runtimeFile "prelude.zs")
        || (Path.GetFileName full = "prelude.zs" && Path.GetFileName(Path.GetDirectoryName full) = "runtime")

    if isPrelude then
        let _, decls = parseFile mainPath
        Typer.check false collect [ mainPath, None, decls ]
    else
        let _, prelude = parseFile (runtimeFile "prelude.zs")
        Typer.check requireMain collect (("prelude.zs", None, prelude) :: loadModules mainPath)

/// Source files -> typed Core -> monomorphic -> closure-converted -> RC-annotated -> LLVM IR
/// (and a C header for [<Export>] functions). A library doesn't need `main`.
/// Time spent in each compiler phase of the last build (zs build --time).
let timings = ResizeArray<string * float>()

let private timed (phase: string) (f: unit -> 'a) : 'a =
    let sw = Stopwatch.StartNew()
    let r = f ()
    timings.Add(phase, sw.Elapsed.TotalMilliseconds)
    r

let compileProgram (mainPath: string) (isLib: bool) =
    timings.Clear()
    let prog = timed "parse + check" (fun () -> check mainPath (not isLib) true)

    match prog.errors with
    | first :: _ -> Error prog.errors
    | [] ->
        let funs =
            try
                let mono = timed "monomorphize" (fun () -> Mono.run prog)
                let lifted = timed "lift closures" (fun () -> Lift.run mono)
                timed "reference counting" (fun () -> Rc.run prog.types lifted)
            with CompileError(l, m) ->
                raise (CompileErrorAt(mainPath, l, 0, m))

        Ok(timed "LLVM IR" (fun () -> Codegen.compile prog.types prog.externs prog.exports prog.tests prog.clayouts funs))

/// Runs a program; with capture, returns its stdout and stderr too (stdin is empty).
let exec (exe: string) (args: string list) (capture: bool) : int * string =
    let psi = ProcessStartInfo exe

    for a in args do
        psi.ArgumentList.Add a

    if capture then
        psi.RedirectStandardOutput <- true
        psi.RedirectStandardError <- true
        psi.RedirectStandardInput <- true

    use p = Process.Start psi

    if capture then
        p.StandardInput.Close()
        let out = p.StandardOutput.ReadToEndAsync()
        let err = p.StandardError.ReadToEndAsync()
        p.WaitForExit()
        p.ExitCode, out.Result + err.Result
    else
        p.WaitForExit()
        p.ExitCode, ""

/// .zs -> LLVM IR -> clang (with the runtime) -> native executable, or with isLib a static
/// library (.a) plus its header (.h).
let build (src: string) (out: string) (emitLlvm: bool) (sanitize: bool) (isLib: bool) : Result<unit, Core.Diagnostic list> =
    let toolError (msg: string) : Core.Diagnostic list =
        [ { file = src
            line = 0
            col = 0
            msg = msg } ]

    let ir =
        try
            if not (File.Exists src || overlay.ContainsKey(Path.GetFullPath src)) then
                raise (CompileErrorAt(src, 0, 0, "file not found"))

            compileProgram src isLib
        with
        | CompileErrorAt(file, line, col, msg) ->
            Error
                [ { file = file
                    line = line
                    col = col
                    msg = msg } ]
        | CompileError(line, msg) ->
            Error
                [ { file = src
                    line = line
                    col = 0
                    msg = msg } ]

    match ir with
    | Error e -> Error e
    | Ok(ir, header) ->
        let ll =
            if emitLlvm then
                Path.ChangeExtension(out, ".ll")
            else
                Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N") + ".ll")

        File.WriteAllText(ll, ir)
        let san = if sanitize then [ "-fsanitize=address,undefined"; "-g" ] else []

        let run (exe: string) (args: string list) =
            let code, output = exec exe args true
            if code = 0 then None else Some(sprintf "%s failed: %s" exe (output.Trim()))

        let failure =
            if isLib then
                // objects for the program and the runtime, archived, plus the header
                let obj = Path.ChangeExtension(ll, ".o")
                let rt = Path.ChangeExtension(ll, ".rt.o")

                let failure =
                    run "clang" ([ "-O2"; "-c"; "-Wno-override-module" ] @ san @ [ ll; "-o"; obj ])
                    |> Option.orElseWith (fun () -> run "clang" ([ "-O2"; "-c" ] @ san @ [ runtimeFile "rt.c"; "-o"; rt ]))
                    |> Option.orElseWith (fun () ->
                        if File.Exists out then
                            File.Delete out

                        run "llvm-ar" [ "rcs"; out; obj; rt ])

                File.WriteAllText(Path.ChangeExtension(out, ".h"), header)

                for f in [ obj; rt ] do
                    if File.Exists f then
                        File.Delete f

                failure
            else
                timed "clang" (fun () -> run "clang" ([ "-O2"; "-rdynamic"; "-Wno-override-module" ] @ san @ [ ll; runtimeFile "rt.c"; "-o"; out; "-lm" ]))

        if not emitLlvm then
            File.Delete ll

        match failure with
        | None -> Ok()
        | Some msg -> Error(toolError msg)

/// The `///` comment lines right above a definition (attribute lines in between are skipped),
/// without the slashes; None if there are none. `prelude.zs` means the installed prelude.
let docAbove (file: string) (line: int) : string option =
    let path = if file = "prelude.zs" then runtimeFile "prelude.zs" else file

    let lines =
        try
            (readSource path).Replace("\r\n", "\n").Split '\n'
        with _ ->
            [||]

    let mutable i = line - 2 // the line above, 0-based
    let doc = ResizeArray<string>()

    while i >= 0 && i < lines.Length && (lines[i].TrimStart().StartsWith "///" || lines[i].TrimStart().StartsWith "[<") do
        let t = lines[i].TrimStart()

        if t.StartsWith "///" then
            let text = t.Substring 3
            doc.Insert(0, if text.StartsWith " " then text.Substring 1 else text)

        i <- i - 1

    if doc.Count = 0 then None else Some(String.concat "\n" doc)

/// Docs for functions built into the compiler (they have no definition to read a comment from).
let builtinDocs =
    dict
        [ "print", "Writes the string to standard output, without a newline."
          "println", "Writes the string and a newline to standard output."
          "eprintln", "Writes the string and a newline to standard error."
          "string", "The text form of a value (`Show.show`): numbers, bools, strings, and any type with `Show`."
          "panic", "Stops the program with the message (and a backtrace). For bugs, not for errors a caller should handle."
          "failwith", "Same as `panic`."
          "assert", "Panics with \"assertion failed\" when the condition is false."
          "ignore", "Discards a value."
          "ref", "A mutable cell holding the value; read and write it with `r.Value`."
          "Array.create", "An array of `n` copies of `x`."
          "Array.length", "The number of elements."
          "String.length", "The length in bytes (UTF-8)."
          "String.sub", "The `len` bytes of `s` starting at byte `start`. Panics if out of range."
          "String.byte", "The byte at index `i`. Panics if out of range."
          "String.ofByte", "A one-byte string."
          "String.trim", "`s` without leading and trailing spaces, tabs and line breaks."
          "String.toUpper", "`s` with ASCII letters in upper case."
          "String.toLower", "`s` with ASCII letters in lower case."
          "String.replace", "`s` with every occurrence of `old` replaced by `by`."
          "String.ofCStr", "A Z# string copied from a C string (`const char*`)."
          "Array.set", "`a` with element `i` replaced by `x`. Arrays are values: `a` itself is unchanged (it is reused in place when nothing else refers to it)."
          "Buffer.create", "A Buffer of `n` copies of `x`. A Buffer is shared and mutable: a write is seen through every reference."
          "Buffer.length", "The number of elements."
          "Buffer.ofArray", "A new Buffer with the array's elements."
          "Buffer.toArray", "An array copy of the Buffer's current elements."
          "Int.wrappingAdd", "`a + b`, wrapping around on overflow instead of panicking."
          "Int.wrappingSub", "`a - b`, wrapping around on overflow instead of panicking."
          "Int.wrappingMul", "`a * b`, wrapping around on overflow instead of panicking."
          "Runtime.allocations", "The number of heap objects allocated so far."
          "Process.exit", "Ends the program now with the exit code (output is flushed; nothing else is cleaned up)."
          "File.exists", "Whether `path` names an existing regular file."
          "Dir.exists", "Whether `path` names an existing directory." ]

/// A documented item of a source file, found by reading its declarations.
type DocItem =
    { kind: string // function, type, case, trait, method, derive, impl, member
      key: string // what hovers refer to: List.map, option, Some, Show.show, show, string#Length
      title: string // the declaration as written, without its body
      line: int
      doc: string option }

/// The declarations of a file with their doc comments: top-level `let`, `type`, `trait`,
/// `derive`, `impl`, plus union cases, trait methods and members under them.
let docItems (file: string) : DocItem list =
    let path = if file = "prelude.zs" then runtimeFile "prelude.zs" else file

    let lines =
        try
            (readSource path).Replace("\r\n", "\n").Split '\n'
        with _ ->
            [||]

    let header (l: string) =
        // the declaration without its body: up to a top-level `=` (not ==, <=, >=, <>)
        let t = l.Trim()
        let m = Text.RegularExpressions.Regex.Match(t, @"\s=(\s|$)")
        if m.Success then t.Substring(0, m.Index).Trim() else t

    let items = ResizeArray<DocItem>()
    let mutable container = "" // the type, extension or trait whose block we are in
    let mutable containerKind = ""

    let add kind key (i: int) =
        items.Add
            { kind = kind
              key = key
              title = header lines[i]
              line = i + 1
              doc = docAbove file (i + 1) }

    let rx (p: string) (l: string) = Text.RegularExpressions.Regex.Match(l, p)

    for i in 0 .. lines.Length - 1 do
        let l = lines[i]

        if l.Length > 0 && not (Char.IsWhiteSpace l[0]) && not (l.StartsWith "//") && not (l.StartsWith "[<") then
            container <- ""
            containerKind <- ""

            let m = rx @"^let\s+(rec\s+)?(private\s+)?([A-Za-z_][A-Za-z0-9_.]*|\(\|[^)]*\|\))" l

            if m.Success then
                if not m.Groups[2].Success then add "function" m.Groups[3].Value i // private: not API
            else
                let m = rx @"^type\s+(private\s+)?([A-Za-z_][A-Za-z0-9_]*)(<[^>]*>)?\s*(with)?" l

                if m.Success then
                    container <- m.Groups[2].Value

                    if m.Groups[1].Success then
                        containerKind <- "private"
                    elif m.Groups[4].Success then
                        containerKind <- "extension"
                    else
                        containerKind <- "type"
                        add "type" container i
                else
                    let m = rx @"^trait\s+([A-Za-z_][A-Za-z0-9_]*)" l

                    if m.Success then
                        container <- m.Groups[1].Value
                        containerKind <- "trait"
                        add "trait" container i
                    else
                        let m = rx @"^derive\s+([A-Za-z_][A-Za-z0-9_]*)" l

                        if m.Success then
                            add "derive" ("derive " + m.Groups[1].Value) i
                        else
                            let m = rx @"^impl\s+(.*?)\s*=\s*$" l
                            if m.Success then add "impl" ("impl " + m.Groups[1].Value) i
        elif container <> "" then
            let t = l.Trim()
            let m = rx @"^\|\s*([A-Z][A-Za-z0-9_]*)" t

            if m.Success && containerKind = "type" then
                add "case" m.Groups[1].Value i
            else
                let m = rx @"^abstract\s+([A-Za-z_][A-Za-z0-9_]*)" t

                if m.Success && containerKind = "trait" then
                    add "method" (container + "." + m.Groups[1].Value) i
                else
                    let m = rx @"^(static\s+)?member\s+(?:[A-Za-z_][A-Za-z0-9_]*\.)?([A-Za-z_][A-Za-z0-9_]*)" t
                    if m.Success then add "member" (container + "#" + m.Groups[2].Value) i

    List.ofSeq items
