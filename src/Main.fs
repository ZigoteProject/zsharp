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

let private runtimeFile name = Path.Combine(AppContext.BaseDirectory, name)

let private parseFile (path: string) =
    try
        let toks = File.ReadAllText path |> lex
        toks, parse toks
    with CompileError(l, m) ->
        raise (CompileErrorAt(path, l, m))

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
        |> List.tryFind File.Exists

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
                            for isExpr, text in parts do
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
                raise (CompileErrorAt(display path, 0, sprintf "import cycle: %s" (String.concat " -> " (List.rev (m :: stack)))))
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

/// Source files -> typed Core -> monomorphic -> closure-converted -> RC-annotated -> LLVM IR.
let compileProgram (mainPath: string) =
    let preludePath = runtimeFile "prelude.zs"
    let _, prelude = parseFile preludePath
    let prog = Typer.check (("prelude.zs", None, prelude) :: loadModules mainPath)

    let funs =
        try
            prog |> Mono.run |> Lift.run |> Rc.run prog.types
        with CompileError(l, m) ->
            raise (CompileErrorAt(mainPath, l, m))

    Codegen.compile prog.types prog.externs funs

/// .zs -> LLVM IR -> clang (with the runtime) -> native executable. Returns false on any error.
let private build (src: string) (out: string) (emitLlvm: bool) (sanitize: bool) =
    let ir =
        try
            if not (File.Exists src) then
                raise (CompileErrorAt(src, 0, "file not found"))

            Some(compileProgram src)
        with
        | CompileErrorAt(file, line, msg) ->
            if line > 0 then
                eprintfn "%s:%d: error: %s" file line msg
            else
                eprintfn "%s: error: %s" file msg

            None
        | CompileError(line, msg) ->
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
