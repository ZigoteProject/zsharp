/// Perceus reference counting (Reinking, Xie, de Moura, Leijen; PLDI 2021), base algorithm:
/// precise ownership. Every owned variable is consumed exactly once on every path: moved into
/// its last use, dup'ed before earlier uses, and dropped as soon as it is dead (at the start of
/// a branch that does not use it). Function arguments are owned by the callee; a closure being
/// applied is borrowed. Pattern variables borrow from the scrutinee and are dup'ed when used.
module Rc

open Core
open Mono

let run (types: System.Collections.Generic.Dictionary<string, TypeInfo>) (funs: MFun list) : MFun list =
    let heap t = needsRc types t
    let mk k ty = { k = k; ty = ty }
    let count = ref 0

    let tmp () =
        count.Value <- count.Value + 1
        sprintf "$rc%d" count.Value

    let rcFun (f: MFun) =
        // every variable's type, by unique name
        let vtypes = System.Collections.Generic.Dictionary<string, Ty>()

        for x, t in f.pars do
            vtypes[x] <- t

        let rec collect (e: CExpr) =
            match e.k with
            | CLet(x, v, _)
            | CLetMut(x, v, _) -> vtypes[x] <- v.ty
            | CFor(x, a, _, _, _) -> vtypes[x] <- a.ty
            | CMatch(_, cases) ->
                for p, _, _ in cases do
                    for x, t in patVars p do
                        vtypes[x] <- t
            | _ -> ()

            children e.k |> List.iter collect

        collect f.body

        let mutables =
            let rec go (e: CExpr) =
                (match e.k with
                 | CLetMut(x, _, _) -> [ x ]
                 | _ -> [])
                @ (children e.k |> List.collect go)

            Set.ofList (go f.body)

        let heapVar x = heap vtypes[x]

        let drops (vars: Set<string>) (e: CExpr) =
            vars |> Set.fold (fun acc x -> mk (CDrop(x, vtypes[x], acc)) acc.ty) e

        let dups (vars: string seq) (e: CExpr) =
            vars |> Seq.fold (fun acc x -> mk (CDup(x, vtypes[x], acc)) acc.ty) e

        // ponytail: free variables are recomputed per node (quadratic); cache them if compile time matters
        /// e must consume every variable in `owned`; `borrowed` variables stay alive throughout.
        let rec rc (owned: Set<string>) (borrowed: Set<string>) (e: CExpr) : CExpr =
            let fv = freeVars e
            let dead = Set.difference owned fv
            drops dead (rc' (Set.intersect owned fv) borrowed e)

        /// Ordered subexpressions: each owned variable goes to the last one that uses it.
        and rcList (owned: Set<string>) (borrowed: Set<string>) (es: CExpr list) =
            let fvs = es |> List.map freeVars |> Array.ofList

            es
            |> List.mapi (fun i ei ->
                let later = fvs[i + 1 ..] |> Array.fold Set.union Set.empty
                let mine = Set.intersect owned fvs[i]
                let oi = Set.difference mine later
                rc oi (Set.union borrowed (Set.difference mine oi)) ei)

        /// let-binds a non-variable subexpression so it can be inspected by name.
        and viaTemp (owned: Set<string>) (borrowed: Set<string>) (sub: CExpr) (build: CExpr -> CExpr) =
            let t = tmp ()
            vtypes[t] <- sub.ty
            rc' owned borrowed (mk (CLet(t, sub, build (mk (CLocal t) sub.ty))) (build (mk (CLocal t) sub.ty)).ty)

        and isVar (e: CExpr) =
            match e.k with
            | CLocal x -> not (mutables.Contains x)
            | _ -> false

        and rc' (owned: Set<string>) (borrowed: Set<string>) (e: CExpr) : CExpr =
            let re k = mk k e.ty

            match e.k with
            | CLocal x ->
                if owned.Contains x then e
                elif heap e.ty then mk (CDup(x, e.ty, e)) e.ty
                else e
            | CInt _
            | CFloat _
            | CBool _
            | CStr _
            | CUnit -> e
            | CLine(l, a) -> re (CLine(l, rc owned borrowed a))
            | CLet(x, v, body) ->
                let fb = freeVars body
                let fvv = freeVars v
                let ov = Set.difference (Set.intersect owned fvv) fb
                let v' = rc ov (Set.union borrowed (Set.difference (Set.intersect owned fvv) ov)) v
                let ob = Set.difference owned ov
                let ob = if heap v.ty then ob.Add x else ob
                re (CLet(x, v', rc ob borrowed body))
            | CLetMut(x, v, body) ->
                let fb = freeVars body
                let fvv = freeVars v
                let ov = Set.difference (Set.intersect owned fvv) fb
                let v' = rc ov (Set.union borrowed (Set.difference (Set.intersect owned fvv) ov)) v
                re (CLetMut(x, v', rc (Set.difference owned ov) borrowed body))
            | CSeq(a, b) when heap a.ty ->
                let t = tmp ()
                vtypes[t] <- a.ty
                rc' owned borrowed (re (CLet(t, a, b)))
            | CSeq(a, b) ->
                match rcList owned borrowed [ a; b ] with
                | [ a'; b' ] -> re (CSeq(a', b'))
                | _ -> failwith "unreachable"
            | CIf(c, t, f) ->
                let fc = freeVars c
                let fr = Set.union (freeVars t) (freeVars f)
                let mine = Set.intersect owned fc
                let oc = Set.difference mine fr
                let c' = rc oc (Set.union borrowed (Set.difference mine oc)) c
                let rest = Set.difference owned oc
                re (CIf(c', rc rest borrowed t, rc rest borrowed f))
            | CMatch(s, cases) when isVar s ->
                let x =
                    match s.k with
                    | CLocal x -> x
                    | _ -> failwith "unreachable"

                let xOwned = owned.Contains x

                let cases' =
                    cases
                    |> List.map (fun (p, g, body) ->
                        let pvars = patVars p |> List.map fst |> List.filter heapVar |> Set.ofList
                        let all = Set.unionMany [ borrowed; owned; pvars ]
                        let g' = g |> Option.map (rc Set.empty all)

                        if xOwned then
                            let used = Set.intersect pvars (freeVars body)
                            p, g', dups used (rc (Set.union owned used) borrowed body)
                        else
                            p, g', rc owned (Set.union borrowed pvars) body)

                re (CMatch(s, cases'))
            | CMatch(s, cases) -> viaTemp owned borrowed s (fun v -> re (CMatch(v, cases)))
            | CField(r, i) when isVar r ->
                let x =
                    match r.k with
                    | CLocal x -> x
                    | _ -> failwith "unreachable"

                let f = tmp ()
                vtypes[f] <- e.ty
                let res = mk (CLocal f) e.ty
                let res = if owned.Contains x then mk (CDrop(x, vtypes[x], res)) e.ty else res
                let res = if heap e.ty then mk (CDup(f, e.ty, res)) e.ty else res
                re (CLet(f, e, res))
            | CField(r, i) -> viaTemp owned borrowed r (fun v -> re (CField(v, i)))
            | CApplyClo(fe, arg) when isVar fe ->
                let x =
                    match fe.k with
                    | CLocal x -> x
                    | _ -> failwith "unreachable"

                // the closure stays alive across the argument and the call, then is released
                let arg' = rc (owned.Remove x) (borrowed.Add x) arg

                if owned.Contains x then
                    let r = tmp ()
                    vtypes[r] <- e.ty
                    re (CLet(r, re (CApplyClo(fe, arg')), mk (CDrop(x, vtypes[x], mk (CLocal r) e.ty)) e.ty))
                else
                    re (CApplyClo(fe, arg'))
            | CApplyClo(fe, arg) -> viaTemp owned borrowed fe (fun v -> re (CApplyClo(v, arg)))
            | CWhile _
            | CFor _ ->
                // loop parts run repeatedly, so they only borrow; owned variables die after the loop
                let all = Set.union owned borrowed
                let loop = re (mapChildren (rc Set.empty all) e.k)
                mk (CSeq(loop, drops owned (mk CUnit tUnit))) tUnit
            | CAssign(x, v) -> re (CAssign(x, rc owned borrowed v))
            | CTuple xs -> re (CTuple(rcList owned borrowed xs))
            | CCtor(u, tag, xs) -> re (CCtor(u, tag, rcList owned borrowed xs))
            | CCallDirect(n, xs) -> re (CCallDirect(n, rcList owned borrowed xs))
            | CExtern(n, xs) -> re (CExtern(n, rcList owned borrowed xs))
            | CPrim(n, xs) -> re (CPrim(n, rcList owned borrowed xs))
            | CMkClosure(n, xs) -> re (CMkClosure(n, rcList owned borrowed xs))
            | CBin(op, a, b) ->
                match rcList owned borrowed [ a; b ] with
                | [ a'; b' ] -> re (CBin(op, a', b'))
                | _ -> failwith "unreachable"
            | CNeg a -> re (CNeg(rc owned borrowed a))
            | CNot a -> re (CNot(rc owned borrowed a))
            | CGlobal _
            | CApp _
            | CLam _
            | CLetFun _
            | CDup _
            | CDrop _ -> failwithf "Rc: unexpected node %A" e.k

        let owned = f.pars |> List.map fst |> List.filter heapVar |> Set.ofList
        { f with body = rc owned Set.empty f.body }

    List.map rcFun funs
