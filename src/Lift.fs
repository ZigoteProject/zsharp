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
    | n, TFun(_, r, _) -> resultAfter (n - 1) r
    | _ -> failwith "resultAfter: not a function type"

/// external: the arity of a function another module has the code of. wrapped: a closure of a
/// top-level function goes through a function of its maker's own, which calls it, so a function
/// borrows what it may whatever makes closures of it (a module's code is then the same whichever
/// modules are made with it, Driver).
let runWith (external: string -> int option) (wrapped: bool) (funs: MFun list) : MFun list =
    let arities = funs |> List.map (fun f -> f.name, f.pars.Length) |> dict

    let arity (g: string) =
        match arities.TryGetValue g with
        | true, n -> n
        | _ ->
            match external g with
            | Some n -> n
            | None -> failwithf "Lift: unknown function %s" g
    // per thread, for the function being converted: what it lifts out, its file and line, and
    // its lambdas' numbers (so its code doesn't depend on other functions')
    let out = new System.Threading.ThreadLocal<ResizeArray<MFun>>(fun () -> ResizeArray())
    let source = new System.Threading.ThreadLocal<string * int>(fun () -> ("", 0))
    let count = new System.Threading.ThreadLocal<int ref>(fun () -> ref 0)
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
        if args.IsEmpty then f else mk (CApplyClo(f, args)) (resultAfter args.Length f.ty)

    /// A closure of top-level function g holding args (owner's): of g itself, or of a function
    /// of owner's that calls g.
    let closureOf (owner: string) (g: string) (fty: Ty) (args: CExpr list) =
        if not wrapped then
            mk (CMkClosure(g, args)) (resultAfter args.Length fty)
        else
            count.Value.Value <- count.Value.Value + 1
            let w = sprintf "%s$call%d" owner count.Value.Value
            let rec split n t = if n = 0 then [], t else (match prune t with TFun(a, r, _) -> (let ps, res = split (n - 1) r in a :: ps, res) | _ -> failwith "closureOf")
            let ptys, res = split (arity g) fty
            let ps = ptys |> List.mapi (fun i t -> sprintf "$w%d" i, t)
            let body = mk (CCallDirect(g, ps |> List.map (fun (x, t) -> mk (CLocal x) t))) res

            out.Value.Add
                { name = w
                  pars = ps
                  ret = res
                  row = rowEmpty
                  body = body
                  file = fst source.Value
                  line = snd source.Value }

            mk (CMkClosure(w, args)) (resultAfter args.Length fty)

    /// A call of f with its first parameters pre (captures) and these arguments: direct when
    /// they're enough, else a closure (topLevel: f is a top-level function, see closureOf).
    let direct owner (topLevel: bool) f (pre: CExpr list) n (fty: Ty) (args: CExpr list) =
        if args.Length >= n then
            let now, later = List.splitAt n args
            applyChain (mk (CCallDirect(f, pre @ now)) (resultAfter n fty)) later
        elif topLevel then
            closureOf owner f fty args
        else
            mk (CMkClosure(f, pre @ args)) (resultAfter args.Length fty)

    let rec conv (lfuns: Map<string, LocalFun>) (owner: string) (e: CExpr) : CExpr =
        let cv = conv lfuns owner

        match e.k with
        | CLocal x when lfuns.ContainsKey x ->
            let lf = lfuns[x]
            mk (CMkClosure(lf.lname, capExprs lf.caps)) e.ty
        | CGlobal(g, _) -> closureOf owner g e.ty []
        | CApp(h, args) ->
            let args = List.map cv args

            match h.k with
            | CGlobal(g, _) -> direct owner true g [] (arity g) h.ty args
            | CLocal x when lfuns.ContainsKey x ->
                let lf = lfuns[x]
                direct owner false lf.lname (capExprs lf.caps) lf.arity h.ty args
            | _ -> applyChain (cv h) args
        | CLam(ps, body) ->
            let caps = captures lfuns e Set.empty
            count.Value.Value <- count.Value.Value + 1
            let lname = sprintf "%s$lam%d" owner count.Value.Value
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
        | CLetRec(fs, rest) ->
            // functions that call each other: each takes every capture of the group, so a call
            // between them passes the captures along
            let names = fs |> List.map (fun (g, _, _) -> g) |> Set.ofList

            let caps =
                fs
                |> List.collect (fun (_, ps, body) -> captures lfuns body (Set.union names (Set.ofList (List.map fst ps))))
                |> List.distinctBy fst

            let lfuns =
                fs
                |> List.fold
                    (fun (m: Map<string, LocalFun>) (g, ps, _) ->
                        m.Add(
                            g,
                            { lname = owner + "$" + g
                              caps = caps
                              arity = ps.Length }
                        ))
                    lfuns

            for g, ps, body in fs do
                lift lfuns lfuns[g].lname caps ps body

            conv lfuns owner rest
        | k -> mk (mapChildren cv k) e.ty

    and lift lfuns lname caps ps (body: CExpr) =
        let body = conv lfuns lname body

        out.Value.Add
            { name = lname
              pars = caps @ ps
              ret = body.ty
              row = rowEmpty
              body = body
              file = fst source.Value
              line = snd source.Value }

    // a mutable variable a lambda refers to becomes a cell for its whole scope, which the
    // closure holds: a for loop's body over an impl whose forEach wasn't inlined (a recursive
    // one), the one lambda that may assign its function's variables (0017)
    let rec mentions (x: string) (e: CExpr) =
        match e.k with
        | CLocal y
        | CAssign(y, _)
        | CArraySet(y, _, _) when y = x -> true
        | k -> children k |> List.exists (mentions x)

    let rec lambdaMentions (x: string) (e: CExpr) =
        match e.k with
        | CLam(_, b) -> mentions x b
        | k -> children k |> List.exists (lambdaMentions x)

    let rec cells (e: CExpr) : CExpr =
        match e.k with
        | CLetMut(x, v, body) when lambdaMentions x body ->
            let v = cells v
            let cell = TCon("ref", [ v.ty ])

            let rec through (e: CExpr) =
                match e.k with
                | CLocal y when y = x -> mk (CPrim("ref.get", [ mk (CLocal x) cell ])) e.ty
                | CAssign(y, w) when y = x -> mk (CPrim("ref.set", [ mk (CLocal x) cell; through w ])) e.ty
                | CArraySet(y, _, _) when y = x -> failwith "Lift: an array element assigned through a loop's cell"
                | k -> mk (mapChildren through k) e.ty

            mk (CLet(x, mk (CPrim("ref", [ v ])) cell, through (cells body))) e.ty
        | k -> mk (mapChildren cells k) e.ty

    // each function on its own, on every core; its lifted lambdas come before it, as they're made
    let one (f: MFun) =
        source.Value <- (f.file, f.line) // lifted lambdas are debugged as part of their function
        count.Value.Value <- 0
        let mine = ResizeArray<MFun>()
        out.Value <- mine
        mine.Add { f with body = conv Map.empty f.name (cells f.body) }
        List.ofSeq mine

    try
        funs |> Array.ofList |> Array.Parallel.map one |> List.concat
    with :? System.AggregateException as e ->
        raise e.InnerExceptions[0]

let run (funs: MFun list) : MFun list = runWith (fun _ -> None) false funs
