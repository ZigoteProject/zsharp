module Main

open System
open System.Diagnostics
open System.IO
open Syntax

let private exec (exe: string) (args: string list) =
    let psi = ProcessStartInfo exe

    for a in args do
        psi.ArgumentList.Add a

    use p = Process.Start psi
    p.WaitForExit()
    p.ExitCode

let private runtimeFile name = Path.Combine(AppContext.BaseDirectory, name)

/// Source -> typed Core -> monomorphic -> closure-converted -> RC-annotated -> LLVM IR.
let compileSource (src: string) =
    let prelude = File.ReadAllText(runtimeFile "prelude.zs") |> lex |> parse
    let user = src |> lex |> parse
    let prog = Typer.check (prelude @ user)
    let funs = prog |> Mono.run |> Lift.run |> Rc.run prog.types
    Codegen.compile prog.types prog.externs funs

/// .zs -> LLVM IR -> clang (with the runtime) -> native executable. Returns false on any error.
let private build (src: string) (out: string) (emitLlvm: bool) (sanitize: bool) =
    let ir =
        try
            if not (File.Exists src) then
                fail 0 "file not found"

            Some(compileSource (File.ReadAllText src))
        with CompileError(line, msg) ->
            if line > 0 then
                eprintfn "%s:%d: error: %s" src line msg
            else
                eprintfn "%s: error: %s" src msg

            None

    match ir with
    | None -> false
    | Some ir ->
        let ll =
            if emitLlvm then
                Path.ChangeExtension(out, ".ll")
            else
                Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N") + ".ll")

        File.WriteAllText(ll, ir)
        let san = if sanitize then [ "-fsanitize=address,undefined"; "-g" ] else []
        let args = [ "-O2"; "-rdynamic"; "-Wno-override-module" ] @ san @ [ ll; runtimeFile "rt.c"; "-o"; out; "-lm" ]
        let code = exec "clang" args

        if not emitLlvm then
            File.Delete ll

        code = 0

[<EntryPoint>]
let main argv =
    match List.ofArray argv with
    | "build" :: src :: rest ->
        let out =
            match List.tryFindIndex ((=) "-o") rest with
            | Some i when i + 1 < rest.Length -> rest[i + 1]
            | _ -> Path.GetFileNameWithoutExtension src

        if build src out (List.contains "--emit-llvm" rest) (List.contains "--sanitize" rest) then 0 else 1
    | "run" :: src :: rest ->
        let exe = Path.Combine(Path.GetTempPath(), "zs-" + Guid.NewGuid().ToString("N"))

        if build src exe false (List.contains "--sanitize" rest) then
            let code = exec exe []
            File.Delete exe
            code
        else
            1
    | _ ->
        eprintfn "usage: zs build <file.zs> [-o <out>] [--emit-llvm] [--sanitize]\n       zs run <file.zs> [--sanitize]"
        2
