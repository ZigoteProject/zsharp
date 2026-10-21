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

[<EntryPoint>]
let main argv =
    match List.ofArray argv with
    | "build" :: src :: rest ->
        let out =
            match List.tryFindIndex ((=) "-o") rest with
            | Some i when i + 1 < rest.Length -> rest[i + 1]
            | _ -> Path.GetFileNameWithoutExtension src

        let isLib = List.contains "--lib" rest
        if build src out (List.contains "--emit-llvm" rest) (List.contains "--sanitize" rest) isLib then 0 else 1
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
    | "lsp" :: _ -> Lsp.serve () // editors may add flags such as --stdio
    | "mcp" :: _ -> Mcp.serve ()
    | "run" :: src :: rest ->
        let exe = Path.Combine(Path.GetTempPath(), "zs-" + Guid.NewGuid().ToString("N"))

        if build src exe false (List.contains "--sanitize" rest) false then
            let code, _ = exec exe [] false
            File.Delete exe
            code
        else
            1
    | _ ->
        eprintfn "usage: zs build <file.zs> [-o <out>] [--lib] [--emit-llvm] [--sanitize]\n       zs run <file.zs> [--sanitize]\n       zs check <file.zs>\n       zs fmt [--check] <files…>\n       zs lsp\n       zs mcp"
        2
