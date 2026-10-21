/// The compiler front end shared by the command line and the language server: loading the
/// main file's modules (from disk, or from an editor's unsaved buffers), and the full pipeline.
module Driver

open System
open System.Collections.Generic
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
    let _, prelude = parseFile (runtimeFile "prelude.zs")
    Typer.check requireMain collect (("prelude.zs", None, prelude) :: loadModules mainPath)

/// Source files -> typed Core -> monomorphic -> closure-converted -> RC-annotated -> LLVM IR
/// (and a C header for [<Export>] functions). A library doesn't need `main`.
let compileProgram (mainPath: string) (isLib: bool) =
    let prog = check mainPath (not isLib) true

    match prog.errors with
    | first :: _ -> Error prog.errors
    | [] ->
        let funs =
            try
                prog |> Mono.run |> Lift.run |> Rc.run prog.types
            with CompileError(l, m) ->
                raise (CompileErrorAt(mainPath, l, 0, m))

        Ok(Codegen.compile prog.types prog.externs prog.exports prog.clayouts funs)
