/// The passes after checking (the F# compiler's Driver.lift and lower): monomorphization with the
/// share check and fusion, inlining, effects as evidence, closure conversion and reference
/// counting; code generation comes after them.
// ponytail: no Simplify or Decide yet (matches stay as written, as ZS_NO_DECIDE=1 has them)
open Core.Program

/// ZS_DUMP_CORE=name (* for all): the Core of matching functions after reference counting, or
/// after the stage ZS_DUMP_STAGE names (mono, inline, effects, lift), as the F# compiler shows it.
let private dumpAt (stage: string) (funs: list<MFun>) =
  let wanted =
    match Environment.getVariable "ZS_DUMP_STAGE" with
    | Some s -> if s = "" then "rc" else s
    | None -> "rc"
  match Environment.getVariable "ZS_DUMP_CORE" with
  | Some name ->
    if wanted = stage then
      let v = Types.Vars.make ()
      for f in funs do
        if name = "*" || String.contains name f.name then
          let pars = String.join ", " (List.map fst f.pars)
          eprintln $"{f.name}({pars}) =\n{Core.Ir.showCore (Types.Show.show v) 1 f.body}\n"
  | None -> ()

let private stage (name: string) (funs: list<MFun>) : list<MFun> =
  dumpAt name funs
  funs

// whether a function waits (a task's state machine)
let rec private waits (e: Core.Ir.CExpr) : bool =
  match e.k with
  | Core.Ir.CPrim(op, _) -> op = "task.suspend" || op = "task.abandon" || List.exists waits (Core.Ir.children e.k)
  | k -> List.exists waits (Core.Ir.children k)

/// A checked program's functions monomorphic, closure-converted and reference counted, with the
/// types the passes added (effects' frames); Error where a pass can't go on.
let lower (prog0: Program) : result<Map<string, Types.Ty.TypeInfo> * list<MFun>, PassError> =
  let prog = Opt.Mono.lowered prog0
  // functions called from outside keep their signatures (main, the tests, C exports)
  let fixedNames = Set.ofList ("main" :: List.append prog.tests (List.map (fun (e: Core.Ir.Export) -> e.fname) prog.exports))
  // [<Target>] and [<Multiversion>] functions stay whole: their code is for features their
  // callers may not have
  let kept (n: string) = Map.containsKey (Core.Ir.baseFunName n) prog.targets
  let passes () : result<Map<string, Types.Ty.TypeInfo> * list<MFun>, PassError> / Stops =
    let mono = stage "mono" (Opt.Mono.fuse (Opt.Mono.checkShared prog (Opt.Mono.run prog)))
    let inlined = stage "inline" (Opt.Inline.run kept (Opt.Inline.uncurry fixedNames mono))
    let (types, lowered) = Opt.Evidence.run prog.types prog.effects inlined
    let lifted = stage "lift" (Opt.Lift.run (stage "effects" lowered))
    // a task's state machine owns its parameters: they live in its coroutine frame past the call
    // that starts it
    let machines = Set.ofList (List.map (fun (f: MFun) -> f.name) (List.filter (fun (f: MFun) -> waits f.body) lifted))
    let entries = Set.union fixedNames machines
    let counted = stage "rc" (Opt.Rc.lower types (Opt.Rc.borrowing types entries lifted) lifted)
    Ok(types, counted)
  handle passes () with
  | Stops.stop e, _ -> Error e
