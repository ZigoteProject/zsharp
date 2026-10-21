module Main

open System
open System.Diagnostics
open System.Collections.Generic
open System.IO
open Syntax

let private exec (exe: string) (args: string list) =
    let psi = ProcessStartInfo exe

    for a in args do
        psi.ArgumentList.Add a

    use p = Process.Start psi
    p.WaitForExit()
    p.ExitCode

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
let private build (src: string) (out: string) (emitLlvm: bool) (sanitize: bool) (isLib: bool) =
    let ir =
        try
            if not (File.Exists src) then
                raise (CompileErrorAt(src, 0, 0, "file not found"))

            match compileProgram src isLib with
            | Ok r -> Some r
            | Error errors ->
                for e in errors do
                    printError e.file e.line e.col e.msg

                if errors.Length > 1 then
                    eprintfn "%d errors" errors.Length

                None
        with
        | CompileErrorAt(file, line, col, msg) ->
            printError file line col msg
            None
        | CompileError(line, msg) ->
            printError src line 0 msg
            None

    match ir with
    | None -> false
    | Some(ir, header) ->
        let ll =
            if emitLlvm then
                Path.ChangeExtension(out, ".ll")
            else
                Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N") + ".ll")

        File.WriteAllText(ll, ir)
        let san = if sanitize then [ "-fsanitize=address,undefined"; "-g" ] else []

        let ok =
            if isLib then
                // objects for the program and the runtime, archived, plus the header
                let obj = Path.ChangeExtension(ll, ".o")
                let rt = Path.ChangeExtension(ll, ".rt.o")

                let ok =
                    exec "clang" ([ "-O2"; "-c"; "-Wno-override-module" ] @ san @ [ ll; "-o"; obj ]) = 0
                    && exec "clang" ([ "-O2"; "-c" ] @ san @ [ runtimeFile "rt.c"; "-o"; rt ]) = 0
                    && (File.Delete out |> fun () -> exec "llvm-ar" [ "rcs"; out; obj; rt ] = 0)

                File.WriteAllText(Path.ChangeExtension(out, ".h"), header)

                for f in [ obj; rt ] do
                    if File.Exists f then
                        File.Delete f

                ok
            else
                let args = [ "-O2"; "-rdynamic"; "-Wno-override-module" ] @ san @ [ ll; runtimeFile "rt.c"; "-o"; out; "-lm" ]
                exec "clang" args = 0

        if not emitLlvm then
            File.Delete ll

        ok

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
    | "run" :: src :: rest ->
        let exe = Path.Combine(Path.GetTempPath(), "zs-" + Guid.NewGuid().ToString("N"))

        if build src exe false (List.contains "--sanitize" rest) false then
            let code = exec exe []
            File.Delete exe
            code
        else
            1
    | _ ->
        eprintfn "usage: zs build <file.zs> [-o <out>] [--lib] [--emit-llvm] [--sanitize]\n       zs run <file.zs> [--sanitize]\n       zs check <file.zs>\n       zs lsp"
        2
