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
    | [ "lsp" ] -> Lsp.serve ()
    | [ "mcp" ] -> Mcp.serve ()
    | "run" :: src :: rest ->
        let exe = Path.Combine(Path.GetTempPath(), "zs-" + Guid.NewGuid().ToString("N"))

        if build src exe false (List.contains "--sanitize" rest) false then
            let code, _ = exec exe [] false
            File.Delete exe
            code
        else
            1
    | _ ->
        eprintfn "usage: zs build <file.zs> [-o <out>] [--lib] [--emit-llvm] [--sanitize]\n       zs run <file.zs> [--sanitize]\n       zs check <file.zs>\n       zs lsp\n       zs mcp"
        2
