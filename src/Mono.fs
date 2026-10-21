/// Monomorphization: copies each generic function once per concrete instantiation reachable
/// from main. The output has no type variables.
module Mono

open System.Collections.Generic
open Core

type MFun =
    { name: string
      pars: (string * Ty) list
      ret: Ty
      body: CExpr }

let mangle (name: string) (inst: Ty list) =
    if inst.IsEmpty then
        name
    else
        name + "<" + (inst |> List.map show |> String.concat ",") + ">"

/// Concrete type: quantified variables replaced, everything else resolved (defaulted).
let rec private concrete (inst: Ty list) t =
    match prune t with
    | TGen i -> List.item i inst
    | TCon(n, a) -> TCon(n, List.map (concrete inst) a)
    | TFun(a, b) -> TFun(concrete inst a, concrete inst b)
    | TTuple ts -> TTuple(List.map (concrete inst) ts)
    | TVar _ as t -> resolve t

let run (prog: Program) : MFun list =
    let defs = prog.funs |> List.map (fun f -> f.name, f) |> dict
    let seen = HashSet<string>()
    let queue = Queue<string * Ty list>()
    let out = ResizeArray<MFun>()

    let request name inst =
        let m = mangle name inst

        if seen.Add m then
            queue.Enqueue(name, inst)

        m

    request "main" [] |> ignore

    while queue.Count > 0 do
        let name, inst = queue.Dequeue()
        let f = defs[name]
        let ct = concrete inst

        let rec ex (e: CExpr) : CExpr =
            let k =
                match e.k with
                | CGlobal(g, Some gi) -> CGlobal(request g (List.map ct gi), Some [])
                | CGlobal(g, None) -> CGlobal(request g inst, Some []) // self-recursion
                | CLam(ps, b) -> CLam(ps |> List.map (fun (x, t) -> x, ct t), ex b)
                | CLetFun(n, r, ps, b, rest) -> CLetFun(n, r, ps |> List.map (fun (x, t) -> x, ct t), ex b, ex rest)
                | CMatch(s, cases) -> CMatch(ex s, cases |> List.map (fun (p, g, b) -> mapPatTypes ct p, Option.map ex g, ex b))
                | k -> mapChildren ex k

            { k = k; ty = ct e.ty }

        out.Add
            { name = mangle name inst
              pars = f.pars |> List.map (fun (x, t) -> x, ct t)
              ret = ct f.ret
              body = ex f.body }

    List.ofSeq out
