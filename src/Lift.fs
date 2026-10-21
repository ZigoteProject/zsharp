/// Closure conversion and lambda lifting. Every lambda and local function becomes a top-level
/// function whose leading parameters are its captured variables. Saturated calls to known
/// functions become direct calls; anything else builds or applies a closure.
module Lift

open Core
open Mono

type private LocalFun =
    { lname: string
      caps: (string * Ty) list
      arity: int }

let rec private resultAfter n t =
    match n, prune t with
    | 0, t -> t
    | n, TFun(_, r) -> resultAfter (n - 1) r
    | _ -> failwith "resultAfter: not a function type"

let run (funs: MFun list) : MFun list =
    let arity = funs |> List.map (fun f -> f.name, f.pars.Length) |> dict
    let out = ResizeArray<MFun>()
    let source = ref ("", 0) // the file and line of the function being converted
    let count = ref 0
    let mk k ty = { k = k; ty = ty }

    /// Free value variables, with references to local functions replaced by their captures.
    let captures (lfuns: Map<string, LocalFun>) (e: CExpr) (exclude: Set<string>) =
        let bound = Set.ofList (binders e)

        refs e
        |> List.collect (fun (x, t) ->
            match lfuns.TryFind x with
            | Some lf -> lf.caps
            | None -> [ x, t ])
        |> List.filter (fun (x, _) -> not (bound.Contains x || exclude.Contains x))
        |> List.distinctBy fst

    let capExprs (caps: (string * Ty) list) = caps |> List.map (fun (x, t) -> mk (CLocal x) t)

    let applyChain (f: CExpr) (args: CExpr list) =
        args |> List.fold (fun acc a -> mk (CApplyClo(acc, a)) (resultAfter 1 acc.ty)) f

    let direct f (pre: CExpr list) n (fty: Ty) (args: CExpr list) =
        if args.Length >= n then
            let now, later = List.splitAt n args
            applyChain (mk (CCallDirect(f, pre @ now)) (resultAfter n fty)) later
        else
            mk (CMkClosure(f, pre @ args)) (resultAfter args.Length fty)

    let rec conv (lfuns: Map<string, LocalFun>) (owner: string) (e: CExpr) : CExpr =
        let cv = conv lfuns owner

        match e.k with
        | CLocal x when lfuns.ContainsKey x ->
            let lf = lfuns[x]
            mk (CMkClosure(lf.lname, capExprs lf.caps)) e.ty
        | CGlobal(g, _) -> mk (CMkClosure(g, [])) e.ty
        | CApp(h, args) ->
            let args = List.map cv args

            match h.k with
            | CGlobal(g, _) -> direct g [] arity[g] h.ty args
            | CLocal x when lfuns.ContainsKey x ->
                let lf = lfuns[x]
                direct lf.lname (capExprs lf.caps) lf.arity h.ty args
            | _ -> applyChain (cv h) args
        | CLam(ps, body) ->
            let caps = captures lfuns e Set.empty
            count.Value <- count.Value + 1
            let lname = sprintf "%s$lam%d" owner count.Value
            lift lfuns lname caps ps body
            mk (CMkClosure(lname, capExprs caps)) e.ty
        | CLetFun(g, _, ps, body, rest) ->
            let caps = captures lfuns body (Set.ofList (g :: List.map fst ps))

            let lf =
                { lname = owner + "$" + g
                  caps = caps
                  arity = ps.Length }

            let lfuns = lfuns.Add(g, lf)
            lift lfuns lf.lname caps ps body
            conv lfuns owner rest
        | k -> mk (mapChildren cv k) e.ty

    and lift lfuns lname caps ps (body: CExpr) =
        let body = conv lfuns lname body

        out.Add
            { name = lname
              pars = caps @ ps
              ret = body.ty
              body = body
              file = fst source.Value
              line = snd source.Value }

    for f in funs do
        source.Value <- (f.file, f.line) // lifted lambdas are debugged as part of their function
        out.Add { f with body = conv Map.empty f.name f.body }

    List.ofSeq out
