/// zs check: a program's modules checked in order, the library's first, and its diagnostics shown
/// as the terminal shows them, with how many of each (the F# compiler's Driver.checkModules and
/// Main's report).
open Diag.Diagnostic

/// A program checked: its modules (the library's, then the program's) and the checker's context
/// (its tables, the functions' Core and the diagnostics).
type Checked = { modules: list<Modules.Loaded>; cx: Infer.Cx.Cx }

let private late : Infer.Cx.Late = { autoDerive = Infer.Decls.autoDerive }

let private inFile (m: Modules.Loaded) : Infer.Cx.InFile = { index = m.source.file; source = m.source; tokens = m.tree.tokens }

/// Checks the program whose main file is mainPath; what stops it before checking (a file it can't
/// read, an import cycle, syntax errors) is Error, with the sources the errors are in.
let program (mainPath: string) (requireMain: bool) (collect: bool) : result<Checked, array<Diagnostic> * list<Syntax.Source.Source>> =
  let noPlace : Span = { file = -1; offset = -1; length = -1 }
  match Modules.library (Modules.libraryDir ()) true with
  | Error e -> Error([| error noPlace e |], [])
  | Ok lib ->
    match Modules.program (List.length lib) mainPath with
    | Error(d, src) -> Error([| d |], Option.toList src)
    | Ok prog ->
      let all = List.append lib prog
      let sources = List.map (fun (m: Modules.Loaded) -> m.source) all
      // a syntax error stops before checking: the first one, as the F# compiler's parser stops
      // there (the ones after it may be its consequences)
      match List.tryFind (fun (m: Modules.Loaded) -> Array.length m.errors > 0) all with
      | Some m -> Error([| m.errors.[0] |], sources)
      | None ->
        let names (ms: list<Modules.Loaded>) = List.choose (fun (m: Modules.Loaded) -> m.modName) ms
        let impls (ms: list<Modules.Loaded>) = List.collect (fun (m: Modules.Loaded) -> m.impls) ms
        let cx = Infer.Cx.create requireMain collect (names lib) (impls lib) Set.empty late (inFile (List.head lib))
        for m in lib do
          Infer.Decls.check cx (inFile m) m.modName m.decls |> ignore
        // the program's modules and explicit impls, as at the start
        for n in names prog do
          for e in Infer.Cx.withEnclosing n do
            cx.moduleNames.Value <- Set.add e cx.moduleNames.Value
        cx.manualImpls.Value <- Set.union cx.manualImpls.Value (Set.ofList (impls prog))
        for m in prog do
          Infer.Decls.check cx (inFile m) m.modName m.decls |> ignore
        Infer.Decls.finish cx
        Ok { modules = all; cx = cx }

/// The program the passes after checking take: the context's tables, with every type settled (a
/// variable bound in the context followed, a free one defaulted, rows in canonical order).
let programOf (cx: Infer.Cx.Cx) : Core.Program.Program =
  let v = cx.v
  let settle (t: Types.Ty.Ty) = Types.Norm.resolve v t
  let pars (ps: list<string * Types.Ty.Ty>) = List.map (fun (x, t) -> (x, settle t)) ps
  let fn (f: Core.Ir.FunDef) : Core.Ir.FunDef =
    { f with pars = pars f.pars; ret = settle f.ret; row = Types.Norm.resolveRow v f.row; body = Core.Ir.mapTypes settle f.body }
  let ex (e: Core.Ir.Export) : Core.Ir.Export = { e with pars = List.map settle e.pars; ret = settle e.ret }
  let ext (x: Core.Ir.ExternSig) : Core.Ir.ExternSig = { x with pars = List.map settle x.pars; ret = settle x.ret }
  { types = cx.types.Value
    externs = Map.map (fun _ x -> ext x) cx.externs.Value
    funs = List.map fn (Array.toList (Buffer.toArray cx.funs))
    traitMethods = cx.traitMethods.Value
    effects = cx.effects.Value
    impls = cx.impls.Value
    exports = List.map ex (Array.toList (Buffer.toArray cx.exports))
    values = Array.toList (Buffer.toArray cx.valueList)
    tests = Array.toList (Buffer.toArray cx.tests)
    clayouts = cx.clayouts.Value
    targets = cx.targets.Value
    memberNames = Map.map (fun _ (ms: list<string * Infer.Cx.MemberInfo>) -> List.map fst ms) cx.members.Value }

/// Prints diagnostics and, when there's more than one, how many of each; false when they fail the
/// command (an error, or a warning under strict).
let report (sources: list<Syntax.Source.Source>) (ds: array<Diagnostic>) (strict: bool) : bool =
  let byIndex = Map.ofList (List.map (fun (s: Syntax.Source.Source) -> (s.file, s)) sources)
  let none = Syntax.Source.make -1 "" ""
  let sourceOf (i: int) =
    match Map.tryFind i byIndex with
    | Some s -> s
    | None -> none
  Diag.Render.print sourceOf ds
  let errors = Array.length (Array.filter (fun (d: Diagnostic) -> d.severity = Err) ds)
  let warnings = Array.length ds - errors
  let count (n: int) (what: string) = if n = 1 then "1 " + what else $"{n} {what}s"
  let counted =
    match (errors, warnings) with
    | (0, 0) -> ""
    | (e, 0) -> if e > 1 then count e "error" else ""
    | (0, w) -> if w > 1 then count w "warning" else ""
    | (e, w) -> count e "error" + ", " + count w "warning"
  if strict && warnings > 0 && errors = 0 then
    eprintln (count warnings "warning" + ", " + (if warnings = 1 then "an error" else "errors") + " under --strict")
  else if counted <> "" then
    eprintln counted
  errors = 0 && not (strict && warnings > 0)

/// zs check file: every error and warning, nothing built; 0 when it passes.
let run (mainPath: string) (strict: bool) : int =
  match program mainPath true true with
  | Error(ds, sources) -> if report sources ds strict then 0 else 1
  | Ok c ->
    let sources = List.map (fun (m: Modules.Loaded) -> m.source) c.modules
    if report sources (Buffer.toArray c.cx.diagnostics) strict then 0 else 1

/// zs build file: for now the check, with a build's report: its errors when it has any (its
/// warnings then aren't shown), else its warnings; code generation is still the F# compiler's.
let build (mainPath: string) (strict: bool) : int =
  match program mainPath true true with
  | Error(ds, sources) -> if report sources ds strict then 0 else 1
  | Ok c ->
    let sources = List.map (fun (m: Modules.Loaded) -> m.source) c.modules
    let all = Buffer.toArray c.cx.diagnostics
    let errors = Array.filter (fun (d: Diagnostic) -> d.severity = Err) all
    if Array.length errors > 0 then
      report sources errors strict |> ignore
      1
    else if report sources all strict then
      eprintln "zs: building is the F# compiler's still (phase 11): this one checks"
      1
    else
      1
