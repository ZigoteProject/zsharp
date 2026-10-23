/// Type inference: Hindley-Milner with kinded variables (int literals, numeric operators),
/// let-polymorphism for top-level functions, and lowering to Core IR.
module Typer

open System.Collections.Generic
open Syntax
open Core

exception private Mismatch
exception private NoImpl of string * Ty // trait, type

let private kindOf (r: TV ref) =
    match r.Value with
    | Unbound(_, k) -> k
    | Link _ -> kAny

/// Checks whether a type implements a trait through a user impl (set by `check`), pushing the
/// impl's own requirements onto the type's arguments.
let mutable private userImpl: string -> Ty -> bool = fun _ _ -> false

/// The trait's other parameters as the impl for a type determines them (Iter on list<int>:
/// [int]), when the type's head has an impl of a trait with several (0017).
let mutable private implParams: string -> Ty -> Ty list option = fun _ _ -> None

/// Both constraints at once. Literal kinds keep only the types that also have the traits.
let private meet (a: Kind) (b: Kind) : Kind =
    let traits = Set.union a.traits b.traits
    // a trait's other parameters, which unify unifies first where both kinds have them
    let pars = Map.fold (fun (m: Map<string, Ty list>) k v -> if m.ContainsKey k then m else m.Add(k, v)) a.params b.params

    let allowed =
        match a.allowed, b.allowed with
        | None, k
        | k, None -> k
        | Some x, Some y -> Some(Set.intersect x y)

    let has tr n =
        hasBuiltinImpl tr n || userImpl tr (tcon n)

    match allowed with
    | Some s ->
        let ok = s |> Set.filter (fun n -> traits |> Set.forall (fun tr -> has tr n))

        if s.IsEmpty then
            raise Mismatch
        elif ok.IsEmpty then
            let tr = traits |> Seq.find (fun tr -> s |> Set.forall (fun n -> not (has tr n)))
            raise (NoImpl(tr, tcon (if s.Contains "int" then "int" elif s.Contains "f64" then "f64" else Seq.head s)))
        else
            { allowed = Some ok; traits = traits; params = pars }
    | None -> { allowed = None; traits = traits; params = pars }

let rec private occurs r t =
    match prune t with
    | TVar r2 -> obj.ReferenceEquals(r, r2)
    | TCon(_, ts)
    | TTuple ts -> List.exists (occurs r) ts
    | TFun(a, b, row) -> occurs r a || occurs r b || occurs r row
    | TMeas(_, vs) -> vs |> List.exists (fst >> occurs r)
    | TGen _ -> false

/// Unifies two units of measure (Kennedy): solves a/b = 1 for the variable v with the smallest
/// exponent e. When e divides every other exponent, v = rest^(-1/e). Otherwise v becomes a fresh
/// variable times rest^(-floor(k/e)), which leaves every other exponent smaller than e, and the
/// rest is solved again: so 'u^2 = 'v^3 gives 'u = 'w^3 and 'v = 'w^2. Rigid variables (a
/// generic function's own) can't be solved for; when only they are left, the units differ.
let rec private unifyMeas (a: Ty) (b: Ty) =
    let floorDiv k e = if (k % e <> 0) && ((k < 0) <> (e < 0)) then k / e - 1 else k / e

    match normMeas (measDiv a b) with
    | [], [] -> ()
    | us, vs ->
        let solvable = vs |> List.filter (fun (v, _) -> match prune v with TVar _ -> true | _ -> false)

        if solvable.IsEmpty then
            raise Mismatch

        let v, e = solvable |> List.minBy (snd >> abs)
        let others = vs |> List.filter (fun (w, _) -> not (obj.ReferenceEquals(w, v)))

        match prune v with
        | TVar r when (us |> List.forall (fun (_, k) -> k % e = 0)) && (others |> List.forall (fun (_, k) -> k % e = 0)) ->
            // v^e * rest = 1  =>  v = rest^(-1/e)
            r.Value <- Link(TMeas(us |> List.map (fun (u, k) -> u, -k / e), others |> List.map (fun (w, k) -> w, -k / e)))
        | TVar _ when solvable.Length = 1 -> raise Mismatch // v^e = units e doesn't divide (rigid variables are units here)
        | TVar r ->
            let w = fresh kAny
            r.Value <- Link(TMeas(us |> List.map (fun (u, k) -> u, -(floorDiv k e)), (w, 1) :: (others |> List.map (fun (x, k) -> x, -(floorDiv k e)))))
            unifyMeas a b
        | _ -> raise Mismatch

let private satisfies (k: Kind) t =
    let allowedOk =
        match k.allowed, t with
        | None, _ -> true
        | Some s, TCon(n, []) -> s.Contains n
        | _ -> false

    allowedOk
    && k.traits
       |> Set.forall (fun tr ->
           let ok =
               match t with
               | TCon(n, []) when hasBuiltinImpl tr n -> true
               | TCon(n, [ TMeas _ ]) when hasBuiltinImpl tr n -> true
               | _ -> userImpl tr t

           if not ok then
               raise (NoImpl(tr, t))

           true)

let rec private unify a b =
    match prune a, prune b with
    | TVar r1, TVar r2 when obj.ReferenceEquals(r1, r2) -> ()
    | TVar r1, TVar r2 ->
        // 'c : Iter<int> and 'c : Iter<'a>: one type's elements have one type
        for KeyValue(tr, ps) in (kindOf r1).params do
            match (kindOf r2).params.TryFind tr with
            | Some qs -> List.iter2 unify ps qs
            | None -> ()

        let k = meet (kindOf r1) (kindOf r2)

        match r2.Value with
        | Unbound(id, _) -> r2.Value <- Unbound(id, k)
        | Link _ -> ()

        r1.Value <- Link(TVar r2)

        // a literal's type the trait leaves one choice for ("abc" : Iter<'a>: a string, not a
        // cstr) is that type now, so the impl gives the trait's other parameters
        match k.allowed with
        | Some s when s.Count = 1 && not k.params.IsEmpty -> unify (TVar r2) (tcon (Seq.head s))
        | _ -> ()
    | TVar r, t
    | t, TVar r ->
        if occurs r t || not (satisfies (kindOf r) t) then
            raise Mismatch

        let pars = (kindOf r).params
        r.Value <- Link t

        // the impl for t's head determines the trait's other parameters
        for KeyValue(tr, ps) in pars do
            match implParams tr t with
            | Some os -> List.iter2 unify ps os
            | None -> ()
    | TCon(a, xs), TCon(b, ys) when a = b && nums.Contains a -> unifyMeas (measOf xs) (measOf ys)
    | TMeas _, _
    | _, TMeas _ -> unifyMeas a b
    | TCon(a, xs), TCon(b, ys) when a = b && xs.Length = ys.Length -> List.iter2 unify xs ys
    | TFun(a1, b1, r1), TFun(a2, b2, r2) ->
        unify a1 a2
        unify b1 b2
        unifyRow r1 r2
    | TTuple xs, TTuple ys when xs.Length = ys.Length -> List.iter2 unify xs ys
    | TGen i, TGen j when i = j -> ()
    | _ -> raise Mismatch

/// Unifies two effect rows (Leijen's scoped labels): each label of one meets the first label
/// of the other with its effect's name (their type arguments unify), and each row's tail
/// takes what's left of the other's. A closed row (no variable) can't take more.
and private unifyRow (r1: Ty) (r2: Ty) =
    match prune r1, prune r2 with
    | TVar a, TVar b when obj.ReferenceEquals(a, b) -> ()
    | TCon("$total", []), TCon("$total", []) -> ()
    // a bare variable takes the other row whole (pure code's rows are mostly these)
    | TVar v, t
    | t, TVar v ->
        if occurs v t then
            raise Mismatch

        v.Value <- Link t
    | _ -> unifyLabels r1 r2

and private unifyLabels (r1: Ty) (r2: Ty) =
    let ls1, _ = rowParts r1
    let ls2, _ = rowParts r2
    let rest1 = ResizeArray<Ty>()
    let mutable rest2 = ls2

    for l in ls1 do
        match rest2 |> List.tryFindIndex (fun m -> labelName m = labelName l) with
        | Some i ->
            match prune l, prune rest2[i] with
            | TCon(_, xs), TCon(_, ys) when xs.Length = ys.Length -> List.iter2 unify xs ys
            | _ -> raise Mismatch

            rest2 <- List.removeAt i rest2
        | None -> rest1.Add l

    let rest1 = List.ofSeq rest1
    // the tails after the labels' arguments unified, which may have linked them
    let t1 = prune (snd (rowParts r1))
    let t2 = prune (snd (rowParts r2))

    let link (v: TV ref) (row: Ty) =
        if occurs v row then
            raise Mismatch

        v.Value <- Link row

    match t1, t2 with
    | TVar v1, TVar v2 when obj.ReferenceEquals(v1, v2) -> if not (rest1.IsEmpty && rest2.IsEmpty) then raise Mismatch
    | TVar v1, TVar v2 ->
        let tail = fresh kRow
        link v1 (mkRow rest2 tail)
        link v2 (mkRow rest1 tail)
    | TVar v1, _ when rest1.IsEmpty -> link v1 (mkRow rest2 t2)
    | _, TVar v2 when rest2.IsEmpty -> link v2 (mkRow rest1 t1)
    | TCon("$total", []), TCon("$total", [])
    | TGen _, TGen _ when t1 = t2 && rest1.IsEmpty && rest2.IsEmpty -> ()
    | _ -> raise Mismatch

/// The effects a function type performs where the other one, of the same shape, can't: the
/// labels of its rows that the other's closed rows lack ([] when the shapes differ or none).
let rec private extraEffects (expected: Ty) (actual: Ty) : Ty list =
    match prune expected, prune actual with
    | TFun(a1, b1, r1), TFun(a2, b2, r2) ->
        let here =
            match rowParts r1 with
            | ls, t when (match prune t with
                          | TCon("$total", []) -> true
                          | _ -> false) ->
                fst (rowParts r2) |> List.filter (fun l -> not (ls |> List.exists (fun m -> labelName m = labelName l)))
            | _ -> []

        here @ extraEffects a1 a2 @ extraEffects b1 b2
    | TCon(n, xs), TCon(m, ys) when n = m && xs.Length = ys.Length -> List.collect id (List.map2 extraEffects xs ys)
    | TTuple xs, TTuple ys when xs.Length = ys.Length -> List.collect id (List.map2 extraEffects xs ys)
    | _ -> []

let private showEffects (ls: Ty list) = ls |> List.map show |> List.distinct |> String.concat ", "

let private expect what expected actual =
    try
        unify expected actual
    with
    | Mismatch ->
        // what newcomers write: a literal is a kinded variable, so the names are compared as shown
        let hint =
            match prune expected, prune actual with
            | TCon("array", _), TCon("span", _) -> ": Array.ofSpan copies it"
            | e, a when not (extraEffects e a).IsEmpty ->
                sprintf ": this function performs %s, and one without it is expected here" (showEffects (extraEffects e a))
            | _ ->
                match show expected, show actual with
                | e, a when nums.Contains e && nums.Contains a -> sprintf ": numbers don't convert on their own; write %s x" e
                | "string", a when nums.Contains a -> ": interpolate it, $\"{x}\""
                | "char", "string" -> ": a char literal is 'a', in single quotes"
                | "bool", a when nums.Contains a -> ": a number isn't a condition; compare it, x <> 0"
                | _ -> ""

        fail 0 (sprintf "%s: expected %s, got %s%s" what (show expected) (show actual) hint)
    | NoImpl("Share", t) -> fail 0 (sprintf "%s: %s can't be shared between threads (it isn't Share)" what (show t))
    | NoImpl(tr, t) ->
        let tuple =
            match prune t with
            | TTuple xs when what.StartsWith "argument 1 of '" ->
                let f = what.Substring(15).TrimEnd('\'')
                sprintf "; if '%s' takes its %d arguments one by one, write %s a b, not %s (a, b)" f xs.Length f f
            | TCon _ when tr = "Iter" ->
                sprintf "; list, array, Buffer, span, string, option, Map, Set, HashMap, Seq and Range do, and impl Iter<%s, <element>> = let forEach c f = … adds yours" (show t)
            | TCon _ when not (List.contains tr [ "Share"; "Eq"; "Ord"; "Hash"; "Show"; "Add"; "Num" ]) ->
                sprintf "; write impl %s<%s> = …" tr (show t)
            | _ -> ""

        fail 0 (sprintf "%s: %s does not implement %s%s" what (show t) tr tuple)

/// The function types along a type's results: its own and, when it returns a function, that
/// one's, and so on (where a row may be closed or opened without changing what's accepted).
let rec private spine (t: Ty) : Ty list =
    match prune t with
    | TFun(_, b, _) as f -> f :: spine b
    | _ -> []

/// The rule a function must keep where none of its effects can be handled (given to C, run on
/// another thread): expected has none, actual is the function; an error says what it performs.
let private expectNoEffects (rule: Printf.StringFormat<string -> string>) (what: string) (expected: Ty) (actual: Ty) =
    match extraEffects expected actual with
    | [] -> expect what expected actual
    | ls -> fail 0 (sprintf rule (showEffects ls))

/// Quantifies the unbound variables of a top-level function's type (linking them to TGen):
/// type variables first, then rows, so 'a, 'b name the types and 'e the effects. First a row
/// variable that only ends one of the rows along the result spine is closed (it stands for no
/// effects there: `unit -> unit / Yield<int>`, not `/ <Yield<int> | 'e>`); a reference opens it
/// again (Koka's close and open).
let private generalize (t: Ty) : Kind list =
    let rec count (v: TV ref) (t: Ty) =
        match prune t with
        | TVar r -> if obj.ReferenceEquals(r, v) then 1 else 0
        | TCon(_, ts)
        | TTuple ts -> List.sumBy (count v) ts
        | TFun(a, b, row) -> count v a + count v b + count v row
        | TMeas(_, vs) -> vs |> List.sumBy (fst >> count v)
        | TGen _ -> 0

    let spines =
        match prune t with
        | TTuple ts -> List.collect spine ts // a group of functions calling each other
        | _ -> spine t

    for f in spines do
        match f with
        | TFun(_, _, row) ->
            match prune (snd (rowParts row)) with
            | TVar v when count v t = 1 -> v.Value <- Link rowEmpty
            | _ -> ()
        | _ -> ()

    let found = ResizeArray<TV ref * Kind>()

    let rec go t =
        match prune t with
        | TVar r ->
            match r.Value with
            | Unbound(_, k) when not (found.Exists(fun (r2, _) -> obj.ReferenceEquals(r, r2))) ->
                found.Add(r, k)
                // what a trait's other parameters mention is the scheme's too ('c : Iter<'a>)
                for ps in k.params.Values do
                    List.iter go ps
            | _ -> ()
        | TCon(_, ts)
        | TTuple ts -> List.iter go ts
        | TFun(a, b, row) ->
            go a
            go b
            go row
        | TMeas(_, vs) -> vs |> List.iter (fst >> go)
        | TGen _ -> ()

    go t
    let types, rows = found |> List.ofSeq |> List.partition (fun (_, k) -> not (isRowKind k))
    let ordered = types @ rows
    ordered |> List.iteri (fun i (r, _) -> r.Value <- Link(TGen i))
    ordered |> List.map (fun (_, k) -> { k with params = k.params |> Map.map (fun _ ps -> List.map resolve ps) })

/// A function type taking ps, without effects.
let private funTy (ps: Ty list) (ret: Ty) = List.foldBack tfun ps ret

/// A function type taking ps whose body performs row: the last arrow has it, the others none
/// (giving a function some of its arguments does nothing).
let private funTyRow (ps: Ty list) (ret: Ty) (row: Ty) =
    match List.rev ps with
    | [] -> ret
    | last :: before -> List.fold (fun acc p -> tfun p acc) (TFun(last, ret, row)) before

/// Splits a function type into its first n parameter types and the rest.
let rec private peel n t =
    match n, prune t with
    | 0, t -> [], t
    | n, TFun(a, b, _) ->
        let ps, r = peel (n - 1) b
        a :: ps, r
    | _ -> failwith "peel: not a function type"

type private Builtin =
    { prim: string
      kinds: Kind list
      ty: Ty
      arity: int }

/// The functions on SIMD vectors and masks (DESIGN §8), a module per type (F32x4.splat,
/// Mask8.any), built into the compiler: b makes each one's entry.
let private simdBuiltins (b: string -> string -> Kind list -> Ty -> int -> string * Builtin) =
    let f x y = tfun x y

    [ for n, e, k in vectorTypes do
          let v, et, m = tcon n, tcon e, simdModule n
          let mask = tcon (sprintf "mask%d" k)
          let arr = TCon("array", [ et ])
          b (m + ".splat") "vec.splat" [] (f et v) 1
          b (m + ".load") "vec.load" [] (f (TCon("span", [ et ])) (f tInt v)) 2
          b (m + ".store") "vec.store" [] (f arr (f tInt (f v arr))) 3
          b (m + ".get") "vec.get" [] (f v (f tInt et)) 2
          b (m + ".set") "vec.set" [] (f v (f tInt (f et v))) 3
          b (m + ".init") "vec.init" [] (f (f tInt et) v) 1
          b (m + ".sum") "vec.sum" [] (f v et) 1
          b (m + ".min") "vec.min" [] (f v (f v v)) 2
          b (m + ".max") "vec.max" [] (f v (f v v)) 2
          b (m + ".reduceMin") "vec.reduceMin" [] (f v et) 1
          b (m + ".reduceMax") "vec.reduceMax" [] (f v et) 1
          b (m + ".abs") "vec.abs" [] (f v v) 1

          for c in [ "equal"; "notEqual"; "lessThan"; "lessOrEqual"; "greaterThan"; "greaterOrEqual" ] do
              b (m + "." + c) ("vec." + c) [] (f v (f v mask)) 2

          b (m + ".select") "vec.select" [] (f mask (f v (f v v))) 3
          b (m + ".shuffle") "vec.shuffle" [] (f v (f v (f (TCon("array", [ tInt ])) v))) 3

          if floats.Contains e then
              for g in [ "sqrt"; "floor"; "ceil"; "round" ] do
                  b (m + "." + g) ("vec." + g) [] (f v v) 1

              b (m + ".mulAdd") "vec.mulAdd" [] (f v (f v (f v v))) 3

          // from the other vectors with as many lanes, lane by lane
          for n2, _, k2 in vectorTypes do
              if k2 = k && n2 <> n then
                  b (m + ".of" + simdModule n2) "vec.convert" [] (f (tcon n2) v) 1
      for name, intr, ps, r, _ in simdIntrinsics do
          b name ("llvm:" + intr) [] (List.foldBack (fun p acc -> f (tcon p) acc) ps (tcon r)) ps.Length
      for mn, _ in maskTypes do
          let mt, mm = tcon mn, simdModule mn
          b (mm + ".any") "mask.any" [] (f mt tBool) 1
          b (mm + ".all") "mask.all" [] (f mt tBool) 1
          b (mm + ".count") "mask.count" [] (f mt tInt) 1
          b (mm + ".not") "mask.not" [] (f mt mt) 1
          b (mm + ".get") "mask.get" [] (f mt (f tInt tBool)) 2 ]

let private builtins =
    let a = TGen 0
    let f x y = tfun x y
    let atomic, mutex, channel = TCon("Atomic", [ a ]), TCon("Mutex", [ a ]), TCon("Channel", [ a ])
    let kAtomic = { kAny with allowed = Some(nums + set [ "bool"; "char" ]) }
    let kShare = kTrait "Share"

    let b name prim kinds ty arity =
        name,
        { prim = prim
          kinds = kinds
          ty = ty
          arity = arity }

    dict (
        [ b "ignore" "ignore" [ kAny ] (f a tUnit) 1
          b "panic" "panic" [ kAny ] (f tStr a) 1
          b "failwith" "panic" [ kAny ] (f tStr a) 1
          b "assert" "assert" [] (f tBool tUnit) 1
          b "print" "print" [] (f tStr tUnit) 1
          b "println" "println" [] (f tStr tUnit) 1
          b "Text.String.length" "String.length" [] (f tStr tInt) 1
          b "Text.String.ofCStr" "String.ofCStr" [] (f tCStr tStr) 1
          b "Text.String.sub" "String.sub" [] (f tStr (f tInt (f tInt tStr))) 3
          b "Text.String.byte" "String.byte" [] (f tStr (f tInt (tcon "u8"))) 2
          b "Text.String.ofByte" "String.ofByte" [] (f (tcon "u8") tStr) 1
          b "Text.String.indexOfFrom" "String.indexOfFrom" [] (f tStr (f tStr (f tInt tInt))) 3
          b "Text.String.trim" "String.trim" [] (f tStr tStr) 1
          b "Text.String.toUpper" "String.toUpper" [] (f tStr tStr) 1
          b "Text.String.toLower" "String.toLower" [] (f tStr tStr) 1
          b "Text.String.replace" "String.replace" [] (f tStr (f tStr (f tStr tStr))) 3
          b "Text.String.isFloat" "String.isFloat" [] (f tStr tBool) 1
          b "Native.parseInt" "int.parse" [ kInt ] (f tInt (f tStr (TTuple [ tBool; a ]))) 2
          b "Native.parseFloat" "float.parse" [ kFloat ] (f tStr (TTuple [ tBool; a ])) 1
          b "Float.toBits" "float.toBits" [] (f (tcon "f64") (tcon "u64")) 1
          b "Float.ofBits" "float.ofBits" [] (f (tcon "u64") (tcon "f64")) 1
          b "Native.clockRealtime" "Clock.realtime" [] (f tUnit (tcon "i64")) 1
          b "Native.fileOpen" "File.open" [] (f tStr (f tInt tInt)) 2
          b "Native.fileModified" "File.mtime" [] (f tStr (tcon "i64")) 1
          b "Native.fileSize" "File.size" [] (f tStr (tcon "i64")) 1
          b "Native.fileTouch" "File.touch" [] (f tStr tUnit) 1
          b "Native.fileCopy" "File.copy" [] (f tStr (f tStr tUnit)) 2
          b "Native.fileMove" "File.move" [] (f tStr (f tStr tUnit)) 2
          b "Native.tempFile" "File.temp" [] (f tStr tStr) 1
          b "Native.tempDirectory" "Dir.temp" [] (f tStr tStr) 1
          b "Native.deleteDirectory" "Dir.delete" [] (f tStr tUnit) 1
          b "Native.isSymlink" "File.isSymlink" [] (f tStr tBool) 1
          b "Native.currentDirectory" "Env.cwd" [] (f tUnit tStr) 1
          b "Native.processStart" "Process.start" [] (f tStr (f tStr (f tStr (f tBool (f tStr (f tInt (f tInt (f tInt tInt)))))))) 8
          b "Native.processPipe" "Process.pipe" [] (f tInt tInt) 1
          b "Native.processWait" "Process.wait" [] (f tInt tInt) 1
          b "Native.processKill" "Process.kill" [] (f tInt tInt) 1
          b "Native.unixListen" "Unix.listen" [] (f tStr tInt) 1
          b "Native.unixConnect" "Unix.connect" [] (f tStr tInt) 1
          b "Text.String.toFloat" "String.toFloat" [] (f tStr (tcon "f64")) 1
          b "Native.readLine" "Console.readLineRaw" [] (f tUnit tStr) 1
          b "Native.eof" "Console.eof" [] (f tUnit tBool) 1
          b "eprintln" "eprintln" [] (f tStr tUnit) 1
          b "ref" "ref" [ kAny ] (f a (TCon("ref", [ a ]))) 1
          b "Collections.Array.create" "Array.create" [ kAny ] (f tInt (f a (TCon("array", [ a ])))) 2
          b "Collections.Array.set" "array.update" [ kAny ] (f (TCon("array", [ a ])) (f tInt (f a (TCon("array", [ a ]))))) 3
          b "Collections.Buffer.create" "Array.create" [ kAny ] (f tInt (f a (TCon("Buffer", [ a ])))) 2
          b "Collections.Buffer.length" "Array.length" [ kAny ] (f (TCon("Buffer", [ a ])) tInt) 1
          b "Collections.Buffer.push" "buffer.push" [ kAny ] (f a (f (TCon("Buffer", [ a ])) tUnit)) 2
          b "Collections.Buffer.removeLast" "buffer.removeLast" [ kAny ] (f (TCon("Buffer", [ a ])) a) 1
          b "Collections.Buffer.truncate" "buffer.truncate" [ kAny ] (f tInt (f (TCon("Buffer", [ a ])) tUnit)) 2
          b "Collections.Buffer.blit" "buffer.blit" [ kAny ] (f (TCon("span", [ a ])) (f tInt (f (TCon("Buffer", [ a ])) (f tInt (f tInt tUnit))))) 5
          b "Collections.Array.copy" "array.copy" [ kAny ] (f (TCon("array", [ a ])) (TCon("array", [ a ]))) 1
          b "Collections.Buffer.ofArray" "array.copy" [ kAny ] (f (TCon("array", [ a ])) (TCon("Buffer", [ a ]))) 1
          b "Collections.Buffer.toArray" "array.copy" [ kAny ] (f (TCon("span", [ a ])) (TCon("array", [ a ]))) 1
          b "Collections.Buffer.ofSpan" "array.copy" [ kAny ] (f (TCon("span", [ a ])) (TCon("Buffer", [ a ]))) 1
          b "Collections.Array.ofSpan" "array.copy" [ kAny ] (f (TCon("span", [ a ])) (TCon("array", [ a ]))) 1
          b "Collections.Span.length" "Array.length" [ kAny ] (f (TCon("span", [ a ])) tInt) 1
          b "Collections.Fixed.length" "fixed.length" [ kAny; kAny ] (f (TCon("fixed", [ a; TGen 1 ])) tInt) 1
          b "Collections.Fixed.get" "fixed.get" [ kAny; kAny ] (f (TCon("fixed", [ a; TGen 1 ])) (f tInt a)) 2
          b "Collections.Fixed.set" "fixed.set" [ kAny; kAny ] (f (TCon("fixed", [ a; TGen 1 ])) (f tInt (f a (TCon("fixed", [ a; TGen 1 ]))))) 3
          b "Collections.Fixed.create" "fixed.create" [ kAny; kAny ] (f a (TCon("fixed", [ a; TGen 1 ]))) 1
          b "Collections.Fixed.ofArray" "fixed.ofArray" [ kAny; kAny ] (f (TCon("span", [ a ])) (TCon("fixed", [ a; TGen 1 ]))) 1
          b "Collections.Span.ofPtr" "span.ofPtr" [ kAny ] (f (TCon("ptr", [ a ])) (f tInt (TCon("span", [ a ])))) 2
          b "Text.String.bytes" "span.ofString" [] (f tStr (TCon("span", [ tcon "u8" ]))) 1
          b "Text.String.ofBytes" "String.ofBytes" [] (f (TCon("span", [ tcon "u8" ])) tStr) 1
          b "Int.wrappingAdd" "wrap+" [ kInt ] (f a (f a a)) 2
          b "Int.wrappingSub" "wrap-" [ kInt ] (f a (f a a)) 2
          b "Int.wrappingMul" "wrap*" [ kInt ] (f a (f a a)) 2
          b "Runtime.allocations" "Runtime.allocations" [] (f tUnit tInt) 1
          b "Environment.exit" "Process.exit" [ kAny ] (f tInt a) 1
          b "Mmio.read32" "mmio.read.u32" [] (f (tcon "usize") (tcon "u32")) 1
          b "Mmio.write32" "mmio.write.u32" [] (f (tcon "usize") (f (tcon "u32") tUnit)) 2
          b "Mmio.read8" "mmio.read.u8" [] (f (tcon "usize") (tcon "u8")) 1
          b "Mmio.write8" "mmio.write.u8" [] (f (tcon "usize") (f (tcon "u8") tUnit)) 2
          b "Runtime.ticks" "Runtime.ticks" [] (f tUnit (tcon "u64")) 1
          b "Math.sqrt" "Math.sqrt" [ kFloat ] (f a a) 1
          b "Ptr.read" "ptr.read" [ kAny ] (f (TCon("ptr", [ a ])) a) 1
          b "Ptr.write" "ptr.write" [ kAny ] (f (TCon("ptr", [ a ])) (f a tUnit)) 2
          b "Ptr.add" "ptr.add" [ kAny ] (f (TCon("ptr", [ a ])) (f tInt (TCon("ptr", [ a ])))) 2
          b "Ptr.null" "ptr.null" [ kAny ] (f tUnit (TCon("ptr", [ a ]))) 1
          b "Ptr.isNull" "ptr.isNull" [ kAny ] (f (TCon("ptr", [ a ])) tBool) 1
          b "Ptr.alloc" "ptr.alloc" [ kAny ] (f tInt (TCon("ptr", [ a ]))) 1
          b "Ptr.free" "ptr.free" [ kAny ] (f (TCon("ptr", [ a ])) tUnit) 1
          b "Ptr.ofCPtr" "ptr.cast" [ kAny ] (f (tcon "cptr") (TCon("ptr", [ a ]))) 1
          b "Ptr.toCPtr" "ptr.cast" [ kAny ] (f (TCon("ptr", [ a ])) (tcon "cptr")) 1
          b "Ptr.cast" "ptr.cast" [ kAny; kAny ] (f (TCon("ptr", [ a ])) (TCon("ptr", [ TGen 1 ]))) 1
          b "Weak.create" "weak.new" [ kAny ] (f a (TCon("weak", [ a ]))) 1
          b "Weak.get" "weak.get" [ kAny ] (f (TCon("weak", [ a ])) (TCon("option", [ a ]))) 1
          b "Arena.with" "arena.with" [ kAny ] (f (f tUnit a) a) 1
          b "Runtime.mallocs" "Runtime.mallocs" [] (f tUnit tInt) 1
          b "Runtime.marks" "Runtime.marks" [] (f tUnit tInt) 1
          // the thread pool (runtime/rt.c), which Std's Parallel wraps: a job runs a function
          // that crossed threads, and its result comes back to the thread that joins it
          b "Native.parFork" "par.fork" [ kAny ] (f (TCon("share", [ f tUnit a ])) tCPtr) 1
          b "Native.parJoin" "par.join" [ kAny ] (f tCPtr a) 1
          b "Native.parWorkers" "par.workers" [] (f tUnit tInt) 1
          // what threads share (Std's Threading): an Atomic holds a number, bool or char, a Mutex
          // and a Channel any value that can be shared
          b "Threading.Atomic.make" "atomic.make" [ kAtomic ] (f a atomic) 1
          b "Threading.Atomic.get" "atomic.get" [ kAtomic ] (f atomic a) 1
          b "Threading.Atomic.set" "atomic.set" [ kAtomic ] (f atomic (f a tUnit)) 2
          b "Threading.Atomic.exchange" "atomic.exchange" [ kAtomic ] (f atomic (f a a)) 2
          b "Threading.Atomic.compareExchange" "atomic.cas" [ kAtomic ] (f atomic (f a (f a a))) 3
          b "Threading.Atomic.add" "atomic.add" [ kNumeric ] (f atomic (f a a)) 2
          b "Threading.Mutex.make" "mutex.make" [ kShare ] (f a mutex) 1
          b "Threading.Mutex.get" "mutex.get" [ kShare ] (f mutex a) 1
          b "Threading.Mutex.set" "mutex.set" [ kShare ] (f mutex (f a tUnit)) 2
          b "Threading.Mutex.update" "mutex.update" [ kShare ] (f mutex (f (f a a) a)) 2
          b "Threading.Channel.make" "chan.make" [ kShare ] (f tInt channel) 1
          b "Threading.Channel.send" "chan.send" [ kShare ] (f channel (f a tUnit)) 2
          b "Threading.Channel.receive" "chan.receive" [ kShare ] (f channel (TCon("option", [ a ]))) 1
          b "Threading.Channel.close" "chan.close" [ kShare ] (f channel tUnit) 1
          // the event loop and sockets (runtime/rt.c), which Std's Task and Tcp wrap
          b "Native.loopPost" "Loop.post" [] (f (f tUnit tUnit) tUnit) 1
          b "Native.loopWait" "Loop.wait" [] (f tInt (f tBool (f (f tUnit tUnit) tUnit))) 3
          b "Native.loopUnwait" "Loop.unwait" [] (f tInt (f tBool tUnit)) 2
          b "Native.loopTimer" "Loop.timer" [] (f tInt (f (f tUnit tUnit) tInt)) 2
          b "Native.loopUntimer" "Loop.untimer" [] (f tInt tUnit) 1
          b "Native.loopStep" "Loop.step" [] (f tUnit tBool) 1
          b "Native.loopClose" "Loop.close" [] (f tUnit tUnit) 1
          b "Native.loopEnter" "Loop.enter" [] (f tUnit tBool) 1
          b "Native.loopLeave" "Loop.leave" [] (f tUnit tUnit) 1
          b "Native.loopBlocking" "Loop.blocking" [] (f (TCon("share", [ f tUnit tUnit ])) (f (f tUnit tUnit) tUnit)) 2
          // tasks on other threads' loops (Task.spawn): the token says which loop gets a result
          b "Native.loopSpawn" "Loop.spawn" [] (f (TCon("share", [ f tUnit tUnit ])) tUnit) 1
          b "Native.loopExpect" "Loop.expect" [] (f (f tUnit tUnit) tInt) 1
          b "Native.loopFulfill" "Loop.fulfill" [] (f tInt tUnit) 1
          b "Native.tcpListen" "Tcp.listen" [] (f tStr (f tInt tInt)) 2
          b "Native.tcpAccept" "Tcp.accept" [] (f tInt tInt) 1
          b "Native.tcpConnect" "Tcp.connect" [] (f tStr (f tInt tInt)) 2
          b "Native.socketError" "Tcp.error" [] (f tInt tInt) 1
          b "Native.fdRead" "Fd.read" [] (f tInt (f (TCon("Buffer", [ tcon "u8" ])) (f tInt (f tInt tInt)))) 4
          b "Native.fdWrite" "Fd.write" [] (f tInt (f (TCon("Buffer", [ tcon "u8" ])) (f tInt (f tInt tInt)))) 4
          b "Native.fdWriteText" "Fd.write" [] (f tInt (f tStr (f tInt (f tInt tInt)))) 4
          b "Native.fdClose" "Fd.close" [] (f tInt tUnit) 1
          b "Native.errorText" "Errno.text" [] (f tInt tStr) 1
          b "Native.argc" "Env.argc" [] (f tUnit tInt) 1
          b "Native.arg" "Env.arg" [] (f tInt tStr) 1
          b "Native.hasVariable" "Env.has" [] (f tStr tBool) 1
          b "Native.getVariable" "Env.get" [] (f tStr tStr) 1
          b "Native.ioOk" "Io.ok" [] (f tUnit tBool) 1
          b "Native.ioError" "Io.error" [] (f tUnit tStr) 1
          b "Native.readFile" "File.readRaw" [] (f tStr tStr) 1
          b "Native.writeFile" "File.writeRaw" [] (f tStr (f tStr tUnit)) 2
          b "Native.appendFile" "File.appendRaw" [] (f tStr (f tStr tUnit)) 2
          b "IO.File.exists" "File.exists" [] (f tStr tBool) 1
          b "Native.deleteFile" "File.deleteRaw" [] (f tStr tUnit) 1
          b "IO.Directory.exists" "Dir.exists" [] (f tStr tBool) 1
          b "Native.createDirectory" "Dir.createRaw" [] (f tStr tUnit) 1
          b "Native.listDirectory" "Dir.listRaw" [] (f tStr tStr) 1
          b "Native.runProcess" "Process.runRaw" [] (f tStr (f tStr tStr)) 2
          b "Native.exitCode" "Process.code" [] (f tUnit tInt) 1
          b "Collections.Array.length" "Array.length" [ kAny ] (f (TCon("span", [ a ])) tInt) 1 ]
        @ [ for t in Seq.append nums [ "float"; "c_int" ] ->
                let target =
                    match typeAliases.TryGetValue t with
                    | true, c -> c
                    | _ -> t

                b t "conv" [ kConvertible ] (f a (tcon target)) 1 ]
        @ [ b "char" "conv" [ kIntOrChar ] (f a tChar) 1 ]
        @ simdBuiltins b
    )

/// The built-in functions only `unsafe` code may call: raw memory through ptr<T>.
let private unsafeBuiltins = set [ "Ptr.read"; "Ptr.write"; "Ptr.add"; "Ptr.alloc"; "Ptr.free"; "Ptr.ofCPtr"; "Ptr.cast"; "Collections.Span.ofPtr" ]

/// Builtins over arrays that take a span and read an array, a Buffer or a span alike: an
/// argument converted to a span for them is passed as it is (Codegen reads all three).
let private overWindows = set [ "Array.length"; "array.copy"; "vec.load"; "fixed.ofArray" ]

type private Local =
    { u: string // unique name in Core
      ty: Ty
      mut: bool
      depth: int } // closure nesting depth where it is bound

type MemberInfo =
    { gname: string // the function implementing it
      isStatic: bool
      isProperty: bool
      mpars: MemberParam list }

type Global =
    { mutable ty: Ty
      mutable kinds: Kind list
      arity: int
      mutable defining: bool }

/// One of the checker's tables (State): a dictionary that also remembers the keys written since
/// its last mark. Those are what a module added or changed: the module's result, which the
/// cache keeps and a later build writes back instead of checking the module again.
type Table<'k, 'v when 'k: equality>(cmp: IEqualityComparer<'k>) =
    let d = Dictionary<'k, 'v>(cmp)
    let written = HashSet<'k>(cmp)
    let order = ResizeArray<'k>()

    new() = Table<'k, 'v>(HashIdentity.Structural)

    member _.Item
        with get (k: 'k) = d[k]
        and set (k: 'k) (v: 'v) =
            if written.Add k then
                order.Add k

            d[k] <- v

    member _.TryGetValue(k: 'k, [<System.Runtime.InteropServices.Out>] v: byref<'v>) = d.TryGetValue(k, &v)
    member _.ContainsKey(k: 'k) = d.ContainsKey k
    member _.Remove(k: 'k) = d.Remove k // only after an error, when nothing of the module is kept
    member _.Count = d.Count
    member _.Keys = d.Keys
    member _.Values = d.Values
    member _.Dict = d
    /// The keys written since the last mark, in the order first written (still there).
    member _.Written = order |> Seq.filter d.ContainsKey
    member _.Mark() =
        written.Clear()
        order.Clear()

    interface IEnumerable<KeyValuePair<'k, 'v>> with
        member _.GetEnumerator() : IEnumerator<KeyValuePair<'k, 'v>> = (d :> IEnumerable<_>).GetEnumerator()

    interface System.Collections.IEnumerable with
        member _.GetEnumerator() : System.Collections.IEnumerator = (d :> System.Collections.IEnumerable).GetEnumerator()

/// A set of the checker's state that remembers what was added since its last mark (as Table).
type Bag<'a when 'a: equality>() =
    let s = HashSet<'a>(HashIdentity.Structural)
    let added = ResizeArray<'a>()

    member _.Add(x: 'a) =
        if s.Add x then
            added.Add x
            true
        else
            false

    member _.Contains(x: 'a) = s.Contains x
    member _.Count = s.Count
    member _.Set = s
    member _.Added = added :> seq<'a>
    member _.Mark() = added.Clear()

    interface IEnumerable<'a> with
        member _.GetEnumerator() : IEnumerator<'a> = (s :> IEnumerable<_>).GetEnumerator()

    interface System.Collections.IEnumerable with
        member _.GetEnumerator() : System.Collections.IEnumerator = (s :> System.Collections.IEnumerable).GetEnumerator()

/// What checking a program's modules has built so far: everything the modules after them can
/// see. A module's result is what it wrote here (each table's Written, the lists' new items):
/// Snapshot writes it per module, and writes it back into the state of a later check.
type State =
    { types: Table<string, TypeInfo>
      ctors: Table<string, string * int> // constructor -> union, tag
      records: ResizeArray<string> // record types in declaration order
      recordDefaults: Table<string, Expr option list> // record -> default per field
      ctorFieldNames: Table<string, string option list> // constructor -> field names
      members: Table<string, (string * MemberInfo) list> // type -> its members, in declaration order
      memberTypeNames: Bag<string> // the last part of each type in members, a quick test for staticMember
      traitMethods: Table<string, TraitMethod> // "Show.show" -> method
      traitAliases: Table<string, string> // "show" -> "Show.show"; "M.describe" -> "M.Describe.describe"
      traitNames: Bag<string> // by full name: Show, or M.Describe declared in module M
      effects: Table<string, EffectInfo> // by full name
      effectOps: Table<string, string * int> // "Yield.yield" -> the effect, the operation's index
      impls: Table<string * string, Dictionary<string, string>> // (trait, type) -> method -> function
      implRequires: Table<string * string, Set<string> list> // traits each type argument needs
      implOthers: Table<string * string, Ty list> // a trait's other parameters, over the head's variables (0017)
      derives: Table<string, (int * string * Param list * SType option * Expr) list> // by full name, as traits
      deriveGroups: Table<string, string list> // derive Json = ToJson, FromJson: by full name, the members'
      aliases: Table<string, int * Ty> // type Duration = i64<ns>: by full name, its parameters' count and what it names (TGen i the i-th)
      deriveModules: Table<string, string option> // derive -> the module declaring it
      // active pattern case -> (function, total?, number of parameters before the value)
      activePatterns: Table<string, string * bool * int>
      apCtors: Bag<string> // cases of total active patterns: payload optional
      autoDerived: Bag<string * string> // automatic derives made so far
      optOut: Bag<string * string> // [<NoEquality>] / [<NoComparison>]
      globals: Table<string, Global>
      externs: Table<string, ExternSig>
      funs: ResizeArray<FunDef>
      counter: int ref // for unique names, from 0 in each module (so a module's names are its own)
      measures: Bag<string> // [<Measure>] types
      clayouts: Bag<string> // [<CLayout>] records
      targets: Table<string, string list> // [<Target>] and [<Multiversion>] functions (Program.targets)
      exports: ResizeArray<Export>
      tests: ResizeArray<string>
      consts: Table<string, Expr> // constants (top-level and from import c): their uses are the expression
      globalValues: Table<string, Ty> // top-level values computed at startup
      valueList: ResizeArray<string * string> // in initialization order: name, init function
      literalRecords: Table<Expr, string> // record literal -> the record it built (a constant's, rechecked at each use)
      privates: Table<string, string option> // qualified name -> owning module
      moduleNames: Bag<string> // files' and nested modules, and the namespaces they are in
      mainNested: Bag<string> // modules nested in the main file (it has no module name)
      nestedModules: Bag<string> // every `module X =` so far, to catch a second one
      enclosingOf: Table<string, string list> } // each module's enclosing modules, innermost first

let private freshState () =
    { types =
        let t = Table()
        t[windowType] <- windowDef // what a span is after monomorphization
        t[bufferType] <- bufferDef // and a Buffer, in a ref
        t
      ctors = Table()
      records = ResizeArray()
      recordDefaults = Table()
      ctorFieldNames = Table()
      members = Table()
      memberTypeNames = Bag()
      traitMethods = Table()
      traitAliases = Table()
      traitNames = Bag()
      effects = Table()
      effectOps = Table()
      impls = Table()
      implRequires = Table()
      implOthers = Table()
      derives = Table()
      deriveGroups = Table()
      aliases = Table()
      deriveModules = Table()
      activePatterns = Table()
      apCtors = Bag()
      autoDerived = Bag()
      optOut = Bag()
      globals = Table()
      externs = Table()
      funs = ResizeArray()
      counter = ref 0
      measures = Bag()
      clayouts = Bag()
      targets = Table()
      exports = ResizeArray()
      tests = ResizeArray()
      consts = Table()
      globalValues = Table()
      valueList = ResizeArray()
      literalRecords = Table(HashIdentity.Reference)
      privates = Table()
      moduleNames = Bag()
      mainNested = Bag()
      nestedModules = Bag()
      enclosingOf = Table() }

/// Where a module's result starts in the state's lists (and the checker's hovers).
type Marks =
    { records: int
      funs: int
      exports: int
      tests: int
      valueList: int
      hovers: int }

/// Starts a module's result: every table and set forgets what it was written before.
let markState (st: State) =
    st.types.Mark()
    st.ctors.Mark()
    st.recordDefaults.Mark()
    st.ctorFieldNames.Mark()
    st.members.Mark()
    st.memberTypeNames.Mark()
    st.traitMethods.Mark()
    st.traitAliases.Mark()
    st.traitNames.Mark()
    st.effects.Mark()
    st.effectOps.Mark()
    st.impls.Mark()
    st.implRequires.Mark()
    st.implOthers.Mark()
    st.derives.Mark()
    st.deriveGroups.Mark()
    st.aliases.Mark()
    st.deriveModules.Mark()
    st.activePatterns.Mark()
    st.apCtors.Mark()
    st.autoDerived.Mark()
    st.optOut.Mark()
    st.globals.Mark()
    st.externs.Mark()
    st.measures.Mark()
    st.clayouts.Mark()
    st.targets.Mark()
    st.consts.Mark()
    st.globalValues.Mark()
    st.literalRecords.Mark()
    st.privates.Mark()
    st.moduleNames.Mark()
    st.mainNested.Mark()
    st.nestedModules.Mark()
    st.enclosingOf.Mark()

/// modules: (file, module name, declarations) in dependency order; the prelude and the main
/// file have no module name (their declarations are global).
/// collect: report every declaration's error (editors) instead of stopping at the first.
/// The type of a function built into the compiler, by full name (for `zs doc`).
let builtinType (name: string) =
    match builtins.TryGetValue name with
    | true, b -> Some b.ty
    | _ -> None

/// Modules the target doesn't have, by full name (Std's on a microcontroller, set by the
/// driver): a name in one is reported as such rather than as unknown.
let unavailable = HashSet<string>()

/// Operators on numbers and booleans: pure, as fusion takes them.
let private pureOps =
    set [ "+"; "-"; "*"; "/"; "%"; "="; "<>"; "<"; ">"; "<="; ">="; "&&"; "||"; "&&&"; "|||"; "^^^"; "<<<"; ">>>" ]

/// The top-level definition being checked, for the error on a function that calls itself without `rec`.
let mutable private currentDef = ""

/// The error for a name nothing defines; the names F# and C programmers reach for first say what Z# has instead.
let private unknown (what: string) (x: string) =
    let inModule (m: string) = [ m; shortName m ] |> List.exists (fun p -> x.StartsWith(p + "."))

    match unavailable |> Seq.tryFind inModule with
    | Some m -> fail 0 (sprintf "'%s' is in %s, part of Std, which needs an operating system; this target has none" x m)
    | None when x = "!" -> fail 0 "'!' isn't an operator: write not x (F#'s !r is r.Value)"
    | None when x = "printfn" || x = "printf" || x = "eprintfn" ->
        fail 0 (sprintf "there's no %s: print with println $\"…{x}…\" (print for no newline, Console.Error.writeLine for errors)" x)
    | None when x = "sprintf" || x = "failwithf" -> fail 0 (sprintf "there's no %s: interpolate, $\"…{x}…\"" x)
    | None when x = "raise" || x = "reraise" ->
        fail 0 "there's no raise: return a result (Error e) for the caller to match on, throw a typed exception (Throw.throw e, caught by Throw.catch), or panic for a bug"
    | None when x = "null" || x = "NULL" -> fail 0 "there's no null: a missing value is None, of type option<'a>"
    | None when x = "return" ->
        fail 0 "return belongs in a computation expression (task { }, result { }); a function's last expression is its result"
    | None when x = "async" || x.StartsWith "Async." -> fail 0 "there's no Async: write task { }, and run it with Task.run"
    | None when x = currentDef -> fail 0 (sprintf "'%s' calls itself: declare it with let rec" x)
    | None when x <> "" && isOpChar x[0] -> fail 0 (sprintf "unknown operator '%s'; define it with: let (%s) a b = …" x x)
    | None when x = "yield" -> fail 0 "yield belongs in [ … ], [| … |] or seq { }"
    | None -> fail 0 (sprintf "unknown %s '%s'" what x)

/// A check of a program's modules, one at a time in dependency order (the prelude and the main
/// file have no module name: their names are global). Each module is either checked now
/// (`check`), or written back into `state` from what checking it gave before (by Snapshot,
/// from the cache), which is the same to the modules after it.
type Session =
    { state: State
      /// Checks a module (file, module name, declarations); false if it had errors. Its result
      /// is what it wrote to the state, and its hovers: what's after `marks ()`.
      check: string -> string option -> (int * Decl) list -> bool
      marks: unit -> Marks
      hovers: ResizeArray<Hover>
      /// errors and warnings so far, in order; a module from the cache adds its warnings
      diagnostics: ResizeArray<Diagnostic>
      /// After the library: the program's file modules and explicit impls (as at the start).
      addProgram: string list -> (string * string) list -> unit
      /// The program so far, with `main` checked (when required, or there is one) and every
      /// error; funs and hovers are the modules checked here.
      finish: unit -> Program }

/// moduleNames: the program's file modules (all of them, so a name can be told from a
/// module's); manualImpls: the explicit impls of every module, (trait, type as written), which
/// win over automatic derives. collect: report every declaration's error (editors) instead of
/// stopping at the first.
let session (requireMain: bool) (collect: bool) (allModules: string list) (manualImpls: (string * string) list) : Session =
    let st = freshState ()
    let types = st.types
    let ctors = st.ctors
    let records = st.records
    let recordDefaults = st.recordDefaults
    let ctorFieldNames = st.ctorFieldNames
    let members = st.members
    let memberTypeNames = st.memberTypeNames
    let traitMethods = st.traitMethods
    let effects = st.effects
    let effectOps = st.effectOps
    let traitAliases = st.traitAliases
    let traitNames = st.traitNames
    let impls = st.impls
    let implRequires = st.implRequires
    let implOthers = st.implOthers
    let derives = st.derives
    let deriveModules = st.deriveModules
    let activePatterns = st.activePatterns
    let apCtors = st.apCtors
    // explicit impls anywhere in the program win over automatic derives
    let manualImpls = HashSet<string * string>(manualImpls)
    let optOut = st.optOut
    let mutable autoDerive: string -> string -> bool = fun _ _ -> false // set once derives can run

    implParams <-
        fun tr t ->
            match prune t with
            | TCon(n, args) ->
                match implOthers.TryGetValue((tr, n)) with
                | true, os -> Some(List.map (substGen args) os)
                | _ -> None
            | TTuple ts ->
                match implOthers.TryGetValue((tr, tupleHead ts.Length)) with
                | true, os -> Some(List.map (substGen ts) os)
                | _ -> None
            | _ -> None

    userImpl <-
        fun tr t ->
            match prune t with
            | t when tr = "Share" ->
                // built in, from the type's parts (its type variables must be Share too)
                try
                    (shareBlocker (fun v -> unify (fresh (kTrait "Share")) v) types.Dict Set.empty t).IsNone
                with
                | Mismatch
                | NoImpl _ -> false
            | TCon(n, []) when isDynName n -> n.Substring 4 = tr // dyn Trait implements its trait
            | TCon(n, args) ->
                if not (implRequires.ContainsKey((tr, n))) then
                    autoDerive tr n |> ignore

                match implRequires.TryGetValue((tr, n)) with
                | true, reqs ->
                    for a, trs in List.zip args reqs do
                        for tr2 in trs do
                            unify (fresh (kTrait tr2)) a

                    true
                | _ -> false
            | TTuple ts when List.contains tr [ "Eq"; "Ord"; "Show"; "Hash" ] ->
                // tuples have structural Eq/Ord/Show/Hash when their components do
                for a in ts do
                    unify (fresh (kTrait tr)) a

                true
            | TTuple ts ->
                // an impl for tuples of this size (impl Binary<'a * 'b>), kept under *2
                match implRequires.TryGetValue((tr, tupleHead ts.Length)) with
                | true, reqs ->
                    for a, trs in List.zip ts reqs do
                        for tr2 in trs do
                            unify (fresh (kTrait tr2)) a

                    true
                | _ -> false
            | _ -> false
    let globals = st.globals
    let externs = st.externs
    let funs = st.funs
    let tyvars = Dictionary<string, Ty>() // 'a in the current function's annotations
    let counter = st.counter
    let measures = st.measures
    let diagnostics = ResizeArray<Diagnostic>()
    let hovers = ResizeArray<Hover>()
    let currentFile = ref ""
    // the warning kinds the declaration being checked silences ([<NoWarn "…">])
    let silenced = ref Set.empty<string>

    /// A warning of a kind at a place, unless the declaration silences the kind (0021).
    let warn (kind: string) (line: int) (col: int) (msg: string) =
        if not (silenced.Value.Contains kind) then
            diagnostics.Add
                { severity = Severity.Warning
                  name = kind
                  file = currentFile.Value
                  line = line
                  col = col
                  msg = msg
                  notes = [] }

    // the values statements drop in the declaration being checked, with their places: warned
    // about at its end, when their types are settled (unused-value)
    let discarded = ResizeArray<Ty * int * int>()

    // trait methods called with an ambient row (0025): the value's type, the row, the trait, the
    // method and the line; through dyn the row must be empty
    let dynCalls = ResizeArray<Ty * Ty * string * string * int>()

    // the [<Tests>] values of the module being checked, and whether each is a list (0009)
    let testValues = ResizeArray<string * bool>()

    let closeDynCalls () =
        let calls = List.ofSeq dynCalls
        dynCalls.Clear()

        for t, row, tr, m, line in calls do
            match prune t with
            | TCon(d, []) when d.StartsWith "dyn:" ->
                try
                    unify rowEmpty row
                with Mismatch ->
                    fail line (sprintf "this performs %s, but %s is called through dyn %s, where its arguments must perform nothing: call it on the value's own type, or handle it inside" (fst (rowParts row) |> List.map show |> String.concat ", ") m (shortName tr))
            | _ -> ()

    let warnDiscarded () =
        for t, l, c in discarded do
            let shown =
                match prune t with
                | TCon("unit", [])
                | TGen _ -> None
                | TVar r ->
                    // a literal's type not settled: int if it can be, else its float
                    match (kindOf r).allowed with
                    | None -> None
                    | Some ts when ts.Contains "int" -> Some "int"
                    | Some ts when ts.Contains "f64" -> Some "f64"
                    | Some _ -> Some "a number"
                | t -> Some(show t)

            match shown with
            | Some t -> warn "unused-value" l c (sprintf "this statement's value (%s) is discarded: use it, or pipe it to ignore" t)
            | None -> ()

        discarded.Clear()
    let currentLine = ref 0 // of the expression being inferred (assert messages)
    // the effects of the function being checked: what its body performs joins this row (an
    // initializer's or a task's is closed: nothing may be performed there), and what it is, for
    // an error naming it ("" for a function's inferred row)
    let ctxRow = ref rowEmpty
    let ctxWhat = ref "code outside a function"

    /// Checks a body with its own row: a function's, a lambda's, a handled expression's.
    let withRowAs (row: Ty) (what: string) (f: unit -> 'r) : 'r =
        let outer, outerWhat = ctxRow.Value, ctxWhat.Value
        ctxRow.Value <- row
        ctxWhat.Value <- what

        try
            f ()
        finally
            ctxRow.Value <- outer
            ctxWhat.Value <- outerWhat

    let withRow (row: Ty) (f: unit -> 'r) : 'r = withRowAs row "" f

    /// A row's effects as text: Yield<int>, Log.
    let effectsText (row: Ty) = fst (rowParts row) |> List.map show |> String.concat ", "

    /// A call performs what the function's row has: it joins the row of the body the call is in
    /// (a closed row opened first: calling a function that performs less is fine).
    let useRow (row: Ty) =
        let ls, tail = rowParts row

        // each of the callee's effects met by the first one of its name here
        let within (here: Ty list) =
            let mutable left = here

            for l in ls do
                match left |> List.tryFindIndex (fun h -> labelName h = labelName l) with
                | Some i ->
                    match prune l, prune left[i] with
                    | TCon(_, xs), TCon(_, ys) when xs.Length = ys.Length -> List.iter2 unify xs ys
                    | _ -> raise Mismatch

                    left <- List.removeAt i left
                | None -> raise Mismatch

        try
            match prune tail with
            | TCon("$total", []) when ls.IsEmpty -> ()
            | TCon("$total", []) -> unifyRow (mkRow ls (fresh kRow)) ctxRow.Value
            | TVar a ->
                let here, hereTail = rowParts ctxRow.Value

                match prune hereTail with
                // the callee's row ends in this row's own variable (a function calling itself under
                // a handle of an effect it performs): it's included when its effects are here
                | TVar b when obj.ReferenceEquals(a, b) -> within here
                | _ -> unifyRow row ctxRow.Value
            | _ -> unifyRow row ctxRow.Value
        with Mismatch ->
            let here = fst (rowParts ctxRow.Value)
            // the same effect, handled here with other type arguments
            match ls |> List.tryPick (fun l -> here |> List.tryFind (fun h -> labelName h = labelName l) |> Option.map (fun h -> l, h)) with
            | Some(l, h) -> fail 0 (sprintf "this performs %s, but the innermost handler here is for %s" (show l) (show h))
            | None when ls.IsEmpty -> fail 0 "this call's effects can't be handled here: write the effects of the function it calls (/ E)"
            | None when ctxWhat.Value = "" -> fail 0 (sprintf "this performs %s, which the function it's in can't (its type says what it performs)" (effectsText row))
            | None -> fail 0 (sprintf "this performs %s, but %s can't: handle it inside (handle … with)" (effectsText row) ctxWhat.Value)

    /// Remembers the type at a node's source position, and what the name refers to.
    let recordKey (node: obj) (name: string) (t: Ty) (inlay: bool) (key: string) (isDef: bool) =
        match positions.TryGetValue node with
        | true, (l, c, len) ->
            hovers.Add
                { hfile = currentFile.Value
                  hline = l
                  hcol = c
                  // a definition spans its name as written (`length`, though named Collections.List.length)
                  hlen = if isDef && len > 0 then len else max len name.Length
                  name = name
                  hty = t
                  constraints = ""
                  explain = ""
                  decl = false
                  key = key
                  isDef = isDef
                  inlay = inlay }
        | _ -> ()

    let record (node: obj) (name: string) (t: Ty) (inlay: bool) = recordKey node name t inlay "" false

    /// The type with its variables as a scheme's ('a, 'b, … in order), as a hover or an error
    /// shows a generic one; a literal's variable (a number constant's) stays.
    let schemed (t: Ty) =
        let vars = ResizeArray<TV ref>()

        let rec named (t: Ty) =
            match prune t with
            | TVar r when (kindOf r).allowed.IsNone ->
                if not (vars.Exists(fun v -> obj.ReferenceEquals(v, r))) then
                    vars.Add r

                TGen(vars.FindIndex(fun v -> obj.ReferenceEquals(v, r)))
            | TCon(n, ts) -> TCon(n, List.map named ts)
            | TTuple ts -> TTuple(List.map named ts)
            | TFun(a, b, r) -> TFun(named a, named b, named r)
            | t -> t

        named t

    /// Errors raised while checking a positioned node (a name, call or field) point at it.
    let at (node: obj) (f: unit -> 'r) : 'r =
        try
            f ()
        with CompileError(0, msg) when positions.ContainsKey node ->
            let l, c, _ = positions[node]
            raise (CompileErrorPos(l, c, msg))

    let colOf (node: obj) =
        match positions.TryGetValue node with
        | true, (_, c, _) -> c
        | _ -> 0

    /// Parameters that are plain names, with their types.
    let recordParams (orig: Param list) (pars: (string * string * Ty) list) =
        if orig.Length = pars.Length then
            List.iter2
                (fun (p: Pat, ann: SType option) (_, u, t) ->
                    match p with
                    | PIdent(x, None) -> recordKey p x t ann.IsNone u true
                    | _ -> ())
                orig
                pars
    let clayouts = st.clayouts
    let exports = st.exports
    let tests = st.tests
    let consts = st.consts
    let inlining = HashSet<string>() // constants being expanded (a cycle is an error)
    let globalValues = st.globalValues
    let valueList = st.valueList
    let recordHints = Dictionary<Expr, Ty>(HashIdentity.Reference) // record literal -> expected type
    let measuredHints = Dictionary<Expr, Ty>(HashIdentity.Reference) // 5<ns> -> the number type expected of it
    let aliases = st.aliases
    let literalRecords = st.literalRecords
    let lambdaHints = Dictionary<Expr, Ty>(HashIdentity.Reference) // lambda -> the function type expected of it
    let dynHints = Dictionary<Expr, Ty>(HashIdentity.Reference) // expression -> the dyn Trait expected of it
    let spanHints = Dictionary<Expr, Ty>(HashIdentity.Reference) // expression -> the span expected of it
    let shareHints = Dictionary<Expr, Ty>(HashIdentity.Reference) // expression -> the share<F> expected of it
    // a let-bound local's Core, by its unique name: what a function crossing threads captures
    // when it captures a local function
    let localValues = Dictionary<string, CExpr>()
    let currentModule = ref (None: string option)
    let opens = ref ([]: string list) // most recent first
    let privates = st.privates
    // files' and nested modules, and the namespaces they are in (Collections from Collections.List):
    // every file's from the start, so a name can be told from a module's (no module's result:
    // they're in place before the first is marked); nested ones as they're checked
    let withEnclosing (m: string) =
        let parts = m.Split '.'
        [ for k in 1 .. parts.Length -> String.concat "." parts[.. k - 1] ]

    let moduleNames = st.moduleNames

    for m in allModules do
        for n in withEnclosing m do
            moduleNames.Add n |> ignore

    let mainNested = st.mainNested
    let wrapping = ref false // checking a [<Wrapping>] function: its integer + - * wrap
    let fastMath = ref false // checking a [<FastMath>] function: its float + - * / may be reassociated
    let unsafeOn = ref false // inside `unsafe`
    let exporting = ref false // checking an [<Export>] function: C calls it, so nothing in its type performs
    let nestedModules = st.nestedModules

    /// The name a declaration gets in the current module.
    let qualify (name: string) =
        match currentModule.Value with
        | Some m -> m + "." + name
        | None -> name

    // each module's enclosing modules, innermost first (A.B.C: A.B.C, A.B, A)
    let enclosingOf = st.enclosingOf

    /// The current module and the modules it is nested in, innermost first.
    let enclosing () =
        match currentModule.Value with
        | Some m ->
            match enclosingOf.TryGetValue m with
            | true, e -> e
            | _ ->
                let parts = m.Split '.'
                let e = [ for k in parts.Length .. -1 .. 1 -> String.concat "." parts[.. k - 1] ]
                enclosingOf[m] <- e
                e
        | None -> []

    /// Unqualified names resolve in the current module and the modules it is nested in, then
    /// opened modules, then globally, then in the auto-opened namespaces. Candidates are tried
    /// in that order and built only as needed: this runs for every name.
    let resolveWith (exists: string -> bool) (x: string) : string option =
        let enclosing = enclosing ()

        let rec tryIn (prefixes: string list) =
            match prefixes with
            | [] -> None
            | p :: rest ->
                let q = p + "." + x
                if exists q then Some q else tryIn rest

        // a private name is visible in its module and in the modules nested in it
        let visibleTo (owner: string option) =
            match owner, currentModule.Value with
            | o, c when o = c -> true
            | Some o, Some c -> c.StartsWith(o + ".")
            | None, Some c -> mainNested.Contains c
            | _ -> false

        let found =
            match tryIn enclosing with
            | Some q -> Some q
            | None ->
                match tryIn opens.Value with
                | Some q -> Some q
                | None -> if exists x then Some x else tryIn autoOpens

        found
        |> Option.map (fun q ->
            match privates.TryGetValue q with
            | true, owner when not (visibleTo owner) ->
                fail 0 (sprintf "'%s' is private to module %s" x (defaultArg owner "?"))
            | _ -> q)

    // built in, before any module (so in none's result)
    types["list"] <-
        { npars = 1
          def = UnionDef [ "[]", []; "::", [ TGen 0; TCon("list", [ TGen 0 ]) ] ] }

    ctors["[]"] <- ("list", 0)
    ctors["::"] <- ("list", 1)
    ctorFieldNames["[]"] <- []
    ctorFieldNames["::"] <- [ Some "head"; Some "tail" ]

    let uniq (x: string) =
        counter.Value <- counter.Value + 1
        sprintf "%s.%d" x counter.Value

    let mk k ty = { k = k; ty = ty }

    /// The type dyn Trait, once the trait's methods are known to allow it: each takes the value
    /// first and doesn't mention its type anywhere else (so a call can pass the value it has).
    let dynOf (tr: string) =
        for m in traitMethods.Values do
            if m.owner = tr && m.nparams > 1 then
                fail 0 (sprintf "dyn %s isn't possible: a trait with several type parameters has no dyn" (shortName tr))

            if m.owner = tr then
                let ok =
                    match m.ty with
                    | TFun(TGen 0, rest, _) ->
                        let rec mentions t =
                            match t with
                            | TGen 0 -> true
                            | TCon(_, ts)
                            | TTuple ts -> List.exists mentions ts
                            | TFun(a, b, _) -> mentions a || mentions b
                            | _ -> false

                        not (mentions rest)
                    | _ -> false

                if not ok then
                    fail 0 (sprintf "dyn %s isn't possible: method '%s' must take the value first and not mention its type elsewhere (%s)" (shortName tr) m.name (show m.ty))

        TCon("dyn:" + tr, [])

    /// tparams: Some names inside a type definition (they become TGen), None in a function.
    /// A function type's effects: in a function's annotations, inferred (a row variable); in a
    /// type definition, and in what crosses to C or another thread (pureArrows), none.
    let rec toTyWith (pureArrows: bool) (tparams: string list option) st =
        let toTy = toTyWith pureArrows

        match st with
        | STVar v ->
            match tparams with
            | Some ps ->
                match List.tryFindIndex ((=) v) ps with
                | Some i -> TGen i
                | None -> fail 0 (sprintf "unknown type parameter '%s" v)
            | None ->
                match tyvars.TryGetValue v with
                | true, t -> t
                | _ ->
                    let t = fresh kAny
                    tyvars[v] <- t
                    t
        | STName("dyn", [ STName(tr, []) ]) ->
            match resolveWith traitNames.Contains tr with
            | Some full -> dynOf full
            | None -> fail 0 (sprintf "unknown trait '%s' in dyn %s" tr tr)
        | STName("fixed", [ el; len ]) ->
            // fixed<T, N>: N elements of T inline. N is a positive number, part of the type (a
            // type variable only in the Fixed module, whose functions work for every N)
            let n =
                match len with
                | STName(d, []) when d <> "" && Seq.forall System.Char.IsDigit d ->
                    match System.Int32.TryParse d with
                    | true, k when k > 0 -> TCon(string k, [])
                    | _ -> fail 0 "fixed needs a positive number of elements, written as a literal"
                | STVar _ when currentModule.Value = Some "Collections.Fixed" -> toTy tparams len
                | _ -> fail 0 "fixed needs a positive number of elements, written as a literal"

            TCon("fixed", [ toTy tparams el; n ])
        | STName(d, []) when d <> "" && System.Char.IsDigit d[0] -> fail 0 "only fixed takes a number as a type argument"
        | STName(n, args) when (resolveWith aliases.ContainsKey n |> Option.exists (types.ContainsKey >> not)) ->
            // an alias: what it names, at these arguments
            let q = (resolveWith aliases.ContainsKey n).Value
            let npars, target = aliases[q]

            if npars <> args.Length then
                fail 0 (sprintf "type '%s' expects %d type argument(s)" n npars)

            substGen (List.map (toTy tparams) args) target
        | STName(n, args) ->
            let n =
                match typeAliases.TryGetValue n with
                | true, c -> c
                | _ -> n

            let n =
                resolveWith (fun q -> prims.Contains q || builtinCons.ContainsKey q || types.ContainsKey q) n
                |> Option.defaultValue n

            let arity =
                if nums.Contains n && (match args with
                                       | [ STMeasure _ ] -> true
                                       | _ -> false) then 1
                elif prims.Contains n then 0
                elif builtinCons.ContainsKey n then builtinCons[n]
                elif types.ContainsKey n then types[n].npars
                else fail 0 (sprintf "unknown type '%s'" n)

            if arity <> args.Length then
                fail 0 (sprintf "type '%s' expects %d type argument(s)" n arity)

            match n, args with
            | n, [ m ] when nums.Contains n -> numWith n (toTy tparams m)
            | ("callback" | "fnptr" | "share"), _ -> TCon(n, List.map (toTyWith true tparams) args)
            | _ -> TCon(n, List.map (toTy tparams) args)
        | STTuple ts -> TTuple(List.map (toTy tparams) ts)
        | STFun(a, STRow(b, labels, tail)) -> TFun(toTy tparams a, toTy tparams b, rowOf tparams labels tail)
        // a -> b -> c: giving a function its first arguments performs nothing; the last arrow
        // has its effects
        | STFun(a, (STFun _ as b)) -> TFun(toTy tparams a, toTy tparams b, rowEmpty)
        | STFun(a, b) -> TFun(toTy tparams a, toTy tparams b, (if pureArrows || tparams.IsSome then rowEmpty else fresh kRow))
        | STRow _ -> fail 0 "effects follow a function type's result (int -> unit / Log) or a function's (let f x : int / Log = …)"
        | STMeasure terms ->
            let units, vars = terms |> List.partition (fun (_, isVar, _) -> not isVar)

            for u, _, _ in units do
                if not (measures.Contains u) then
                    fail 0 (sprintf "unknown unit of measure '%s'; declare it with [<Measure>] type %s" u u)

            TMeas(
                normMeas (
                    TMeas(
                        units |> List.map (fun (u, _, e) -> u, e),
                        vars |> List.map (fun (v, _, e) -> toTy tparams (STVar v), e)
                    )
                )
            )

    and toTy (tparams: string list option) st = toTyWith false tparams st

    /// A written row: its effects (Log, Yield<int>), then the row variable it ends in, if any.
    and rowOf (tparams: string list option) (labels: SType list) (tail: string option) =
        let label (l: SType) =
            match l with
            | STName(n, args) ->
                match resolveWith effects.ContainsKey n with
                | Some full ->
                    let info = effects[full]

                    if info.npars <> args.Length then
                        fail 0 (sprintf "effect '%s' expects %d type argument(s)" n info.npars)

                    TCon(full, List.map (toTy tparams) args)
                | None when types.ContainsKey n || prims.Contains n -> fail 0 (sprintf "'%s' is a type, not an effect: effects follow a function's result (int -> unit / Log)" n)
                | None -> fail 0 (sprintf "unknown effect '%s'" n)
            | _ -> fail 0 "effects are named after a function's result: / Log, / <Log, Yield<int>>"

        let tailTy =
            match tail, tparams with
            | None, _ -> rowEmpty
            | Some v, Some _ -> fail 0 (sprintf "a type's functions can't end their effects in a variable ('%s) yet: write the effects they perform" v)
            | Some v, None ->
                match tyvars.TryGetValue v with
                | true, t ->
                    try
                        unify (fresh kRow) t
                    with Mismatch ->
                        fail 0 (sprintf "'%s is a type here, so it can't stand for effects" v)

                    t
                | _ ->
                    let t = fresh kRow
                    tyvars[v] <- t
                    t

        mkRow (List.map label labels) tailTy

    /// A trait method's type. One with function arguments (0025) has an ambient row, TGen after
    /// the trait's parameters, shared by those arguments' arrows written without a row and by its
    /// own last arrow: it performs what the functions it's given perform, and nothing of its own.
    let methodType (tps: string list) (st: SType) : Ty =
        let rec takesFunction (st: SType) =
            match st with
            | STFun(STFun _, _) -> true
            | STFun(_, b) -> takesFunction b
            | _ -> false

        let ambient = TGen tps.Length

        let rec fn (own: bool) (st: SType) =
            match st with
            | STFun(a, (STFun _ as b)) -> TFun(arg a, fn own b, rowEmpty)
            | STFun(_, STRow(_, labels, _)) when own && not labels.IsEmpty ->
                fail 0 "a trait's method performs nothing of its own; its arguments' effects are its row"
            | STFun(a, STRow(b, labels, tail)) -> TFun(arg a, toTy (Some tps) b, rowOf (Some tps) labels tail)
            | STFun(a, b) -> TFun(arg a, toTy (Some tps) b, ambient)
            | _ -> toTy (Some tps) st

        and arg (a: SType) =
            match a with
            | STFun _ -> fn false a
            | _ -> toTy (Some tps) a

        if takesFunction st then fn true st else toTy (Some tps) st

    /// Whether a trait method's type has an ambient row (methodType): TGen after its parameters.
    let hasAmbient (tm: TraitMethod) =
        let rec go (t: Ty) =
            match t with
            | TGen i when i = tm.nparams -> true
            | TFun(a, b, r) -> go a || go b || go (snd (rowParts r))
            | TCon(_, ts)
            | TTuple ts -> List.exists go ts
            | _ -> false

        go tm.ty

    let annot ann =
        match ann with
        | Some st -> toTy None st
        | None -> fresh kAny

    /// A function's annotated result, and its effects when they're written (`: int / Log`).
    let annotRet (ret: SType option) =
        match ret with
        | Some(STRow(t, labels, tail)) -> toTy None t, Some(rowOf None labels tail)
        | _ -> annot ret, None

    /// A global function used as a value: its own row (the arity-th arrow's) opened when closed
    /// (`/ <E | 'e>` for `/ E`), so it goes where a function performing more is expected. The
    /// coercion is marked (eff.open): Mono drops it where the rows came out equal, and Evidence
    /// adapts the function to the larger row where they didn't.
    let opened (arity: int) (c: CExpr) =
        let rec go n t =
            match prune t with
            | TFun(a, b, row) when n = 1 ->
                let ls, tail = rowParts row

                match prune tail with
                | TCon("$total", []) -> Some(TFun(a, b, mkRow ls (fresh kRow)))
                | _ -> None
            | TFun(a, b, row) when n > 1 -> go (n - 1) b |> Option.map (fun b' -> TFun(a, b', row))
            | _ -> None

        match (if arity > 0 then go arity c.ty else None) with
        | Some t -> { k = CPrim("eff.open", [ c ]); ty = t }
        | None -> c

    let instantiate (kinds: Kind list) (t: Ty) =
        let vars = kinds |> List.map (fun k -> fresh { k with params = Map.empty })

        // a kind's trait parameters may name the scheme's other variables ('c : Iter<'a>)
        for v, k in List.zip vars kinds do
            match v with
            | TVar r when not k.params.IsEmpty ->
                match r.Value with
                | Unbound(id, k0) -> r.Value <- Unbound(id, { k0 with params = k.params |> Map.map (fun _ ps -> List.map (substGen vars) ps) })
                | Link _ -> ()
            | _ -> ()

        substGen vars t, vars

    /// A user type applied to fresh type arguments.
    let instType name =
        let args = List.init types[name].npars (fun _ -> fresh kAny)
        TCon(name, args), args

    let ctorName (c: string) = resolveWith ctors.ContainsKey c
    let isCtor (c: string) = (ctorName c).IsSome

    let caseFields u tag args =
        match types[u].def with
        | UnionDef cs -> snd cs[tag] |> List.map (substGen args)
        | RecordDef _ -> []

    let unionCases u =
        match types[u].def with
        | UnionDef cs -> cs |> List.map (fun (n, ts) -> n, ts.Length)
        | RecordDef _ -> []

    let fieldsOf r =
        match types[r].def with
        | RecordDef fs -> fs
        | UnionDef _ -> []

    let hasFields (given: string list) (r: string) =
        given |> List.forall (fun f -> fieldsOf r |> List.exists (fst >> (=) f))

    /// Of the records some field names could mean, those in scope as a name would be (the
    /// current and enclosing modules, then opens, global names and the auto-opened namespaces),
    /// from the nearest scope that has any, in declaration order.
    let inScope (candidates: string seq) : string list =
        let order = (enclosing () |> List.map Some) @ (opens.Value |> List.map Some) @ [ None ] @ (autoOpens |> List.map Some)

        let moduleOf (r: string) =
            match r.LastIndexOf '.' with
            | -1 -> None
            | i -> Some(r.Substring(0, i))

        let ranked =
            candidates
            |> Seq.choose (fun r -> order |> List.tryFindIndex ((=) (moduleOf r)) |> Option.map (fun k -> k, r))
            |> List.ofSeq

        match ranked with
        | [] -> []
        | _ ->
            let nearest = ranked |> List.map fst |> List.min
            ranked |> List.filter (fst >> (=) nearest) |> List.map snd

    /// The error for fields that no record in scope has, naming a record out of scope that has them.
    let noRecord (plain: string) (given: string list) =
        match records |> Seq.filter (hasFields given) |> Seq.tryLast with
        | Some r when r.Contains '.' -> // out of scope, so in a module
            let m = r.Substring(0, r.LastIndexOf '.')

            let what =
                match given with
                | [ f ] -> sprintf "a field '%s'" f
                | _ -> "the fields " + (given |> List.map (sprintf "'%s'") |> String.concat ", ")

            fail 0 (sprintf "no record in scope has %s; %s does: open %s, or annotate (… : %s)" what r m r)
        | _ -> fail 0 plain

    /// The record a field of a value of unknown type belongs to: the latest in scope.
    let fieldRecord (field: string) =
        records |> Seq.filter (hasFields [ field ]) |> inScope |> List.tryLast

    let recordOf (t: Ty) (field: string) =
        match prune t with
        | _ when field = "ToString" -> fail 0 "there's no .ToString(): interpolate the value, $\"{x}\", which prints it through Show"
        | TCon(n, _) when (match types.TryGetValue n with
                           | true, { def = RecordDef _ } -> true
                           | _ -> false) -> n
        | TCon("option", _) when field = "Value" ->
            fail 0 "an option has no .Value: match on it (Some x -> …), or use Option.defaultValue d o, or Option.get o, which panics on None"
        | _ ->
            match fieldRecord field with
            | Some r -> r
            | None -> noRecord (sprintf "no record has a field '%s'" field) [ field ]

    /// Matches a constructor's arguments to its payload fields: `C`, `C x`, `C (x, y)`.
    let ctorArgs c (args: 'a list) (fields: Ty list) (tuple: 'a -> 'a list option) (wild: 'a option) =
        match args, fields with
        | [], [] -> []
        | [ a ], fs when fs.Length > 1 && (tuple a |> Option.exists (fun xs -> xs.Length = fs.Length)) -> (tuple a).Value
        | [ a ], fs when fs.Length > 1 && wild = Some a -> List.map (fun _ -> a) fs
        | [ a ], [ _ ] -> [ a ]
        | _ -> fail 0 (sprintf "constructor '%s' expects %d argument(s)" c fields.Length)

    /// Non-variable parameters become fresh names matched against their pattern in the body.
    let lowerParams (ps: Param list) (body: Expr) =
        let named =
            ps
            |> List.mapi (fun i (p, ann) ->
                match p with
                | PIdent(x, None) when not (isCtor x) -> (x, ann), None
                | _ ->
                    let x = sprintf "$p%d" i
                    (x, ann), Some(x, p))

        let body =
            List.foldBack
                (fun (_, m) acc ->
                    match m with
                    | Some(x, p) -> Match(Var x, [ p, None, acc ])
                    | None -> acc)
                named
                body

        List.map fst named, body

    let rec pat (names: Dictionary<string, string>) (p: Pat) (ty: Ty) : CPat =
        let name x =
            match names.TryGetValue x with
            | true, u -> u
            | _ ->
                let u = uniq x
                names[x] <- u
                u

        match p with
        | PWild -> CPWild
        | PUnit ->
            expect "pattern" ty tUnit
            CPWild
        | PInt n ->
            expect "pattern" ty (fresh kInt)
            CPInt n
        | PChar c ->
            expect "pattern" ty tChar
            CPInt(int64 c)
        | PStr s ->
            expect "pattern" ty tStr
            CPStr s
        | PBool b ->
            expect "pattern" ty tBool
            CPBool b
        | PIdent(c, arg) when isCtor c ->
            let c = (ctorName c).Value
            let u, tag = ctors[c]
            let uty, targs = instType u
            expect "pattern" ty uty
            let fields = caseFields u tag targs

            let subs =
                match arg with
                | None when apCtors.Contains c -> [ PWild ]
                | Some(PArgs _) -> fail 0 (sprintf "constructor '%s' takes one argument pattern" c)
                | Some(PNamed named) ->
                    let names = ctorFieldNames[c]

                    for n, _ in named do
                        if not (List.contains (Some n) names) then
                            fail 0 (sprintf "constructor '%s' has no field '%s'" c n)

                    names
                    |> List.map (fun n ->
                        match named |> List.tryFind (fun (m, _) -> Some m = n) with
                        | Some(_, p) -> p
                        | None -> PWild)
                | _ ->
                    ctorArgs c (Option.toList arg) fields (function
                        | PTuple ps -> Some ps
                        | _ -> None) (Some PWild)

            CPCtor(u, tag, List.map2 (pat names) subs fields)
        | PIdent(x, None) ->
            let u = name x
            recordKey p x ty true u true
            CPVar(u, ty)
        | PIdent(c, Some _) -> fail 0 (sprintf "unknown constructor '%s'" c)
        | PTuple ps ->
            let ts = ps |> List.map (fun _ -> fresh kAny)
            expect "pattern" ty (TTuple ts)
            CPTuple(List.map2 (pat names) ps ts)
        | POr(a, b) ->
            let ca, cb = pat names a ty, pat names b ty
            let va, vb = patVars ca, patVars cb

            if List.sort (List.map fst va) <> List.sort (List.map fst vb) then
                fail 0 "both sides of '|' must bind the same variables"

            for x, t in va do
                expect "or-pattern variable" t (vb |> List.find (fst >> (=) x) |> snd)

            CPOr(ca, cb)
        | PAs(p, x) -> CPAs(pat names p ty, name x, ty)
        | PRecord fields ->
            let given = fields |> List.map fst

            match given |> List.countBy id |> List.tryFind (fun (_, n) -> n > 1) with
            | Some(f, _) -> fail 0 (sprintf "field '%s' appears twice in the pattern" f)
            | None -> ()

            // the record: the matched value's type when known, else the latest declared record
            // in scope with all these fields (as for record literals)
            let rname =
                match prune ty with
                | TCon(n, _) when records.Contains n -> n
                | _ ->
                    match records |> Seq.filter (hasFields given) |> inScope with
                    | [] -> noRecord (sprintf "no record has the field%s %s" (if given.Length > 1 then "s" else "") (given |> List.map (sprintf "'%s'") |> String.concat ", ")) given
                    | candidates -> List.last candidates

            match given |> List.tryFind (fun f -> not (fieldsOf rname |> List.exists (fst >> (=) f))) with
            | Some f -> fail 0 (sprintf "record '%s' has no field '%s'" rname f)
            | None -> ()

            let rty, targs = instType rname
            expect "pattern" ty rty

            let subs =
                fieldsOf rname
                |> List.map (fun (f, ft) ->
                    match fields |> List.tryFind (fst >> (=) f) with
                    | Some(_, p) -> f, pat names p (substGen targs ft)
                    | None -> f, CPWild)

            CPRecord(rname, subs)
        | PNamed _ -> fail 0 "named field patterns need a constructor: C(field = p)"
        | PArgs _ -> fail 0 "only constructors and active patterns take arguments"

    /// An expression's Core; where a dyn Trait is expected of it, its value as one.
    let rec infer (env: Map<string, Local>) (depth: int) (e: Expr) : CExpr =
        match dynHints.TryGetValue e with
        | true, hint ->
            dynHints.Remove e |> ignore
            toDyn (inferNode env depth e) hint
        | _ ->
            match shareHints.TryGetValue e with
            | true, hint ->
                shareHints.Remove e |> ignore
                toShare (inferNode env depth e) hint
            | _ ->
                match spanHints.TryGetValue e with
                | true, hint ->
                    spanHints.Remove e |> ignore
                    toSpan (inferNode env depth e) hint
                | _ -> inferNode env depth e

    /// An array or a Buffer where a span is expected: a span over all of it.
    and toSpan (c: CExpr) (hint: Ty) : CExpr =
        match prune c.ty, prune hint with
        | TCon(("array" | "Buffer") as k, [ el ]), TCon("span", [ h ]) ->
            expect "span" h el
            mk (CPrim((if k = "array" then "span.ofArray" else "span.ofBuffer"), [ c ])) (TCon("span", [ el ]))
        | _ -> c

    /// A function where a share<F> is expected (it crosses threads): as it is when it's one
    /// already (or its type isn't known yet), else checked that what it captures can be shared,
    /// and marked (share.fn) for the check of what it calls.
    and toShare (c: CExpr) (hint: Ty) : CExpr =
        match prune c.ty, prune hint with
        | TFun _, TCon("share", [ f ]) ->
            expectNoEffects "a function run on another thread must have no effects: this one performs %s; handle it inside" "function crossing threads" f c.ty
            checkCaptures c
            mk (CPrim("share.fn", [ c ])) hint
        | _ -> c

    /// What a function crossing threads captures must be Share: each local it refers to, and
    /// through a local function it refers to, what that one captures.
    and checkCaptures (c: CExpr) =
        let seen = HashSet<string>()

        let rec go (e: CExpr) (via: string list) =
            let bound = Set.ofList (binders e)

            for x, t in refs e do
                if not (bound.Contains x) && seen.Add x then
                    let name = x.Substring(0, x.LastIndexOf '.')

                    match prune t, localValues.TryGetValue x with
                    | TFun _, (true, def) -> go def (name :: via)
                    | _ ->
                        let through =
                            match via with
                            | [] -> ""
                            | fs -> sprintf " (through %s)" (fs |> List.rev |> List.map (sprintf "'%s'") |> String.concat ", ")

                        try
                            unify (fresh (kTrait "Share")) t
                        with
                        | NoImpl(_, part) ->
                            let part = shareBlocker ignore types.Dict Set.empty t |> Option.defaultValue part
                            let holds = if prune part = prune t then "" else sprintf ", which holds %s" (show part)

                            match prune t with
                            | TFun _ ->
                                fail 0 (sprintf "this function crosses threads, but it captures '%s'%s, a function that may capture what can't be shared: declare it share<%s>" name through (show t))
                            | _ -> fail 0 (sprintf "this function crosses threads, but it captures '%s'%s : %s%s, which can't be shared between threads; share state through Atomic, Mutex or Channel, or return a result per job" name through (show t) holds)
                        | Mismatch -> fail 0 (sprintf "this function crosses threads, but it captures '%s'%s : %s, which can't be shared between threads; share state through Atomic, Mutex or Channel, or return a result per job" name through (show t))

        go c []

    /// A value where a dyn Trait is expected: as it is when it's one already (or its type isn't
    /// known yet), else with its type's impl of the trait.
    and toDyn (c: CExpr) (hint: Ty) : CExpr =
        match prune c.ty, prune hint with
        | TCon(n, []), _ when isDynName n -> c
        | TVar r, _ when (kindOf r).allowed.IsSome ->
            // a literal: its own type (int, f64, string), made a dyn
            settle c.ty
            toDyn c hint
        | TVar _, _ -> c
        | t, TCon(d, []) ->
            let tr = d.Substring 4
            expect (sprintf "value for a dyn %s" (shortName tr)) (fresh (kTrait tr)) t
            mk (CPrim("dyn.box:" + tr, [ c ])) hint
        | _ -> c

    and inferNode (env: Map<string, Local>) (depth: int) (e: Expr) : CExpr =
        let inf = infer env depth
        let node = e

        match e with
        | At(ln, e) ->
            currentLine.Value <- ln

            try
                let c = infer env depth e
                mk (CLine(ln, c)) c.ty
            with CompileError(0, msg) ->
                raise (CompileErrorPos(ln, colOf node, msg))
        | Lit n -> mk (CInt n) (fresh kInt)
        | CharLit c -> mk (CInt(int64 c)) tChar
        | FloatLit f -> mk (CFloat f) (fresh kFloat)
        | BoolLit b -> mk (CBool b) tBool
        | StrLit s -> mk (CStr s) (fresh kStrLit)
        | UnitLit -> mk CUnit tUnit
        | Var x ->
            let r = at node (fun () -> value env depth x)

            // a generic constant (Map.empty) shows its scheme, as F# does: an instance of its
            // own, not the one this use settles
            let shown =
                match env.TryFind x, resolveName x with
                | None, Some q when consts.ContainsKey q ->
                    let own = value' Map.empty depth q

                    match schemed own.ty with
                    | t when t <> own.ty -> t
                    | _ -> r.ty
                | _ -> r.ty

            recordKey node x shown false (keyOf env x) false
            r
        | Call("$task", [ Lambda([ PUnit, None ], body) ]) ->
            // task { }: a Task whose work is the body, in direct style ($cancel is the task's
            // cancellation, $await a wait); the code generator makes a state machine of the work
            // (an LLVM coroutine), so a wait allocates nothing
            let a = fresh kAny
            let cancelTy = tcon "Threading.Cancel"
            let kTy = tfun a tUnit
            let cl =
                { u = uniq "$cancel"
                  ty = cancelTy
                  mut = false
                  depth = depth + 1 }

            let ku, ru = uniq "$k", uniq "$result"
            // the work runs from the event loop, where no handler is: it performs nothing
            let cb = withRowAs rowEmpty "a task's body (it runs from the event loop, where no handler is)" (fun () -> infer (env.Add("$cancel", cl)) (depth + 1) body)
            expect "the task's result" a cb.ty
            let complete = value env depth "Threading.Task.complete"
            expect "the task's result" (tfun kTy (tfun a tUnit)) complete.ty
            let kE = mk (CLocal ku) kTy
            let cancelE = mk (CLocal cl.u) cancelTy

            // a return! that isn't last (in a use's scope): a wait as any other
            let rec plainWaits (e: CExpr) =
                match e.k with
                | CPrim("task.last", [ wait; _ ]) -> plainWaits wait
                | k -> { e with k = mapChildren plainWaits k }

            // what waits for the task gets the body's value: each value the body may end with,
            // given to it; a return! at the end, its task handed this task's cancellation and
            // waiter, so a task looping through return! keeps one state machine, not one per round
            let rec finish (e: CExpr) : CExpr =
                let unit' k = mk k tUnit

                match e.k with
                | CLine(l, b) -> unit' (CLine(l, finish b))
                | CLet(x, v, b) -> unit' (CLet(x, plainWaits v, finish b))
                | CLetMut(x, v, b) -> unit' (CLetMut(x, plainWaits v, finish b))
                | CSeq(a, b) -> unit' (CSeq(plainWaits a, finish b))
                | CIf(c, t, f) -> unit' (CIf(plainWaits c, finish t, finish f))
                | CMatch(s, cases) -> unit' (CMatch(plainWaits s, cases |> List.map (fun (p, g, b) -> p, Option.map plainWaits g, finish b)))
                | CLetFun(n, r, ps, b, rest) -> unit' (CLetFun(n, r, ps, plainWaits b, finish rest))
                | CLetRec(fs, rest) -> unit' (CLetRec(fs |> List.map (fun (n, ps, b) -> n, ps, plainWaits b), finish rest))
                | CPrim("task.last", [ _; t ]) ->
                    let handOff = value env depth "Threading.Task.handOff"
                    expect "the task return! gives" (tfun t.ty (tfun cancelTy (tfun kTy tUnit))) handOff.ty
                    unit' (CApp(handOff, [ t; cancelE; kE ]))
                | _ -> unit' (CApp(complete, [ kE; plainWaits e ]))

            // whether a return! ends the body (on some path): if not, it ends as it always has
            let rec last (e: CExpr) =
                match e.k with
                | CLine(_, b)
                | CLet(_, _, b)
                | CLetMut(_, _, b)
                | CSeq(_, b)
                | CLetFun(_, _, _, _, b)
                | CLetRec(_, b) -> last b
                | CIf(_, t, f) -> last t || last f
                | CMatch(_, cases) -> cases |> List.exists (fun (_, _, b) -> last b)
                | CPrim("task.last", _) -> true
                | _ -> false

            let body =
                if last cb then
                    finish cb
                else
                    // the result first, then what waits for it (which waits held meanwhile)
                    mk (CLet(ru, plainWaits cb, mk (CApp(complete, [ kE; mk (CLocal ru) a ])) tUnit)) tUnit

            let work = mk (CLam([ cl.u, cancelTy; ku, kTy ], body)) (tfun cancelTy (tfun kTy tUnit))
            let _, noneTag = ctors["None"]
            mk (CTuple [ mk (CCtor("option", noneTag, [])) (TCon("option", [ a ])); work ]) (TCon("Threading.Task", [ a ]))
        | Call(("$await" | "$awaitLast") as form, [ e ]) ->
            // let!, do!, return! in a task: the task's ready result, or a wait (task.suspend) for
            // its work's (none if the task is cancelled already: task.abandon); a return!'s
            // marked (task.last), so at the end of the body its task gets this one's waiter
            match env.TryFind "$cancel" with
            | Some cl when cl.depth = depth ->
                let ce = infer env depth e
                let t = fresh kAny
                expect "the task let! waits for" (TCon("Threading.Task", [ t ])) ce.ty
                let tv, x = uniq "$task", uniq "$ready"
                let tvE = mk (CLocal tv) ce.ty
                let cE = mk (CLocal cl.u) cl.ty
                let _, someTag = ctors["Some"]
                let _, noneTag = ctors["None"]
                let cancelled = fieldsOf "Threading.Cancel" |> List.findIndex (fst >> (=) "cancelled")
                let flag = mk (CPrim("ref.get", [ mk (CField(cE, cancelled)) (TCon("ref", [ tBool ])) ])) tBool
                let workTy = tfun cl.ty (tfun (tfun t tUnit) tUnit)
                let wait = mk (CPrim("task.suspend", [ mk (CField(tvE, 1)) workTy; cE ])) t
                let notReady = mk (CIf(flag, mk (CPrim("task.abandon", [])) t, wait)) t

                let ready =
                    CMatch(
                        mk (CField(tvE, 0)) (TCon("option", [ t ])),
                        [ CPCtor("option", someTag, [ CPVar(x, t) ]), None, mk (CLocal x) t
                          CPCtor("option", noneTag, []), None, notReady ]
                    )

                let wait = if form = "$awaitLast" then mk (CPrim("task.last", [ mk ready t; tvE ])) t else mk ready t
                mk (CLet(tv, ce, wait)) t
            | Some _ -> fail 0 "let!, do! and return! wait in the task's own body, not in a function inside it"
            | None -> fail 0 "let!, do! and return! are for a task { }"
        | Call("$seq", [ lam ]) ->
            // seq { }: a Seq of the body, a function performing Yield of the elements
            let a = fresh kAny
            let bodyTy = TFun(tUnit, tUnit, rowExt (TCon("Yield", [ a ])) rowEmpty)
            let cl = inferHint env depth bodyTy lam

            try
                unify bodyTy cl.ty
            with Mismatch | NoImpl _ ->
                match prune cl.ty with
                | TFun(_, r, row) when prune r = tUnit ->
                    let others = fst (rowParts row) |> List.filter (fun l -> labelName l <> "Yield")
                    fail 0 (sprintf "a seq { } only yields: this one performs %s too; handle it inside" (others |> List.map show |> String.concat ", "))
                | TFun(_, r, _) -> fail 0 (sprintf "a seq { }'s body yields its elements and gives unit, not %s" (show r))
                | _ -> fail 0 "a seq { } needs a body"

            match ctors.TryGetValue "Collections.Seq" with
            | true, (u, tag) -> mk (CCtor(u, tag, [ cl ])) (TCon(u, [ a ]))
            | _ -> fail 0 "seq { } needs the library's Seq"
        | Call("$format", [ e; StrLit spec ]) ->
            // {e:spec}: Format.format e "spec", and a number's specifier checked (0024): F and N
            // for every number, D, X and B for integers, E and G for floats
            let x = uniq "$hole"
            let c = inf (Let(PIdent(x, None), None, e, Call("Format.format", [ Var x; StrLit spec ])))

            let kind =
                match c.k with
                | CLet(_, v, _) ->
                    match prune v.ty with
                    | TCon(n, _) when ints.Contains n -> "an integer"
                    | TCon(n, _) when floats.Contains n -> "a float"
                    | TVar r when (kindOf r).allowed |> Option.exists (fun a -> a.Contains "int") -> "an integer"
                    | TVar r when (kindOf r).allowed |> Option.exists (fun a -> a.Contains "f64") -> "a float"
                    | _ -> ""
                | _ -> ""

            let letters =
                match kind with
                | "an integer" -> "FNDXxBb"
                | "a float" -> "FNEG"
                | _ -> ""

            if letters <> "" && not (letters.Contains spec[0]) then
                fail 0 (sprintf "'%c' isn't a format specifier for %s: it takes %s" spec[0] kind (letters |> Seq.map string |> String.concat ", "))

            c
        | Call("$yield", [ e ]) -> perform env depth "Yield.yield" [ e ]
        | Call("$yieldAll", [ e ]) -> call env depth "Collections.Seq.yieldAll" [ e ]
        | Handle(body, ops, ret) -> handleExpr env depth body ops ret
        | Call("assert", [ At(_, (Bin(("=" | "<>" | "<" | "<=" | ">" | ">="), _, _) as c)) ])
        | Call("assert", [ Bin(("=" | "<>" | "<" | "<=" | ">" | ">="), _, _) as c ]) when not (env.ContainsKey "assert") ->
            // a comparison: its sides are evaluated once, and when it fails the message shows
            // them (through Show, or as written) and where they first differ (Diff) (0009)
            let op, a, b =
                match c with
                | Bin(op, a, b) -> op, a, b
                | _ -> failwith "assert"

            let file = System.IO.Path.GetFileName currentFile.Value
            let line = currentLine.Value
            let ca = infer env depth a
            let cb = infer env depth b

            let local (c: CExpr) =
                { u = uniq "$side"
                  ty = c.ty
                  mut = false
                  depth = depth }

            let l, r = local ca, local cb
            let env' = env.Add("$left", l).Add("$right", r)
            let cond = infer env' depth (Bin(op, Var "$left", Var "$right"))

            let has (tr: string) (t: Ty) =
                try
                    unify (fresh (kTrait tr)) t
                    true
                with _ ->
                    false

            let side (name: string) (e: Expr) (t: Ty) = if has "Show" t then Call("Show.show", [ Var name ]) else StrLit(exprText e)

            let at =
                if op = "=" && has "Diff" ca.ty then
                    [ Match(
                          Call("Diff.diff", [ Var "$left"; Var "$right" ]),
                          [ PIdent("Some", Some(PIdent("$at", None))),
                            None,
                            If(Call("Text.String.startsWith", [ StrLit "."; Var "$at" ]), Bin("+", StrLit "\n  at ", Var "$at"), Some(StrLit ""))
                            PIdent("None", None), None, StrLit "" ]
                      ) ]
                else
                    []

            let parts =
                [ StrLit(sprintf "assertion failed at %s:%d: %s\n  left:  " file line (exprText c))
                  side "$left" a ca.ty
                  StrLit "\n  right: "
                  side "$right" b cb.ty ]
                @ at

            let message = parts |> List.reduce (fun x y -> Bin("+", x, y))
            let failed = infer env' depth (Call("panic", [ message ]))
            expect "assert" tUnit failed.ty
            mk (CLet(l.u, ca, mk (CLet(r.u, cb, mk (CIf(cond, mk CUnit tUnit, failed)) tUnit)) tUnit)) tUnit
        | Call(f, [ v; lit ]) when not (env.ContainsKey f) && resolveName f = Some "Testing.expect" ->
            // an expect test: its place goes in, so zs test --update can find its literal (0009)
            match lit with
            | StrLit _
            | At(_, StrLit _) -> call env depth "Testing.expectAt" [ v; lit; StrLit(System.IO.Path.GetFileName currentFile.Value); Lit(int64 currentLine.Value) ]
            | _ -> fail 0 "expect's expected text is a string literal, which zs test --update can rewrite"
        | Call("assert", [ c ]) when not (env.ContainsKey "assert") ->
            // the location goes into the message: "assertion failed at file:line"
            let cc = infer env depth c
            expect "assert" tBool cc.ty
            let file = System.IO.Path.GetFileName currentFile.Value
            mk (CPrim(sprintf "assert:%s:%d" file currentLine.Value, [ cc ])) tUnit
        | Call(f, args) ->
            let r = at node (fun () -> call env depth f args)

            let headTy =
                match r.k with
                | CApp(h, _) -> h.ty
                | CPerform(l, _, args) -> funTyRow (args |> List.map (fun a -> a.ty)) r.ty (rowExt l rowEmpty)
                | CExtern(name, _) when externs.ContainsKey name -> // a C function: its declared type
                    let x = externs[name]
                    List.foldBack tfun (if x.pars.IsEmpty then [ tUnit ] else x.pars) x.ret
                | _ -> r.ty

            recordKey node f headTy false (keyOf env f) false
            r
        | App((Field(r, f) as fe), args) ->
            let cr = inf r
            settle cr.ty

            match memberOf cr.ty f with
            | Some(m: MemberInfo) when not m.isStatic && not m.isProperty ->
                let res = memberCall env depth m (Some cr) args f
                recordKey fe f res.ty false m.gname false
                res
            | _ -> apply env depth (field cr f) args None
        | App(h, args) -> apply env depth (inf h) args None
        | Lambda(ps0, body) ->
            let ps, body = lowerParams ps0 body
            let pars = ps |> List.map (fun (x, ann) -> x, uniq x, annot ann)
            recordParams ps0 pars

            // the function type expected of it gives the unannotated parameters their types
            // before the body is typed: in xs |> List.map (fun s -> s.Length), s is known
            match lambdaHints.TryGetValue node with
            | true, hint ->
                lambdaHints.Remove node |> ignore

                let rec give (t: Ty) (pars: (string * string * Ty) list) (ps: (string * SType option) list) =
                    match prune t, pars, ps with
                    | TFun(p, r, _), (_, _, pt) :: pars', (_, ann) :: ps' ->
                        if ann.IsNone then unify pt p
                        give r pars' ps'
                    | _ -> ()

                give hint pars ps
            | _ -> ()

            let envB =
                pars
                |> List.fold
                    (fun (m: Map<_, _>) (x, u, t) ->
                        m.Add(
                            x,
                            { u = u
                              ty = t
                              mut = false
                              depth = depth + 1 }
                        ))
                    env

            let row = fresh kRow
            let cb = withRow row (fun () -> infer envB (depth + 1) body)
            let ptys = pars |> List.map (fun (_, _, t) -> t)
            mk (CLam(pars |> List.map (fun (_, u, t) -> u, t), cb)) (funTyRow ptys cb.ty row)
        | LetFun(name, isRec, ps0, ret, body, rest) ->
            let ps, body = lowerParams ps0 body
            let pars = ps |> List.map (fun (x, ann) -> x, uniq x, annot ann)
            recordParams ps0 pars
            let rty, declared = annotRet ret
            let row = declared |> Option.defaultWith (fun () -> fresh kRow)
            let fty = funTyRow (pars |> List.map (fun (_, _, t) -> t)) rty row

            let self =
                { u = uniq name
                  ty = fty
                  mut = false
                  depth = depth }

            let envB =
                pars
                |> List.fold
                    (fun (m: Map<_, _>) (x, u, t) ->
                        m.Add(
                            x,
                            { u = u
                              ty = t
                              mut = false
                              depth = depth + 1 }
                        ))
                    (if isRec then env.Add(name, self) else env)

            let cb = withRow row (fun () -> infer envB (depth + 1) body)
            expect (sprintf "result of '%s'" name) rty cb.ty
            recordKey node name fty false self.u true
            localValues[self.u] <- mk (CLam(pars |> List.map (fun (_, u, t) -> u, t), cb)) fty
            let cr = infer (env.Add(name, self)) depth rest
            mk (CLetFun(self.u, isRec, pars |> List.map (fun (_, u, t) -> u, t), cb, cr)) cr.ty
        | LetRecGroup(members, rest) ->
            // local functions that call each other: all names are in scope in every body
            let prepared =
                members
                |> List.map (fun m ->
                    match m with
                    | LetFun(name, _, ps0, ret, body, _) ->
                        let ps, body = lowerParams ps0 body
                        let pars = ps |> List.map (fun (x, ann) -> x, uniq x, annot ann)
                        recordParams ps0 pars
                        let rty, declared = annotRet ret
                        let row = declared |> Option.defaultWith (fun () -> fresh kRow)
                        let fty = funTyRow (pars |> List.map (fun (_, _, t) -> t)) rty row

                        let self =
                            { u = uniq name
                              ty = fty
                              mut = false
                              depth = depth }

                        m, name, pars, rty, fty, self, body, row
                    | _ -> failwith "LetRecGroup member")

            let envGroup = prepared |> List.fold (fun (m: Map<_, _>) (_, name, _, _, _, self, _, _) -> m.Add(name, self)) env

            let defs =
                prepared
                |> List.map (fun (node, name, pars, rty, fty, self, body, row) ->
                    let envB =
                        pars
                        |> List.fold
                            (fun (m: Map<_, _>) (x, u, t) ->
                                m.Add(
                                    x,
                                    { u = u
                                      ty = t
                                      mut = false
                                      depth = depth + 1 }
                                ))
                            envGroup

                    let cb = withRow row (fun () -> infer envB (depth + 1) body)
                    expect (sprintf "result of '%s'" name) rty cb.ty
                    recordKey node name fty false self.u true
                    localValues[self.u] <- mk (CLam(pars |> List.map (fun (_, u, t) -> u, t), cb)) fty
                    self.u, pars |> List.map (fun (_, u, t) -> u, t), cb)

            let cr = infer envGroup depth rest
            mk (CLetRec(defs, cr)) cr.ty
        | Let(PIdent(x, None) as p, ann, v, rest) when not (isCtor x) ->
            let cv =
                match ann with
                | Some a -> inferHint env depth (toTy None a) v
                | None -> inf v

            let u = uniq x
            recordKey p x cv.ty ann.IsNone u true
            ann |> Option.iter (fun a -> expect (sprintf "value of '%s'" x) (toTy None a) cv.ty)
            localValues[u] <- cv

            let l =
                { u = u
                  ty = cv.ty
                  mut = false
                  depth = depth }

            let cr = infer (env.Add(x, l)) depth rest
            mk (CLet(l.u, cv, cr)) cr.ty
        | Let(p, ann, v, rest) ->
            if ann.IsSome then
                fail 0 "type annotations on patterns are not supported yet"

            inf (Match(v, [ p, None, rest ]))
        | LetMut(x, ann, v, rest) ->
            let cv = inf v
            ann |> Option.iter (fun a -> expect (sprintf "value of '%s'" x) (toTy None a) cv.ty)

            let l =
                { u = uniq x
                  ty = cv.ty
                  mut = true
                  depth = depth }

            let cr = infer (env.Add(x, l)) depth rest
            mk (CLetMut(l.u, cv, cr)) cr.ty
        | Assign(lhs, rhs) ->
            // the let mutable a place is a field (of a field…) of
            let rec mutableRoot (e: Expr) =
                match e with
                | Var x when (match env.TryFind x with
                              | Some l -> l.mut
                              | None -> false) -> Some x
                | Field(r, _) -> mutableRoot r
                | _ -> None

            match lhs with
            | Var x ->
                match env.TryFind x with
                | Some l when l.mut ->
                    if l.depth < depth then
                        fail 0 (sprintf "mutable variable '%s' cannot be captured by a closure; use a ref cell (let x = ref …; x.Value <- …)" x)

                    let cv = inf rhs
                    expect (sprintf "value assigned to '%s'" x) l.ty cv.ty
                    mk (CAssign(l.u, cv)) tUnit
                | Some _ -> fail 0 (sprintf "'%s' is not mutable; declare it with 'let mutable'" x)
                | None -> fail 0 (sprintf "unknown name '%s'" x)
            | Index(a, i) ->
                let ca = inf a

                match prune ca.ty, a with
                | TCon("span", _), _ -> fail 0 "a span is read-only: slice the Buffer (b.[i..j]) for a window you can write to"
                | TCon("fixed", _), _ when (match a with
                                            | Var x -> env.TryFind x |> Option.exists (fun l -> l.mut)
                                            | _ -> (mutableRoot a).IsSome) ->
                    // an element of a fixed-size array in a let mutable, or in its record: the
                    // place gets the changed value
                    inf (Assign(a, Call("Collections.Fixed.set", [ a; i; rhs ])))
                | TCon("fixed", _), _ ->
                    fail 0 "a fixed-size array is a value: declare it (or the record holding it) with `let mutable` to assign an element, or use Fixed.set, which returns the changed one"
                | TCon("Buffer", _), _ ->
                    // a Buffer is a shared reference: the write is seen through every alias
                    let ci = inf i
                    let cv = inf rhs
                    expect "Buffer" (TCon("Buffer", [ cv.ty ])) ca.ty
                    expect "index" tInt ci.ty
                    mk (CPrim("array.set", [ ca; ci; cv ])) tUnit
                | _, Var x when (match env.TryFind x with
                                 | Some l -> l.mut
                                 | None -> false) ->
                    let l = env[x]

                    if l.depth < depth then
                        fail 0 (sprintf "mutable variable '%s' cannot be captured by a closure; use a ref cell (let x = ref …; x.Value <- …)" x)

                    let ci = inf i
                    let cv = inf rhs
                    expect "array" (TCon("array", [ cv.ty ])) l.ty
                    expect "array index" tInt ci.ty
                    mk (CArraySet(l.u, ci, cv)) tUnit
                | _ when (mutableRoot a).IsSome ->
                    // an element of an array in a let mutable record's field: the record with the
                    // array changed (in place when both are unique)
                    inf (Assign(a, Call("Collections.Array.set", [ a; i; rhs ])))
                | _ ->
                    fail
                        0
                        "arrays are values: to change one, declare it with `let mutable a = …` and write `a.[i] <- x`, or use `Array.set a i x`, which returns the changed array (Buffer<'a> is the shared mutable alternative)"
            | Field(r, "Value") when (mutableRoot r).IsNone ->
                // a ref's Value
                let cr = inf r
                let cv = inf rhs
                expect "ref cell" (TCon("ref", [ cv.ty ])) cr.ty
                mk (CPrim("ref.set", [ cr; cv ])) tUnit
            | Field(r, "Value") when (match prune (inf r).ty with
                                      | TCon("ref", _) -> true
                                      | _ -> false) ->
                // a ref held by a let mutable (or in its record): the ref's Value, not the holder
                let cr = inf r
                let cv = inf rhs
                expect "ref cell" (TCon("ref", [ cv.ty ])) cr.ty
                mk (CPrim("ref.set", [ cr; cv ])) tUnit
            | Field _ when (mutableRoot lhs).IsSome ->
                // a field of a let mutable record, nested or not: p.pos.x <- v is
                // p <- { p with pos = { p.pos with x = v } }
                let rec rebuild (place: Expr) (v: Expr) =
                    match place with
                    | Field(r, f) -> rebuild r (Update(r, [ f, v ]))
                    | _ -> v

                inf (Assign(Var (mutableRoot lhs).Value, rebuild lhs rhs))
            | Field _ -> fail 0 "record fields are immutable: declare the record with `let mutable` to assign one of its fields, or use { r with field = … }"
            | _ -> fail 0 "only mutable variables, their fields and elements, and ref cells can be assigned"
        | While(c, b) ->
            let cc = inf c
            expect "condition of 'while'" tBool cc.ty
            let cb = inf b
            expect "body of 'while'" tUnit cb.ty
            mk (CWhile(cc, cb)) tUnit
        | For(x, a, step, b, body) ->
            let it = fresh kInt
            let ca = inf a
            expect "start of 'for' range" it ca.ty
            let cb = inf b
            expect "end of 'for' range" it cb.ty

            let cs =
                match step with
                | Some s ->
                    let cs = inf s
                    expect "step of 'for' range" it cs.ty
                    cs
                | None -> mk (CInt 1L) it

            let l =
                { u = uniq x
                  ty = it
                  mut = false
                  depth = depth }

            let cbody = infer (env.Add(x, l)) depth body
            expect "body of 'for'" tUnit cbody.ty
            mk (CFor(l.u, ca, cs, cb, cbody)) tUnit
        | Index(a, i) ->
            let ca = inf a
            let ci = inf i
            let el = fresh kAny

            match prune ca.ty with
            | TCon("fixed", [ fel; _ ]) ->
                expect "array index" tInt ci.ty
                mk (CPrim("fixed.get", [ ca; ci ])) fel
            | _ ->
                let container =
                    match prune ca.ty with
                    | TCon(("Buffer" | "span") as c, _) -> c
                    | _ -> "array"

                expect "indexing" (TCon(container, [ el ])) ca.ty
                expect "array index" tInt ci.ty
                mk (CPrim("array.get", [ ca; ci ])) el
        | ArrayLit xs ->
            let el = fresh kAny

            let cs =
                xs
                |> List.map (fun x ->
                    let c = inf x
                    expect "array element" el c.ty
                    c)

            mk (CPrim("array.lit", cs)) (TCon("array", [ el ]))
        | Typed(e, st) ->
            let t = toTy None st
            let c = inferHint env depth t e
            expect "annotated expression" t c.ty
            c
        | Measured(e, m) ->
            let ce = inf e

            // a number with a unit is the number type expected of it (5<ns> as an i64<ns>)
            match measuredHints.TryGetValue node with
            | true, t ->
                measuredHints.Remove node |> ignore

                try
                    unify ce.ty t
                with Mismatch ->
                    ()
            | _ -> ()

            settle ce.ty

            match prune ce.ty with
            | TCon(n, []) when nums.Contains n -> { ce with ty = numWith n (toTy None m) }
            | t -> fail 0 (sprintf "only numbers have units, not %s" (show t))
        | Bin(("*" | "/") as op, a, b) ->
            let ca = inf a
            let cb = inferHint env depth ca.ty b // a literal with a unit on the right: the left's number type

            if measuredOperands ca cb then
                measuredBin op ca cb
            else
                arith op ca cb
        | Bin(op, a, b) ->
            let ca = inf a
            arith op ca (inferHint env depth ca.ty b)
        | Neg a ->
            let ca = inf a
            expect "operand of '-'" (fresh (kTrait "Num")) ca.ty
            mk (CNeg ca) ca.ty
        | Not a ->
            let ca = inf a
            expect "operand of 'not'" tBool ca.ty
            mk (CNot ca) tBool
        | If(c, t, e) ->
            let cc = inf c
            expect "condition of 'if'" tBool cc.ty
            let ct = inf t

            match e with
            | None ->
                expect "'if' without 'else'" tUnit ct.ty
                mk (CIf(cc, ct, mk CUnit tUnit)) tUnit
            | Some e ->
                let ce = inf e
                expect "'else' branch" ct.ty ce.ty
                mk (CIf(cc, ct, ce)) ct.ty
        | Seq(a, b) ->
            // C's `x = 5` as a statement: a comparison whose value is dropped
            let rec unAt (e: Expr) =
                match e with
                | At(_, e) -> unAt e
                | e -> e

            match unAt a with
            | Bin("=", l, _)
            | Call("=", [ l; _ ]) ->
                match unAt l with
                | Var x when (match env.TryFind x with
                              | Some l -> l.mut
                              | None -> false) ->
                    fail 0 (sprintf "'=' compares; to assign to '%s' write %s <- …" x x)
                | _ -> ()
            | _ -> ()

            let ca = inf a

            // a statement is unit: a type still open here becomes unit (a panic's, a callback's
            // in List.iter, as F#'s rule), and any other is a dropped value: unused-value (0021),
            // warned about at the end of the declaration, when its type is settled
            match prune ca.ty with
            | TVar r when (kindOf r).allowed.IsNone && (kindOf r).traits.IsEmpty ->
                try
                    unify ca.ty tUnit
                with Mismatch ->
                    ()
            | _ -> ()

            if not (silenced.Value.Contains "unused-value") then
                let l, c =
                    match positions.TryGetValue a with
                    | true, (l, c, _) -> l, c
                    | _ -> currentLine.Value, 0

                discarded.Add(ca.ty, l, c)

            let cb = inf b
            mk (CSeq(ca, cb)) cb.ty
        | Tuple xs ->
            let cs = List.map inf xs
            mk (CTuple cs) (TTuple(cs |> List.map (fun c -> c.ty)))
        | RecordLit fields -> recordLit env depth (takeHint node) node fields
        | Update(r, fields) ->
            let cr = inf r
            let rname = recordOf cr.ty (fst fields.Head)
            let rty, targs = instType rname
            expect "record update" rty cr.ty
            let tmp = uniq "$r"
            let defs = fieldsOf rname

            let built =
                buildRecord env depth rname targs fields (fun i _ ->
                    mk (CField(mk (CLocal tmp) cr.ty, i)) (substGen targs (snd defs[i])))

            mk (CLet(tmp, cr, built)) built.ty
        | Field(r, f) ->
            let cr = inf r
            let res = at node (fun () -> field cr f)

            let key =
                match memberOf cr.ty f with
                | Some m -> m.gname
                | None -> ""

            recordKey node f res.ty false key false
            res
        | Question _ -> fail 0 "'?' is only supported as `let x = e?` or as a whole statement (for now)"
        | Unsafe a ->
            let outer = unsafeOn.Value
            unsafeOn.Value <- true

            try
                inf a
            finally
                unsafeOn.Value <- outer
        | DeriveCtx(ctx, e) ->
            try
                inf e
            with
            | CompileError(l, msg) -> fail l (sprintf "%s: %s" ctx msg)
            | CompileErrorPos(l, c, msg) -> raise (CompileErrorPos(l, c, sprintf "%s: %s" ctx msg))
        | ListComp(isArray, body) -> listExpression env depth isArray body
        | Slice(a, i, j) ->
            // a window (a span, or a Buffer of a Buffer) of elements i to j, or a string's copy;
            // a bound left out is the start or the end
            let ca = inf a
            settle ca.ty

            let kind, resTy =
                match prune ca.ty with
                | TCon("array", [ el ]) -> 0L, TCon("span", [ el ])
                | TCon("Buffer", [ el ]) -> 1L, ca.ty
                | TCon("span", [ el ]) -> 2L, ca.ty
                | TCon("string", []) -> 3L, tStr
                | t -> fail 0 (sprintf "a slice needs an array, a Buffer, a span or a string, not %s" (show t))

            let bound (e: Expr) =
                let c = inf e
                expect "slice bound" tInt c.ty
                c

            let s = uniq "$sliced"
            let sv = mk (CLocal s) ca.ty
            let lo = i |> Option.map bound |> Option.defaultValue (mk (CInt 0L) tInt)

            let hi =
                match j with
                | Some j -> bound j
                | None ->
                    let len = mk (CPrim((if kind = 3L then "String.length" else "Array.length"), [ sv ])) tInt
                    mk (CBin("-", len, mk (CInt 1L) tInt)) tInt

            let sliced =
                if kind = 3L then CPrim("String.slice", [ sv; lo; hi ])
                else CPrim("window.slice", [ sv; lo; hi; mk (CInt kind) tInt ])

            mk (CLet(s, ca, mk sliced resTy)) resTy
        | Yield _
        | YieldAll _ -> fail 0 "yield belongs in [ … ], [| … |] or seq { }"
        | ForIn(x, xs, body) ->
            // for x in c do body: Iter.forEach c (fun x -> body; true) (0017), c evaluated once,
            // before the loop. The lambda is the compiler's: its body is typed at the function's
            // depth, so it may assign the function's mutables (the impl's forEach is inlined and
            // the lambda applied in place; Lift gives an assigned variable a cell otherwise)
            let cxs = inf xs
            let fe = inf (Var "Iter.forEach")

            let collTy, elTy, row =
                match prune fe.ty with
                | TFun(c, TFun(TFun(a, _, _), _, r), _) -> c, a, r
                | t -> failwith (sprintf "Iter.forEach : %s" (show t))

            expect "for needs a collection" collTy cxs.ty

            let coll =
                { u = uniq "$coll"
                  ty = cxs.ty
                  mut = false
                  depth = depth }

            let xu = uniq x

            let envB =
                env
                    .Add("$coll", coll)
                    .Add(x,
                         { u = xu
                           ty = elTy
                           mut = false
                           depth = depth })

            let cb = withRow row (fun () -> infer envB depth body)
            expect "the body of 'for'" tUnit cb.ty
            let lam = mk (CLam([ xu, elTy ], mk (CSeq(cb, mk (CBool true) tBool)) tBool)) (TFun(elTy, tBool, row))
            useRow row
            let call = mk (CApp(fe, [ mk (CLocal coll.u) cxs.ty; lam ])) tBool
            mk (CLet(coll.u, cxs, mk (CSeq(call, mk CUnit tUnit)) tUnit)) tUnit
        | TryBind(p, e, rest) ->
            // match e with Ok p -> rest | Error err -> Error err, or, on an option, match e with
            // Some p -> rest | None -> None: the rest of the block (the function's result, or the
            // lambda's) gives what the early return does. Its errors point at the `?`.
            let ce = inf e

            let onOption =
                match prune ce.ty with
                | TCon("option", _) -> true
                | _ -> false

            let wrap, payload, other =
                if onOption then
                    let a = fresh kAny
                    TCon("option", [ a ]), a, None
                else
                    let okTy, er = fresh kAny, fresh kAny
                    TCon("result", [ okTy; er ]), okTy, Some er

            at node (fun () -> expect "operand of '?'" wrap ce.ty)
            let names = Dictionary<string, string>()
            let caseOf (c: string) = snd ctors[c]
            let union = if onOption then "option" else "result"
            let cp = CPCtor(union, caseOf (if onOption then "Some" else "Ok"), [ pat names p payload ])
            let vars = patVars cp

            let envOk =
                names
                |> Seq.fold
                    (fun (m: Map<_, _>) kv ->
                        m.Add(
                            kv.Key,
                            { u = kv.Value
                              ty = vars |> List.find (fst >> (=) kv.Value) |> snd
                              mut = false
                              depth = depth }
                        ))
                    env

            let crest = infer envOk depth rest

            at node (fun () ->
                let gives = match other with
                            | Some er -> TCon("result", [ fresh kAny; er ])
                            | None -> TCon("option", [ fresh kAny ])

                try
                    unify gives crest.ty
                with Mismatch | NoImpl _ ->
                    match prune crest.ty, other with
                    | TCon("result", _), None -> fail 0 "? on an option in a function returning result<_, _>: use Option.toResult, or option { }"
                    | TCon("option", _), Some _ -> fail 0 "? on a result in a function returning option<_>: use Result.toOption, or result { }"
                    | TCon("unit", []), _ -> fail 0 "? needs the function to return a result or an option; this one returns unit: match on the value instead, or make the function return a result"
                    | t, Some er ->
                        let ers =
                            match prune er with
                            | TVar _ -> "_"
                            | t -> show t

                        fail 0 (sprintf "'?' needs the rest of the block to produce a result<_, %s>, but it produces %s" ers (show t))
                    | t, None -> fail 0 (sprintf "'?' needs the rest of the block to produce an option, but it produces %s" (show t)))

            let failCase =
                match other with
                | Some er ->
                    let eu = uniq "$err"
                    CPCtor("result", caseOf "Error", [ CPVar(eu, er) ]), None, mk (CCtor("result", caseOf "Error", [ mk (CLocal eu) er ])) crest.ty
                | None -> CPCtor("option", caseOf "None", []), None, mk (CCtor("option", caseOf "None", [])) crest.ty

            let cases = [ (cp, None, crest); failCase ]
            Match.check unionCases apCtors.Contains (cases |> List.map (fun (p, _, _) -> p, false))
            mk (CMatch(ce, cases)) crest.ty
        | Match(s, cases) when
            not (isActiveCall s) && cases |> List.exists (fun (p: Pat, _, _) -> (activeOf p).IsSome)
            ->
            inf (desugarActive s cases)
        | Match(s, cases) ->
            let cs = inf s
            let resTy = fresh kAny

            let ccases =
                cases
                |> List.map (fun (p, guard, body) ->
                    let names = Dictionary<string, string>()
                    let cp = pat names p cs.ty
                    let vars = patVars cp

                    if (vars |> List.map fst |> List.distinct).Length <> vars.Length then
                        fail 0 "a variable is bound twice in this pattern"

                    let env =
                        names
                        |> Seq.fold
                            (fun (m: Map<_, _>) kv ->
                                m.Add(
                                    kv.Key,
                                    { u = kv.Value
                                      ty = vars |> List.find (fst >> (=) kv.Value) |> snd
                                      mut = false
                                      depth = depth }
                                ))
                            env

                    let cg =
                        guard
                        |> Option.map (fun g ->
                            let cg = infer env depth g
                            expect "'when' guard" tBool cg.ty
                            cg)

                    let cb = infer env depth body
                    expect "match case" resTy cb.ty
                    cp, cg, cb)

            Match.check unionCases apCtors.Contains (ccases |> List.map (fun (p, g, _) -> p, g.IsSome))
            mk (CMatch(cs, ccases)) resTy

    /// * and / on numbers with units: the units multiply and divide; a unitless literal
    /// operand is dimensionless.
    and measuredBin (op: string) (ca: CExpr) (cb: CExpr) : CExpr =

        let numPart t =
            match prune t with
            | TCon(n, ms) when nums.Contains n -> Some(n, measOf ms)
            | _ -> None

        for x, other in [ ca, cb; cb, ca ] do
            match prune x.ty, numPart other.ty with
            | TVar r, Some(n, _) when (kindOf r).allowed.IsSome -> expect (sprintf "operand of '%s'" op) (TCon(n, [])) x.ty
            | _ -> ()

        match numPart ca.ty, numPart cb.ty with
        | Some(n1, m1), Some(n2, m2) when n1 = n2 ->
            mk (CBin(op, ca, cb)) (numWith n1 (if op = "*" then measMul m1 m2 else measDiv m1 m2))
        | _ -> fail 0 (sprintf "operands of '%s' must be numbers of the same type: %s and %s" op (show ca.ty) (show cb.ty))

    /// An operator through its trait: + Add, - * / % Num, = <> Eq, < > <= >= Ord.
    and arith (op: string) (ca: CExpr) (cb: CExpr) : CExpr =
        let isArith = List.contains op [ "+"; "-"; "*"; "/"; "%" ]

        let simdBits =
            match prune ca.ty with
            | TCon(n, []) when isMaskName n -> List.contains op [ "&&&"; "|||"; "^^^" ]
            | TCon(n, []) when isVectorName n -> ints.Contains(fst vectorInfo[n]) && List.contains op [ "&&&"; "|||"; "^^^"; "<<<"; ">>>" ]
            | _ -> false

        if simdBits then
            // lane by lane, on integer vectors and masks; a vector's shift takes one int amount
            let rt = if op = "<<<" || op = ">>>" then tInt else ca.ty
            expect (sprintf "right operand of '%s'" op) rt cb.ty
            mk (CBin(op, ca, cb)) ca.ty
        elif List.contains op [ "&&&"; "|||"; "^^^"; "<<<"; ">>>" ] then
            // bitwise: both operands the same integer type (a shift amount too)
            try
                unify (fresh kInt) ca.ty
            with Mismatch ->
                fail 0 (sprintf "operator '%s' needs an integer, not %s" op (show ca.ty))

            expect (sprintf "right operand of '%s'" op) ca.ty cb.ty
            mk (CBin(op, ca, cb)) ca.ty
        else
            let tr =
                match op with
                | "+" -> "Add"
                | "-"
                | "*"
                | "/"
                | "%" -> "Num"
                | "="
                | "<>" -> "Eq"
                | _ -> "Ord"

            try
                unify (fresh (kTrait tr)) ca.ty
            with
            | Mismatch
            | NoImpl _ -> fail 0 (sprintf "operator '%s' does not support type %s (it needs %s)" op (show ca.ty) tr)

            expect (sprintf "right operand of '%s'" op) ca.ty cb.ty

            // in a [<Wrapping>] function, + - * on integers wrap around (decided once the
            // operand type is known: on floats and strings they stay the usual ones)
            let op = if wrapping.Value && List.contains op [ "+"; "-"; "*" ] then "wrap" + op else op
            // in a [<FastMath>] function, + - * / on floats are LLVM's fast ones (Mono keeps the
            // mark only on floats and float vectors)
            let op = if fastMath.Value && List.exists (fun (o: string) -> op.EndsWith o) [ "+"; "-"; "*"; "/" ] then "fast" + op else op
            mk (CBin(op, ca, cb)) (if isArith then ca.ty else tBool)

    /// Does either operand carry a unit of measure (so * and / combine units)?
    and measuredOperands (ca: CExpr) (cb: CExpr) =
        let measured t =
            match prune t with
            | TCon(n, [ TMeas _ ]) when nums.Contains n -> true
            | _ -> false

        measured ca.ty || measured cb.ty

    /// A literal-constrained type variable takes its default before a member lookup.
    and settle (t: Ty) =
        match prune t with
        | TVar r when (kindOf r).allowed.IsSome -> resolve t |> ignore
        | _ -> ()

    /// `e.f` once e is typed: ref cell, record field, or property member.
    and field (cr: CExpr) (f: string) : CExpr =
        settle cr.ty

        let isField =
            match prune cr.ty with
            | TCon(n, _) when records.Contains n -> fieldsOf n |> List.exists (fst >> (=) f)
            | _ -> false

        match prune cr.ty, memberOf cr.ty f with
        | TCon("ref", [ a ]), _ when f = "Value" -> mk (CPrim("ref.get", [ cr ])) a
        | _, Some m when not isField ->
            if m.isStatic then
                fail 0 (sprintf "'%s' is a static member; use %s.%s" f (typeName cr.ty) f)
            elif m.isProperty then
                memberCall Map.empty 0 m (Some cr) [] f
            else
                fail 0 (sprintf "method '%s' must be called: x.%s(...)" f f)
        | TVar _, _ when f = "Value" && (fieldRecord f).IsNone ->
            let a = fresh kAny
            expect "ref cell" (TCon("ref", [ a ])) cr.ty
            mk (CPrim("ref.get", [ cr ])) a
        | TVar _, _ when (fieldRecord f).IsNone ->
            fail 0 (sprintf "cannot resolve '.%s': the type of this expression isn't known here; add a type annotation" f)
        | _ ->
            let rname = recordOf cr.ty f
            let rty, targs = instType rname
            expect (sprintf "field '%s'" f) rty cr.ty
            let defs = fieldsOf rname

            match defs |> List.tryFindIndex (fst >> (=) f) with
            | Some i -> mk (CField(cr, i)) (substGen targs (snd defs[i]))
            | None -> fail 0 (sprintf "%s has no field or member '%s'" (show cr.ty) f)

    and typeName (t: Ty) =
        match prune t with
        | TCon(n, _) -> n
        | t -> showFull t

    and memberOf (t: Ty) (f: string) : MemberInfo option =
        match prune t with
        | TCon(n, _) ->
            match members.TryGetValue n with
            | true, table -> table |> List.tryFind (fst >> (=) f) |> Option.map snd
            | _ -> None
        | _ -> None

    /// `T.M` names a static member?
    and staticMember (name: string) : MemberInfo option =
        let i = name.LastIndexOf '.'

        // most names aren't T.M for a type with members (by T's last part, or an alias), so
        // they are rejected before T is resolved
        let mayHaveMembers () =
            let t = name.Substring(0, i)
            let last = t.Substring(t.LastIndexOf '.' + 1)
            memberTypeNames.Contains last || typeAliases.ContainsKey t

        if i <= 0 || not (mayHaveMembers ()) then
            None
        else
            let t = name.Substring(0, i)

            let t =
                match typeAliases.TryGetValue t with
                | true, c -> c
                | _ -> t

            let t = resolveWith members.ContainsKey t |> Option.defaultValue t

            match members.TryGetValue t with
            | true, table -> table |> List.tryFind (fun (n, m) -> n = name.Substring(i + 1) && m.isStatic) |> Option.map snd
            | _ -> None

    /// A member call. Arguments: positional, then `name = value`; missing optional ones take
    /// their default (evaluated here, seeing earlier parameters) or None.
    and memberCall env depth (m: MemberInfo) (self: CExpr option) (args: Expr list) (what: string) : CExpr =
        let g = globals[m.gname]

        let head =
            if g.defining then
                mk (CGlobal(m.gname, None)) g.ty
            else
                let t, inst = instantiate g.kinds g.ty
                mk (CGlobal(m.gname, Some inst)) t

        let nself = if self.IsSome then 1 else 0
        let arity = max 1 (nself + m.mpars.Length)
        let ptys, resTy = peel arity head.ty
        let mptys = ptys |> List.skip nself

        match self with
        | Some c -> expect (sprintf "receiver of '%s'" what) (List.head ptys) c.ty
        | None -> ()

        let args =
            match args with
            | [ Tuple xs ] -> xs
            | [ UnitLit ] -> []
            | xs -> xs

        let paramIndex n = m.mpars |> List.tryFindIndex (fun p -> p.mname = n)

        let isNamed a =
            match a with
            | Bin("=", Var n, _) -> (paramIndex n).IsSome
            | _ -> false

        let positional = args |> List.takeWhile (isNamed >> not)
        let named = args |> List.skip positional.Length

        if named |> List.exists (isNamed >> not) then
            fail 0 (sprintf "in a call to '%s', positional arguments must come before named ones" what)

        if positional.Length > m.mpars.Length then
            fail 0 (sprintf "'%s' takes %d argument(s), got %d" what m.mpars.Length positional.Length)

        let bindings = ResizeArray<string * CExpr>()
        let given = Dictionary<string, string * Ty>()

        let bindTemp (ce: CExpr) =
            let tmp = uniq "$m"
            bindings.Add(tmp, ce)
            tmp

        let selfArg = self |> Option.map (fun c -> mk (CLocal(bindTemp c)) c.ty)

        let bind i (a: Expr) =
            let p = List.item i m.mpars
            let pt = List.item i mptys

            if given.ContainsKey p.mname then
                fail 0 (sprintf "argument '%s' of '%s' is given twice" p.mname what)

            let ce =
                if p.optional && p.mdefault.IsNone then
                    // the body sees option<T>; a given argument arrives as Some
                    let inner =
                        match prune pt with
                        | TCon("option", [ t ]) -> t
                        | _ -> fresh kAny

                    let c = inferHint env depth inner a
                    expect (sprintf "argument '%s' of '%s'" p.mname what) inner c.ty
                    let u, tag = ctors["Some"]
                    mk (CCtor(u, tag, [ c ])) pt
                else
                    let c = inferHint env depth pt a
                    expect (sprintf "argument '%s' of '%s'" p.mname what) pt c.ty
                    c

            given[p.mname] <- (bindTemp ce, ce.ty)

        positional |> List.iteri bind

        for a in named do
            match a with
            | Bin(_, Var n, v) -> bind (paramIndex n).Value v
            | _ -> ()

        let mutable scope = Map.empty

        let argTemps =
            m.mpars
            |> List.mapi (fun i p ->
                let pt = List.item i mptys

                let tmp, ty =
                    match given.TryGetValue p.mname with
                    | true, v -> v
                    | _ ->
                        let ce =
                            match p.optional, p.mdefault with
                            | true, Some d ->
                                let c = inferHint scope 0 pt d
                                expect (sprintf "default of '%s'" p.mname) pt c.ty
                                c
                            | true, None ->
                                let u, tag = ctors["None"]
                                mk (CCtor(u, tag, [])) pt
                            | false, _ -> fail 0 (sprintf "'%s' is missing argument '%s'" what p.mname)

                        bindTemp ce, pt

                scope <-
                    scope.Add(
                        p.mname,
                        { u = tmp
                          ty = ty
                          mut = false
                          depth = 0 }
                    )

                mk (CLocal tmp) ty)

        let callArgs = Option.toList selfArg @ argTemps
        let callArgs = if callArgs.IsEmpty then [ mk CUnit tUnit ] else callArgs
        let call = mk (CApp(head, callArgs)) resTy
        List.foldBack (fun (tmp, ce: CExpr) acc -> mk (CLet(tmp, ce, acc)) acc.ty) (List.ofSeq bindings) call

    /// `A.B.c.d` lexed as one name: the longest prefix that resolves, then field accesses.
    and splitQualified (env: Map<string, Local>) (x: string) : Expr option =
        let parts = x.Split '.'

        let resolves (n: string) =
            env.ContainsKey n || consts.ContainsKey n || (resolveName n).IsSome

        seq { parts.Length - 1 .. -1 .. 1 }
        |> Seq.tryPick (fun k ->
            let prefix = String.concat "." parts[.. k - 1]

            if resolves prefix then
                Some(parts[k..] |> Array.fold (fun e f -> Field(e, f)) (Var prefix))
            else
                None)

    /// A trait method, instantiated; its type parameter must implement the trait.
    and traitMethod (x: string) : CExpr =
        let tm = traitMethods[traitAliases[x]]
        let n = tm.nparams

        // the head needs the trait, with its other parameters (Iter<'a>), which the impl for the
        // head's type determines; then the method's ambient row
        let head =
            if n = 1 then kTrait tm.owner
            else { kTrait tm.owner with params = Map.ofList [ tm.owner, List.init (n - 1) (fun i -> TGen(i + 1)) ] }

        let kinds = head :: List.init (n - 1) (fun _ -> kAny) @ (if hasAmbient tm then [ kRow ] else [])
        let t, inst = instantiate kinds tm.ty
        let qname = tm.owner + "." + tm.name

        // through dyn, the ambient row is empty: checked once the value's type is known
        if hasAmbient tm then
            dynCalls.Add(inst[0], inst[n], tm.owner, tm.name, currentLine.Value)

        if tm.isConst then
            mk (CApp(mk (CGlobal(qname, Some inst)) (tfun tUnit t), [ mk CUnit tUnit ])) t
        else
            mk (CGlobal(qname, Some inst)) t

    /// The active pattern a case pattern uses at its top: (function, total?, args, case, value pattern).
    and activeOf (p: Pat) : (string * bool * Expr list * string * Pat option) option =
        let name, arg =
            match p with
            | PIdent(c, arg) -> Some c, arg
            | _ -> None, None

        match name |> Option.bind (resolveWith activePatterns.ContainsKey) with
        | Some c ->
            let fn, total, nargs = activePatterns[c]

            let atoms =
                match arg with
                | Some(PArgs ps) -> ps
                | Some p -> [ p ]
                | None -> []

            if atoms.Length < nargs then
                fail 0 (sprintf "active pattern '%s' needs %d argument(s)" c nargs)

            let toExpr p =
                match p with
                | PInt n -> Lit n
                | PStr s -> StrLit s
                | PBool b -> BoolLit b
                | PUnit -> UnitLit
                | PIdent(x, None) -> Var x
                | _ -> fail 0 "active pattern arguments must be literals or names"

            let args = atoms |> List.take nargs |> List.map toExpr

            let value =
                match List.skip nargs atoms with
                | [] -> None
                | [ v ] -> Some v
                | _ -> fail 0 (sprintf "too many patterns after active pattern '%s'" c)

            Some(fn, total, args, c, value)
        | None -> None

    /// A match whose cases use active patterns becomes a chain of plain matches, in case order:
    /// a run of ordinary cases matches the value; a run of one total active pattern matches its
    /// result; a partial one matches Some value. Each falls through (`_`) to the rest.
    and desugarActive (s: Expr) cases : Expr =
        let sv = uniq "$ap"

        let rec chain cases =
            let fallback rest =
                if List.isEmpty rest then [] else [ PWild, None, chain rest ]

            match cases with
            | [] -> failwith "unreachable"
            | (p, _, _) :: _ when (activeOf p).IsNone ->
                let group = cases |> List.takeWhile (fun (p, _, _) -> (activeOf p).IsNone)
                let rest = List.skip group.Length cases
                Match(Var sv, group @ fallback rest)
            | (p, g, b) :: rest ->
                let fn, total, args, c, value = (activeOf p).Value
                let call = Call(fn, args @ [ Var sv ])

                if total then
                    let same (p, _, _) =
                        match activeOf p with
                        | Some(fn2, true, args2, _, _) -> fn2 = fn && args2 = args
                        | _ -> false

                    let group = cases |> List.takeWhile same
                    let rest = List.skip group.Length cases

                    let cases' =
                        group
                        |> List.map (fun (p, g, b) ->
                            let _, _, _, c, value = (activeOf p).Value
                            PIdent(c, value), g, b)

                    Match(call, cases' @ fallback rest)
                else
                    if rest.IsEmpty then
                        fail 0 (sprintf "active pattern '%s' can fail; add a case after it" c)

                    Match(call, [ PIdent("Some", Some(defaultArg value PWild)), g, b ] @ fallback rest)

        Let(PIdent(sv, None), None, s, chain cases)

    /// A match on an active pattern function's result (made by desugarActive) uses its cases directly.
    and isActiveCall (e: Expr) =
        match e with
        | Call(f, _) -> activePatterns.Values |> Seq.exists (fun (fn, _, _) -> fn = f)
        | _ -> false

    /// What a name refers to, for go-to-definition: a local's unique name or a global's.
    and keyOf (env: Map<string, Local>) (x: string) =
        match env.TryFind x with
        | Some l -> l.u
        | None -> resolveName x |> Option.defaultValue ""

    and resolveName (x: string) : string option =
        resolveWith
            (fun q ->
                globals.ContainsKey q || ctors.ContainsKey q || traitAliases.ContainsKey q || builtins.ContainsKey q
                || externs.ContainsKey q || consts.ContainsKey q || globalValues.ContainsKey q || effectOps.ContainsKey q
                || (staticMember q).IsSome)
            x

    and value env depth x : CExpr =
        match env.TryFind x, resolveName x with
        | None, Some q when q <> x -> value' env depth q
        | _ -> value' env depth x

    and value' env depth x : CExpr =
        match env.TryFind x with
        | None when consts.ContainsKey x ->
            // a constant: its expression, typed here (a literal constant takes the type each use
            // needs), its type variables its own (it's generic: Map.empty at any type, twice in
            // one function too)
            if inlining.Contains x then
                fail 0 (sprintf "'%s' is defined in terms of itself" x)

            inlining.Add x |> ignore
            let saved = Dictionary<string, Ty>(tyvars)
            tyvars.Clear()

            try
                infer Map.empty depth consts[x]
            finally
                inlining.Remove x |> ignore
                tyvars.Clear()

                for kv in saved do
                    tyvars[kv.Key] <- kv.Value
        | None when globalValues.ContainsKey x -> mk (CGlobalVal x) globalValues[x]
        | Some l ->
            if l.mut && l.depth < depth then
                fail 0 (sprintf "mutable variable '%s' cannot be captured by a closure; use a ref cell (let x = ref …; x.Value <- …)" x)

            mk (CLocal l.u) l.ty
        | None ->
            match globals.TryGetValue x with
            | _ when not (globals.ContainsKey x) && (staticMember x).IsSome ->
                let m = (staticMember x).Value

                if m.isProperty then
                    memberCall env depth m None [] x
                else
                    fail 0 (sprintf "static method '%s' must be called: %s(...)" x x)
            | true, g when g.defining -> mk (CGlobal(x, None)) g.ty
            | true, g ->
                let t, inst = instantiate g.kinds g.ty
                opened g.arity (mk (CGlobal(x, Some inst)) t)
            | _ ->
                if ctors.ContainsKey x then
                    let u, tag = ctors[x]
                    let uty, targs = instType u

                    match caseFields u tag targs with
                    | [] -> mk (CCtor(u, tag, [])) uty
                    | [ ft ] when apCtors.Contains x ->
                        expect (sprintf "'%s' without a value" x) tUnit ft
                        mk (CCtor(u, tag, [ mk CUnit tUnit ])) uty
                    | [ ft ] ->
                        let p = uniq "$v"
                        mk (CLam([ p, ft ], mk (CCtor(u, tag, [ mk (CLocal p) ft ])) uty)) (TFun(ft, uty, fresh kRow))
                    | _ -> fail 0 (sprintf "constructor '%s' takes several fields; apply it as %s (a, b)" x x)
                elif traitAliases.ContainsKey x then
                    traitMethod x
                elif effectOps.ContainsKey x then
                    perform env depth x []
                elif builtins.ContainsKey x then
                    builtinCall env depth x []
                elif externs.ContainsKey x then
                    fail 0 (sprintf "C function '%s' must be called directly" x)
                else
                    match splitQualified env x with
                    | Some e -> infer env depth e
                    | None when skippedC.ContainsKey x -> fail 0 (sprintf "C name '%s' wasn't imported: %s" x skippedC[x])
                    | None -> unknown "name" x

    and call env depth f args : CExpr =
        match env.TryFind f, resolveName f with
        | None, Some q when q <> f -> call' env depth q args
        | _ -> call' env depth f args

    and call' env depth f args : CExpr =
        if not (env.ContainsKey f || globals.ContainsKey f) && (staticMember f).IsSome then
            memberCall env depth (staticMember f).Value None args f
        elif env.ContainsKey f || globals.ContainsKey f || globalValues.ContainsKey f || consts.ContainsKey f then
            // a function, or a top-level value holding one: let validate = parse >=> check
            apply env depth (value env depth f) args (Some f)
        elif ctors.ContainsKey f then
            ctor env depth f args
        elif traitAliases.ContainsKey f then
            apply env depth (traitMethod f) args (Some f)
        elif builtins.ContainsKey f then
            builtinCall env depth f args
        elif externs.ContainsKey f then
            externCall env depth f args
        elif effectOps.ContainsKey f then
            perform env depth f args
        elif f.Contains ".Builder." then
            // a computation expression's form, and its builder lacks the function for it
            let i = f.LastIndexOf '.'
            let fn = f.Substring(i + 1)
            let builder = f.Substring(0, i)
            let w = string (System.Char.ToLower builder[0]) + builder.Substring(1, builder.IndexOf '.' - 1)

            let form =
                match fn with
                | "bind" -> "let! and do!"
                | "ret" -> "return"
                | "zero" -> "an if without else, and a body that ends in a statement"
                | "using" -> "use"
                | "forEach" -> "for"
                | "delay" -> "its body"
                | _ -> fn

            if w = "async" then
                fail 0 "there's no async { }: write task { }, and run it with Task.run"

            fail 0 (sprintf "%s { } needs %s.%s, for %s" w builder fn form)
        else
            match splitQualified env f with
            | Some e -> infer env depth (App(e, args))
            | None when skippedC.ContainsKey f -> fail 0 (sprintf "C function '%s' wasn't imported: %s" f skippedC[f])
            | None -> unknown "function" f

    /// Type-checks arguments against a (curried) function type; returns them and the result type.
    and checkArgs env depth (fty: Ty) (args: Expr list) (name: string option) =
        let what i =
            match name with
            | Some f -> sprintf "argument %d of '%s'" (i + 1) f
            | None -> sprintf "argument %d" (i + 1)

        // a lambda with an unannotated parameter is typed after the other arguments, which may
        // tell it what it's applied to: List.map (fun s -> s.Length) names, and so
        // names |> List.map (fun s -> s.Length)
        let rec waits (a: Expr) =
            match a with
            | At(_, a) -> waits a
            | Lambda(ps, _) -> ps |> List.exists (fun (_, ann) -> ann.IsNone)
            | _ -> false

        // the parameter types the arguments meet, and the result (None: too many arguments)
        let rec peel (t: Ty) (k: int) (acc: Ty list) =
            if k = 0 then
                Some(List.rev acc, t)
            else
                match prune t with
                | TFun(p, r, row) ->
                    useRow row
                    peel r (k - 1) (p :: acc)
                | TVar _ as v ->
                    // a function not known yet: only the last arrow a call takes performs
                    let p, r, row = fresh kAny, fresh kAny, (if k = 1 then fresh kRow else rowEmpty)
                    expect "function" v (TFun(p, r, row))
                    useRow row
                    peel r (k - 1) (p :: acc)
                | _ -> None

        // a share<F> passed where a plain function is expected is one (share.as keeps the
        // value's own type inside, for the check of what crosses threads)
        let unshare (p: Ty) (ca: CExpr) =
            match prune p, prune ca.ty with
            | TFun _, TCon("share", [ f ]) -> mk (CPrim("share.as", [ ca ])) f
            | _ -> ca

        match (if args |> List.exists waits then peel fty args.Length [] else None) with
        | Some(ps, res) ->
            let typed = Array.zeroCreate args.Length
            let indexed = List.indexed args

            for i, a in (indexed |> List.filter (snd >> waits >> not)) @ (indexed |> List.filter (snd >> waits)) do
                let p = List.item i ps
                let ca = unshare p (inferHint env depth p a)
                expect (what i) p ca.ty
                typed[i] <- ca

            List.ofArray typed, res
        | None ->
            let t = ref fty

            let cargs =
                args
                |> List.mapi (fun i a ->
                    let ca =
                        match prune t.Value with
                        | TFun(p, _, _) -> unshare p (inferHint env depth p a)
                        | _ -> infer env depth a

                    match prune t.Value with
                    | TFun(p, r, row) ->
                        expect (what i) p ca.ty
                        useRow row
                        t.Value <- r
                    | TVar _ ->
                        // a function not known yet: only the last arrow a call takes performs
                        let r, row = fresh kAny, (if i = args.Length - 1 then fresh kRow else rowEmpty)
                        expect "function" t.Value (TFun(ca.ty, r, row))
                        useRow row
                        t.Value <- r
                    | ty ->
                        match name with
                        | Some f -> fail 0 (sprintf "'%s' is applied to too many arguments" f)
                        | None -> fail 0 (sprintf "this value is not a function; it has type %s" (show ty))

                    ca)

            cargs, t.Value

    and apply env depth (ch: CExpr) (args: Expr list) (name: string option) : CExpr =
        // a function called is called as it is (its row is met at each arrow the call takes)
        let ch =
            match ch.k with
            | CPrim("eff.open", [ g ]) -> g
            | _ -> ch

        match prune ch.ty with
        | TCon("fnptr", [ f ]) -> fnptrCall env depth ch f args
        | TCon("share", [ f ]) ->
            // called as any function (the callee keeps its type: what crosses threads is checked by it)
            let cargs, t = checkArgs env depth f args name
            mk (CApp(ch, cargs)) t
        | _ ->
            let cargs, t = checkArgs env depth ch.ty args name
            mk (CApp(ch, cargs)) t

    /// A call through a C function pointer (fnptr<A -> B -> R>), inside `unsafe`: with all its
    /// arguments at once, passed as to an extern.
    and fnptrCall env depth (fp: CExpr) (f: Ty) (args: Expr list) : CExpr =
        if not unsafeOn.Value then
            fail 0 "calling a C function pointer is unsafe: call it inside `unsafe`"

        let rec split t =
            match prune t with
            | TFun(a, r, _) ->
                let ps, res = split r
                a :: ps, res
            | r -> [], r

        let ps, ret = split f
        let ps = ps |> List.filter (fun p -> prune p <> tUnit)
        let args = if ps.IsEmpty && args = [ UnitLit ] then [] else args

        if args.Length <> ps.Length then
            fail 0 (sprintf "this C function pointer takes %d argument(s), got %d" ps.Length args.Length)

        let cargs =
            List.mapi2
                (fun i p a ->
                    let ca = inferHint env depth p a
                    let what = sprintf "argument %d of the C function pointer" (i + 1)
                    // a string is passed to C as a pointer to its bytes
                    if prune p = tCStr then expect what (fresh kStrLit) ca.ty else expect what p ca.ty
                    ca)
                ps
                args

        mk (CPrim("fnptr.call", fp :: cargs)) ret

    and builtinCall env depth name (args: Expr list) : CExpr =
        if unsafeBuiltins.Contains name && not unsafeOn.Value then
            if name = "Collections.Span.ofPtr" then
                fail 0 "Span.ofPtr needs unsafe: the memory's lifetime isn't checked"

            fail 0 (sprintf "'%s' is unsafe: use it inside `unsafe`" name)

        let b = builtins[name]
        let t, _ = instantiate b.kinds b.ty
        let cargs, finalTy = checkArgs env depth t args (Some name)

        let cargs =
            if overWindows.Contains b.prim then
                cargs
                |> List.map (fun c ->
                    match c.k with
                    | CPrim(("span.ofArray" | "span.ofBuffer"), [ x ]) -> x
                    | _ -> c)
            else
                cargs
        let ptys, resTy = peel b.arity t

        if cargs.Length >= b.arity then
            let first, rest = List.splitAt b.arity cargs
            let prim = mk (CPrim(b.prim, first)) resTy
            if rest.IsEmpty then prim else mk (CApp(prim, rest)) finalTy
        else
            // partial application: bind the given arguments, then a lambda over the rest
            let given = cargs |> List.map (fun c -> uniq "$a", c)
            let ps = ptys |> List.skip given.Length |> List.map (fun pt -> uniq "$b", pt)
            let callArgs = (given |> List.map (fun (u, c) -> mk (CLocal u) c.ty)) @ (ps |> List.map (fun (u, t) -> mk (CLocal u) t))
            let lam = mk (CLam(ps, mk (CPrim(b.prim, callArgs)) resTy)) (funTy (List.map snd ps) resTy)
            List.foldBack (fun (u, c) acc -> mk (CLet(u, c, acc)) acc.ty) given lam

    and externCall env depth f (args: Expr list) : CExpr =
        let s = externs[f]
        let args = if s.pars.IsEmpty && args = [ UnitLit ] then [] else args
        let n = s.pars.Length

        if args.Length < n || (args.Length > n && not s.variadic) then
            fail 0 (sprintf "'%s' expects %d argument(s), got %d" f n args.Length)

        let cargs =
            args
            |> List.mapi (fun i a ->
                // the declared parameter type guides a record literal ({ x = 1; y = 2 } for Point),
                // and a callback's what it's given (a share<F> one is checked as crossing threads)
                let ca =
                    if i >= n then infer env depth a
                    else
                        match s.pars[i] with
                        | TCon("callback", [ f ]) -> inferHint env depth f a
                        | t -> inferHint env depth t a

                if i < n then
                    let what = sprintf "argument %d of '%s'" (i + 1) f
                    // a string is passed to C as a pointer to its bytes; a closure as callback + user data
                    match s.pars[i] with
                    | t when t = tCStr -> expect what (fresh kStrLit) ca.ty
                    | TCon("callback", [ f ]) -> expectNoEffects "a function given to C must have no effects: this one performs %s (the C-callback rule)" what f ca.ty
                    | t -> expect what t ca.ty

                ca)

        mk (CExtern(f, cargs)) s.ret

    and ctor env depth c (args: Expr list) : CExpr =
        let u, tag = ctors[c]
        let uty, targs = instType u
        let fields = caseFields u tag targs

        let isNamed a =
            match a with
            | Bin("=", Var n, _) -> List.contains (Some n) ctorFieldNames[c]
            | _ -> false

        let named =
            match args with
            | [ a ] when isNamed a -> Some [ a ]
            | [ Tuple xs ] when List.forall isNamed xs -> Some xs
            | _ -> None

        let args =
            match named with
            | Some xs ->
                // Circle(radius = 2.0): every field by name, in any order
                let given = xs |> List.map (function
                    | Bin(_, Var n, v) -> n, v
                    | _ -> failwith "unreachable")

                if (given |> List.map fst |> List.distinct).Length <> given.Length then
                    fail 0 (sprintf "a field of '%s' is given twice" c)

                ctorFieldNames[c]
                |> List.map (fun n ->
                    match given |> List.tryFind (fun (m, _) -> Some m = n) with
                    | Some(_, v) -> v
                    | None ->
                        match n with
                        | Some n -> fail 0 (sprintf "constructor '%s' is missing field '%s'" c n)
                        | None -> fail 0 (sprintf "constructor '%s' has unnamed fields; pass them by position" c))
            | None ->
                ctorArgs c args fields (function
                    | Tuple xs -> Some xs
                    | _ -> None) None

        let cargs =
            List.map2
                (fun a ft ->
                    let ca = inferHint env depth ft a
                    expect (sprintf "argument of '%s'" c) ft ca.ty
                    ca)
                args
                fields

        mk (CCtor(u, tag, cargs)) uty

    /// Like infer, but the record literals that produce the value may use the expected type to
    /// pick their record.
    /// A list or array expression, [ for x in xs do … yield e ]. One `for` over a list, an array
    /// or an int range, filtered by `if`s, whose parts are pure as fusion takes it (arithmetic on
    /// immutable locals), is the pipeline fusion makes one loop of: List.init over a range, a
    /// filter per `if`, a map to what's yielded (no filter for an array). Any other body runs in
    /// order: a loop consing what it yields onto a list, reversed in place at the end.
    /// E.op args: the operation performed, which puts E in the row of the function it's in; a
    /// function performing it when given fewer arguments.
    and perform env depth (q: string) (args: Expr list) : CExpr =
        let eff, i = effectOps[q]
        let info = effects[eff]
        let op = info.ops[i]
        let targs = List.init info.npars (fun _ -> fresh kAny)
        let inst = targs @ List.init op.own (fun _ -> fresh kAny)
        let ptys = op.pars |> List.map (substGen inst)
        let ret = substGen inst op.ret
        let label = TCon(eff, targs)

        if args.Length >= ptys.Length then
            let now, later = List.splitAt ptys.Length args
            let cargs, _ = checkArgs env depth (funTyRow ptys ret (rowExt label rowEmpty)) now (Some q)
            let p = mk (CPerform(label, i, cargs)) ret
            if later.IsEmpty then p else apply env depth p later None
        else
            // the operation as a value: a lambda performing it (with the arguments given first)
            let given = args |> List.mapi (fun j a -> (let c = inferHint env depth ptys[j] a in expect (sprintf "argument %d of '%s'" (j + 1) q) ptys[j] c.ty; uniq "$a", c))
            let ps = ptys |> List.skip given.Length |> List.map (fun t -> uniq "$b", t)
            let all = (given |> List.map (fun (u, c) -> mk (CLocal u) c.ty)) @ (ps |> List.map (fun (u, t) -> mk (CLocal u) t))
            let lam = mk (CLam(ps, mk (CPerform(label, i, all)) ret)) (funTyRow (List.map snd ps) ret (rowExt label (fresh kRow)))
            List.foldBack (fun (u, c) acc -> mk (CLet(u, c, acc)) acc.ty) given lam

    /// handle body with clauses: the body performs the effect (in front of what the handle's
    /// own body may), each clause gives an operation's meaning, its resumption a function from
    /// the operation's result to the handle's; the return clause maps the body's result (as it is
    /// when left out). The clauses perform in the handle's own row.
    and handleExpr env depth (body: Expr) (ops: (string * Pat list * string * Expr) list) (ret: (Pat * Expr) option) : CExpr =
        if ops.IsEmpty then
            fail 0 "a handle has a clause for each operation of its effect: | Effect.op x, k -> …"

        let opOf (q: string) =
            match resolveWith effectOps.ContainsKey q with
            | Some full -> full
            | None ->
                // the effect known, not the operation: name the ones it has
                let dot = q.LastIndexOf '.'

                match (if dot > 0 then resolveWith effects.ContainsKey (q.Substring(0, dot)) else None) with
                | Some e ->
                    let names = effects[e].ops |> List.map (fun o -> o.name)
                    fail 0 (sprintf "effect %s has no operation '%s' (%s)" (shortName e) (q.Substring(dot + 1)) (String.concat ", " names))
                | None -> fail 0 (sprintf "unknown operation '%s': a clause names an effect's operation, Effect.op" q)

        let clauses =
            ops
            |> List.map (fun (q, ps, k, b) ->
                let full = opOf q
                let e, i = effectOps[full]
                let o = effects[e].ops[i]
                let label = TCon(e, List.init effects[e].npars TGen)
                // a reference to the operation, for hover and references
                recordKey q (shortName full) (funTyRow o.pars o.ret (rowExt label rowEmpty)) false full false
                full, ps, k, b)

        let eff = fst effectOps[(let q, _, _, _ = clauses.Head in q)]

        for q, _, _, _ in clauses do
            if fst effectOps[q] <> eff then
                fail 0 (sprintf "a handle is for one effect: %s's clause needs a handle of its own (around this one, or inside it)" (shortName q))

        let info = effects[eff]

        match clauses |> List.countBy (fun (q, _, _, _) -> q) |> List.tryFind (fun (_, n) -> n > 1) with
        | Some(q, _) -> fail 0 (sprintf "operation %s has two clauses" (shortName q))
        | None -> ()

        let covered = clauses |> List.map (fun (q, _, _, _) -> snd effectOps[q]) |> Set.ofList

        for i, o in List.indexed info.ops do
            if not (covered.Contains i) then
                fail 0 (sprintf "this handle of %s has no clause for %s" (shortName eff) (shortName eff + "." + o.name))

        let targs = List.init info.npars (fun _ -> fresh kAny)
        let label = TCon(eff, targs)
        let outer = ctxRow.Value
        let cb = withRowAs (rowExt label outer) ctxWhat.Value (fun () -> infer env depth body)
        let ans = fresh kAny

        let bindPattern (p: Pat) (t: Ty) =
            let names = Dictionary<string, string>()
            let cp = pat names p t
            let vars = patVars cp

            let env' =
                names
                |> Seq.fold
                    (fun (m: Map<_, _>) kv ->
                        m.Add(
                            kv.Key,
                            { u = kv.Value
                              ty = vars |> List.find (fst >> (=) kv.Value) |> snd
                              mut = false
                              depth = depth }
                        ))
                    env

            cp, env'

        let rv = uniq "$handled"

        let retBody =
            match ret with
            | Some(p, rb) ->
                let cp, env' = bindPattern p cb.ty
                Match.check unionCases apCtors.Contains [ cp, false ]
                let crb = infer env' depth rb
                expect "the return clause" ans crb.ty
                mk (CMatch(mk (CLocal rv) cb.ty, [ cp, None, crb ])) ans
            | None ->
                expect "the handled expression" ans cb.ty
                mk (CLocal rv) cb.ty

        let what = match ret with Some _ -> "the return clause" | None -> "the handled expression"

        let cclauses =
            clauses
            |> List.map (fun (q, ps, k, b) ->
                let i = snd effectOps[q]
                let op = info.ops[i]
                // the operation's own type variables stand for any type: a clause can't choose one
                let own = List.init op.own (fun _ -> TCon(uniq "$sk", []))
                let inst = targs @ own
                let ptys = op.pars |> List.map (substGen inst)
                let rty = substGen inst op.ret

                if ps.Length <> ptys.Length then
                    fail 0 (sprintf "operation %s takes %d argument(s), this clause has %d" (shortName q) ptys.Length ps.Length)

                let named, body = lowerParams (ps |> List.map (fun p -> p, None)) b
                let pars = List.map2 (fun (x, _) t -> x, uniq x, t) named ptys
                recordParams (ps |> List.map (fun p -> p, None)) pars
                let kty = TFun(rty, ans, outer)
                let ku = uniq k

                let envC =
                    pars
                    |> List.fold (fun (m: Map<_, _>) (x, u, t) -> m.Add(x, { u = u; ty = t; mut = false; depth = depth })) env
                    |> fun m -> if k = "_" then m else m.Add(k, { u = ku; ty = kty; mut = false; depth = depth })

                let cbody = infer envC depth body

                try
                    unify ans cbody.ty
                with Mismatch | NoImpl _ ->
                    fail 0 (sprintf "clause %s gives %s, %s %s" (shortName q) (show cbody.ty) what (show ans))

                i, pars |> List.map (fun (_, u, t) -> u, t), (ku, kty), cbody)

        let rec skolem (t: Ty) =
            match prune t with
            | TCon(n, ts) -> n.StartsWith "$sk" || List.exists skolem ts
            | TTuple ts -> List.exists skolem ts
            | TFun(a, b, r) -> skolem a || skolem b || skolem r
            | _ -> false

        if skolem ans then
            fail 0 "a handle's result can't have an operation's own type (it stands for any type, chosen where the operation is performed)"

        mk (CHandle(label, cb, cclauses, (rv, cb.ty), retBody)) ans

    and listExpression env depth (isArray: bool) (body: Expr) : CExpr =
        let rec strip e =
            match e with
            | At(_, a) -> strip a
            | e -> e

        // the filters (outermost first) and the yielded value under the for
        let rec stages e =
            match strip e with
            | If(c, t, None) -> stages t |> Option.map (fun (fs, y) -> c :: fs, y)
            | Yield y -> Some([], y)
            | _ -> None

        let rec fusible (locals: Set<string>) e =
            match e with
            | Lit _
            | FloatLit _
            | BoolLit _
            | CharLit _
            | UnitLit -> true
            | Var x -> locals.Contains x || env.TryFind x |> Option.exists (fun l -> not l.mut)
            | Bin(op, a, b) -> pureOps.Contains op && fusible locals a && fusible locals b
            | Neg a
            | Not a
            | At(_, a) -> fusible locals a
            | If(c, t, Some f) -> fusible locals c && fusible locals t && fusible locals f
            | Let(PIdent(x, None), None, v, b) -> fusible locals v && fusible (locals.Add x) b
            | _ -> false

        let lam x e = Lambda([ PIdent(x, None), None ], e)
        let cons y = Assign(Var "$acc", Call("::", [ Tuple [ y; Var "$acc" ] ]))

        let rec yields e =
            match e with
            | At(l, a) -> At(l, yields a)
            | Yield y -> cons y
            | YieldAll ys -> ForIn("$y", ys, cons (Var "$y"))
            | ForIn(x, xs, b) -> ForIn(x, xs, yields b)
            | For(x, a, s, b, body) -> For(x, a, s, b, yields body)
            | If(c, t, f) -> If(c, yields t, Option.map yields f)
            | Match(s, cases) -> Match(s, cases |> List.map (fun (p, g, b) -> p, g, yields b))
            | Let(p, t, v, b) -> Let(p, t, v, yields b)
            | Seq(a, b) -> Seq(yields a, yields b)
            | e -> e

        let inOrder env (b: Expr) =
            let built = Call("Collections.List.rev", [ Var "$acc" ])
            let result = if isArray then Call("Collections.Array.ofList", [ built ]) else built
            infer env depth (LetMut("$acc", None, Var "[]", Seq(yields b, result)))

        // e with c bound to name, inferred once; in a pipeline, c put where it's used (pure, or
        // used once), so the pipeline is one fusion sees whole under a consumer (List.sum [ … ])
        let bound name (c: CExpr) (putIn: bool) env (k: Map<string, Local> -> bool * CExpr) =
            let l =
                { u = uniq name
                  ty = c.ty
                  mut = false
                  depth = depth }

            let piped, r = k (Map.add name l env)

            let rec put (e: CExpr) =
                match e.k with
                | CLocal v when v = l.u -> c
                | k -> { e with k = mapChildren put k }

            piped, (if piped && putIn then put r else mk (CLet(l.u, c, r)) r.ty)

        let piped env (x: string) (filters: Expr list) (y: Expr) (src: Expr) =
            let m = if isArray then "Collections.Array." else "Collections.List."
            let filtered = filters |> List.fold (fun xs c -> Call(m + "filter", [ lam x c; xs ])) src
            true, infer env depth (Call(m + "map", [ lam x y; filtered ]))

        let inOrder env b = false, inOrder env b

        let pureStages x (filters, y) =
            (not isArray || List.isEmpty filters) && List.forall (fusible (Set.singleton x)) (y :: filters)

        match strip body with
        | ForIn(x, xs, b) when not (x.StartsWith "$") ->
            let cxs = infer env depth xs
            settle cxs.ty

            bound "$coll" cxs true env (fun env ->
                match prune cxs.ty, stages b with
                | TCon("list", _), Some st when pureStages x st && not isArray -> piped env x (fst st) (snd st) (Var "$coll")
                | TCon("array", _), Some st when pureStages x st ->
                    piped env x (fst st) (snd st) (if isArray then Var "$coll" else Call("Collections.Array.toList", [ Var "$coll" ]))
                | _ -> inOrder env (ForIn(x, Var "$coll", b)))
            |> snd
        | For(x, lo, None, hi, b) ->
            let clo = infer env depth lo
            let chi = infer env depth hi
            expect "range" clo.ty chi.ty

            match prune clo.ty with
            | TVar _ -> expect "range" tInt clo.ty
            | _ -> ()

            bound "$lo" clo (fusible Set.empty lo) env (fun env ->
                bound "$hi" chi true env (fun env ->
                    match prune clo.ty, stages b with
                    | TCon("int", []), Some st when pureStages x st ->
                        let m = if isArray then "Collections.Array." else "Collections.List."
                        let n = Bin("+", Bin("-", Var "$hi", Var "$lo"), Lit 1L)
                        piped env x (fst st) (snd st) (Call(m + "init", [ n; lam "$k" (Bin("+", Var "$lo", Var "$k")) ]))
                    | _ -> inOrder env (For(x, Var "$lo", None, Var "$hi", b))))
            |> snd
        | _ -> inOrder env body |> snd

    and inferHint env depth (hint: Ty) (e: Expr) : CExpr =
        pushHint hint e
        infer env depth e

    /// Notes the expected type on the record literals and lambdas that produce e's value: through
    /// if and match branches, the tails of let and sequences, and tuple, list and array elements.
    and pushHint (hint: Ty) (e: Expr) =
        // a dyn Trait goes on to the expressions that give the value, through branches and tails
        let passes =
            match e with
            | At _
            | If(_, _, Some _)
            | Match _
            | Seq _
            | Let _
            | LetMut _
            | LetFun _
            | LetRecGroup _
            | Unsafe _ -> true
            | _ -> false

        match prune hint with
        | TCon(n, []) when isDynName n && not passes -> dynHints[e] <- hint
        | TCon("span", [ _ ]) when not passes -> spanHints[e] <- hint
        | TCon("share", [ f ]) when not passes ->
            shareHints[e] <- hint
            pushInto f e // a lambda's parameters get their types
        | _ -> pushInto hint e

    /// pushHint's structural part.
    and pushInto (hint: Ty) (e: Expr) =
        match e with
        | At(_, a)
        | Unsafe a
        | Neg a -> pushHint hint a
        | Lambda _ ->
            match prune hint with
            | TFun _ -> lambdaHints[e] <- hint
            | _ -> ()
        | Measured _ ->
            match prune hint with
            | TCon(n, _) when nums.Contains n -> measuredHints[e] <- TCon(n, [])
            | _ -> ()
        | RecordLit _ ->
            // only a record type helps (a generic 'a from a constructor mustn't replace it)
            match prune hint with
            | TCon(n, _) when records.Contains n -> recordHints[e] <- hint
            | _ -> ()
        | If(_, t, Some f) ->
            pushHint hint t
            pushHint hint f
        | Match(_, cases) ->
            for _, _, b in cases do
                pushHint hint b
        | Seq(_, b)
        | Let(_, _, _, b)
        | LetMut(_, _, _, b)
        | LetFun(_, _, _, _, _, b)
        | LetRecGroup(_, b) -> pushHint hint b
        | Tuple xs ->
            match prune hint with
            | TTuple ts when ts.Length = xs.Length -> List.iter2 pushHint ts xs
            | _ -> ()
        | Call("::", [ Tuple [ h; t ] ]) -> // a list literal is a chain of ::
            match prune hint with
            | TCon("list", [ el ]) ->
                pushHint el h
                pushHint hint t
            | _ -> ()
        | ArrayLit xs ->
            match prune hint with
            | TCon(("array" | "Buffer"), [ el ]) -> List.iter (pushHint el) xs
            | _ -> ()
        | _ -> ()

    /// The expected type noted on a record literal, used once (C constants share one node).
    and takeHint (e: Expr) =
        match recordHints.TryGetValue e with
        | true, t ->
            recordHints.Remove e |> ignore
            Some t
        | _ -> None

    /// The record a literal builds: the expected type if it is a record; otherwise the only
    /// record in scope whose fields fit (all given fields exist, all missing ones have defaults).
    /// That record is kept for the literal: a constant's, typed again at each use, means the
    /// record its own module sees.
    and recordLit env depth (hint: Ty option) (node: Expr) (fields: (string * Expr) list) : CExpr =
        let given = fields |> List.map fst

        let fits r =
            let defs = List.zip (fieldsOf r) recordDefaults[r]

            given |> List.forall (fun f -> defs |> List.exists (fun ((g, _), _) -> g = f))
            && defs |> List.forall (fun ((g, _), d) -> d.IsSome || List.contains g given)

        let rname =
            match hint |> Option.map prune with
            | Some(TCon(n, _)) when records.Contains n -> n
            | _ when literalRecords.ContainsKey node -> literalRecords[node]
            | _ ->
                match records |> Seq.filter fits |> inScope with
                | [ r ] -> r
                | [] -> recordOf (fresh kAny) given.Head // the precise error comes from buildRecord
                | many ->
                    let exact = many |> List.filter (fun r -> (fieldsOf r).Length = given.Length)

                    if exact.IsEmpty then
                        fail 0 (sprintf "record literal could be any of %s; add a type annotation" (String.concat ", " many))
                    else
                        List.last exact

        literalRecords[node] <- rname
        let rty, targs = instType rname
        let defaults = recordDefaults[rname]

        let built =
            buildRecord env depth rname targs fields (fun i scope ->
                let f, ft = List.item i (fieldsOf rname)
                let ft = substGen targs ft

                match defaults[i] with
                | Some d ->
                    let ce = inferHint scope 0 ft d
                    expect (sprintf "default of field '%s'" f) ft ce.ty
                    ce
                | None -> fail 0 (sprintf "record '%s' is missing field '%s'" rname f))

        built

    /// Binds each given field to a temporary in source order (preserving evaluation order),
    /// then each missing field, in declaration order, to fallback i scope, where scope holds
    /// the fields declared before it. Builds the record from the temporaries.
    and buildRecord env depth rname targs (fields: (string * Expr) list) (fallback: int -> Map<string, Local> -> CExpr) : CExpr =
        let defs = fieldsOf rname

        let named =
            fields
            |> List.map (fun (f, e) ->
                match defs |> List.tryFindIndex (fst >> (=) f) with
                | None -> fail 0 (sprintf "record '%s' has no field '%s'" rname f)
                | Some i ->
                    let ft = substGen targs (snd defs[i])
                    let ce = inferHint env depth ft e
                    expect (sprintf "field '%s'" f) ft ce.ty
                    f, ce, uniq "$f")

        if (named |> List.map (fun (f, _, _) -> f) |> List.distinct).Length <> named.Length then
            fail 0 "a field is given twice"

        let mutable scope = Map.empty
        let filled = ResizeArray()

        let temps =
            defs
            |> List.mapi (fun i (f, _) ->
                let tmp, ty =
                    match named |> List.tryFind (fun (g, _, _) -> g = f) with
                    | Some(_, ce, tmp) -> tmp, ce.ty
                    | None ->
                        let ce = fallback i scope
                        let tmp = uniq "$f"
                        filled.Add(tmp, ce)
                        tmp, ce.ty

                scope <-
                    scope.Add(
                        f,
                        { u = tmp
                          ty = ty
                          mut = false
                          depth = 0 }
                    )

                mk (CLocal tmp) ty)

        let body = mk (CTuple temps) (TCon(rname, targs))
        let body = List.foldBack (fun (tmp, ce: CExpr) acc -> mk (CLet(tmp, ce, acc)) acc.ty) (List.ofSeq filled) body
        List.foldBack (fun (_, ce, tmp) acc -> mk (CLet(tmp, ce, acc)) acc.ty) named body

    /// Type-checks functions that may refer to each other (pre-registered when isRec), then
    /// generalizes each; with joint (let rec … and …), all of them together, so they share one
    /// numbering of their type variables (a call between them uses the caller's instantiation).
    let defineGroupWith
        (joint: bool)
        (items: (int * string * bool * Param list * SType option * Expr * (unit -> Ty) option) list)
        : (Global * Dictionary<string, Ty>) list =
        let prepared =
            items
            |> List.map (fun (ln, name, isRec, ps0, ret, body, expected) ->
                try
                    tyvars.Clear()
                    let ps, body = lowerParams ps0 body
                    let pars = ps |> List.map (fun (x, ann) -> x, uniq x, annot ann)
                    recordParams ps0 pars
                    let rty, declared = annotRet ret
                    // the body's effects (a function without parameters performs none)
                    let row = if pars.IsEmpty then rowEmpty else declared |> Option.defaultWith (fun () -> fresh kRow)

                    let what =
                        match declared, expected with
                        | _ when exporting.Value -> sprintf "'%s', which C calls (the C-callback rule)," name
                        | _, Some _ -> sprintf "'%s', a trait's method," name
                        | Some r, _ when isRowEmpty r -> sprintf "'%s', declared to perform nothing," name
                        | Some r, _ -> sprintf "'%s', declared to perform %s," name (effectsText r)
                        | None, _ when pars.IsEmpty -> sprintf "'%s', which takes no parameters," name
                        | None, _ -> ""

                    let fty = funTyRow (pars |> List.map (fun (_, _, t) -> t)) rty row

                    // an export's functions, and those it takes and gives, have no effects (the
                    // C-callback rule): its rows are closed before its body is checked
                    if exporting.Value then
                        let rec close (t: Ty) =
                            match prune t with
                            | TFun(a, b, r) ->
                                close a
                                close b

                                match prune (snd (rowParts r)) with
                                | TVar v -> v.Value <- Link rowEmpty
                                | _ -> ()
                            | TCon(_, ts)
                            | TTuple ts -> List.iter close ts
                            | _ -> ()

                        close fty

                    match expected with
                    | Some f -> expect (sprintf "'%s' does not match the trait's signature" name) (f ()) fty
                    | None -> ()

                    let g =
                        { ty = fty
                          kinds = []
                          arity = pars.Length
                          defining = true }

                    if isRec then
                        globals[name] <- g

                    ln, name, pars, rty, fty, g, body, Dictionary<string, Ty>(tyvars), (row, what)
                with CompileError(0, msg) ->
                    fail ln msg)

        let bodies =
            prepared
            |> List.map (fun (ln, name, pars, rty, _, _, body, tvs, (row, what)) ->
                try
                    tyvars.Clear()

                    for kv in tvs do
                        tyvars[kv.Key] <- kv.Value

                    let env =
                        pars
                        |> List.fold
                            (fun (m: Map<_, _>) (x, u, t) ->
                                m.Add(
                                    x,
                                    { u = u
                                      ty = t
                                      mut = false
                                      depth = 0 }
                                ))
                            Map.empty

                    currentDef <- name
                    let cb = withRowAs row what (fun () -> inferHint env 0 rty body)
                    currentDef <- ""
                    expect (sprintf "result of '%s'" name) rty cb.ty
                    cb
                with CompileError(0, msg) ->
                    fail ln msg)

        let jointKinds =
            if joint then
                Some(generalize (TTuple(prepared |> List.map (fun (_, _, _, _, fty, _, _, _, _) -> fty))))
            else
                None

        [ for (ln, name, pars, rty, fty, g, _, tvs, (row, _)), cb in List.zip prepared bodies do
              if name = "main" then
                  resolve fty |> ignore

              g.kinds <-
                  match jointKinds with
                  | Some ks -> ks
                  | None -> generalize fty
              g.defining <- false
              globals[name] <- g

              funs.Add
                  { name = name
                    pars = pars |> List.map (fun (_, u, t) -> u, t)
                    ret = rty
                    row = row
                    body = cb
                    ngen = g.kinds.Length
                    rows = g.kinds |> List.filter isRowKind |> List.length
                    file = currentFile.Value
                    line = ln }

              yield g, tvs ]

    let defineGroup items =
        defineGroupWith false (items |> List.map (fun (ln, n, r, ps, ret, b) -> ln, n, r, ps, ret, b, None)) |> ignore

    let defineRecGroup items =
        defineGroupWith true (items |> List.map (fun (ln, n, r, ps, ret, b) -> ln, n, r, ps, ret, b, None)) |> ignore

    /// Members become functions `Type#Name`: self first (instance members), then parameters;
    /// an optional parameter without a default is an option in the body.
    let declareMembers (tname: string) (tparams: string list) (ms: Member list) =
        if not (members.ContainsKey tname) then
            members[tname] <- []
            memberTypeNames.Add(tname.Substring(tname.LastIndexOf '.' + 1)) |> ignore

        let items =
            ms
            |> List.map (fun m ->
                if members[tname] |> List.exists (fst >> (=) m.name) then
                    fail m.mline (sprintf "'%s' already has a member '%s'" tname m.name)

                if not m.isStatic && List.contains m.name (match types.TryGetValue tname with
                                                           | true, { def = RecordDef fs } -> List.map fst fs
                                                           | _ -> []) then
                    fail m.mline (sprintf "member '%s' has the same name as a field of '%s'" m.name tname)

                let gname = tname + "#" + m.name
                let ps = m.mpars |> Option.defaultValue []

                let mps =
                    ps
                    |> List.map (fun p ->
                        let ann =
                            match p.optional, p.mdefault with
                            | true, None -> Some(STName("option", [ defaultArg p.mty (STVar("$opt." + p.mname)) ]))
                            | _ -> p.mty

                        PIdent(p.mname, None), ann)

                let selfPar =
                    m.self
                    |> Option.map (fun v -> PIdent(v, None), Some(STName(tname, tparams |> List.map STVar)))
                    |> Option.toList

                let allPars = selfPar @ mps
                let allPars = if allPars.IsEmpty then [ PUnit, None ] else allPars

                // a new list: a module extending another's type writes the type's members anew
                members[tname] <-
                    members[tname]
                    @ [ m.name,
                        { gname = gname
                          isStatic = m.isStatic
                          isProperty = m.mpars.IsNone
                          mpars = ps } ]

                m.mline, gname, true, allPars, m.mret, m.mbody)

        defineGroup items

    /// Types that can cross the C boundary: numbers, bool, cstr, cptr, unit, [<CLayout>] records,
    /// typed pointers to those (ptr<T>) and C function pointers (fnptr<A -> R>).
    let rec checkCType (what: string) (t: Ty) =
        match prune t with
        | TCon(n, []) when nums.Contains n || n = "bool" || n = "cstr" || n = "cptr" || n = "unit" -> ()
        | TCon(n, []) when clayouts.Contains n -> ()
        | TCon("ptr", [ p ]) ->
            match prune p with
            | TCon("unit", []) -> ()
            | p -> checkCType what p
        | TCon("fnptr", [ f ]) -> checkFnPtr what f
        | TCon("fixed", [ el; _ ]) when what.StartsWith "[<CLayout>] field" -> checkCType what el // C's T[N]
        | TCon("fixed", _) ->
            fail 0 (sprintf "%s: a fixed-size array crosses to C in a [<CLayout>] record's field; C takes an array parameter as a pointer to its first element" what)
        | t -> fail 0 (sprintf "%s: type %s cannot cross the C boundary (mark records [<CLayout>])" what (show t))

    /// fnptr<A -> B -> R>: a C function pointer R (*)(A, B), its parameters and result C types
    /// (unit -> R takes none).
    and checkFnPtr (what: string) (f: Ty) =
        match prune f with
        | TFun(a, r, _) ->
            checkCType what a

            match prune r with
            | TFun _ -> checkFnPtr what r
            | r -> checkCType what r
        | t -> fail 0 (sprintf "%s: fnptr<%s> needs a function type such as fnptr<i32 -> i32>" what (show t))

    /// A Z# value C holds as an opaque handle (zs_handle, with zs_retain and zs_release): a
    /// reference-counted object such as a union's cell, an array, a ref, a closure or a dyn value.
    /// Strings cross as their bytes instead, and records and tuples are values.
    let isHandle (t: Ty) =
        match prune t with
        | TCon("string", _)
        | TTuple _ -> false
        | TCon(n, _) when (match types.TryGetValue n with
                           | true, { def = RecordDef _ } -> true
                           | _ -> false) -> false
        | t -> needsRc types.Dict t

    /// A parameter or result of an extern or an export: a C type, or a handle.
    let checkCArg (what: string) (t: Ty) =
        match prune t with
        | TCon("span", _) -> fail 0 (sprintf "%s: a span can't come from C: it needs an owner" what)
        | _ -> if not (isHandle t) then checkCType what t

    /// callback<A -> R>: C sees (R (*)(void* user, A), void* user); A and R are C types.
    /// callback<share<A -> R>>: C may call it on any thread (a share<A -> R> is given).
    let rec checkCallback (what: string) (f: Ty) =
        match prune f with
        | TCon("share", [ g ]) -> checkCallback what g
        | TFun(a, r, _) ->
            checkCType what a
            checkCType what r
        | t -> fail 0 (sprintf "%s: callback<%s> needs a function type such as callback<int -> unit>" what (show t))

    /// Registers an impl and type-checks its methods. The impl is registered before its
    /// bodies so they may use it recursively; its requirements on type arguments are inferred.
    let declareImpl (tr: string) (head: SType) (others: SType list) (defs: (int * string * Param list * SType option * Expr) list) =
        let tr = resolveWith traitNames.Contains tr |> Option.defaultValue tr

        let methods =
            traitMethods.Values |> Seq.filter (fun m -> m.owner = tr) |> Seq.map (fun m -> m.name) |> Set.ofSeq

        if methods.IsEmpty then
            fail 0 (sprintf "unknown trait '%s'" tr)

        let arity = (traitMethods.Values |> Seq.find (fun m -> m.owner = tr)).nparams

        let hn, hargs =
            match head with
            | STName(n, args) ->
                let n =
                    match typeAliases.TryGetValue n with
                    | true, c -> c
                    | _ -> n

                // the type's full name, as annotations resolve it (Set in Collections: Collections.Set)
                (resolveWith (fun q -> prims.Contains q || builtinCons.ContainsKey q || types.ContainsKey q) n
                 |> Option.defaultValue n),
                args
            // a tuple of type variables: the impl for every tuple of that size (*2 for 'a * 'b)
            | STTuple ts -> tupleHead ts.Length, ts
            | _ -> fail 0 "an impl is for a named type or a tuple, such as Show<Point>, Show<list<'a>> or Binary<'a * 'b>"

        let hvars =
            hargs
            |> List.map (function
                | STVar v -> v
                | _ -> fail 0 "impl type arguments must be type variables: impl Show<list<'a>>")

        if (List.distinct hvars).Length <> hvars.Length then
            fail 0 "impl type variables must be distinct"

        if impls.ContainsKey((tr, hn)) then
            fail 0 (sprintf "%s<%s> is already implemented" tr hn)

        if others.Length <> arity - 1 then
            fail 0 (sprintf "%s takes %d type parameters, and this impl gives %d" (shortName tr) arity (others.Length + 1))

        // the other parameters are made of the head's variables: the head's type determines them
        let rec varsOf (st: SType) =
            match st with
            | STVar v -> [ v ]
            | STName(_, args)
            | STTuple args -> List.collect varsOf args
            | STFun(a, b) -> varsOf a @ varsOf b
            | _ -> []

        implOthers[(tr, hn)] <-
            others
            |> List.map (fun o ->
                match varsOf o |> List.tryFind (fun v -> not (List.contains v hvars)) with
                | Some v ->
                    let theirs = if hvars.IsEmpty then "it has none" else hvars |> List.map ((+) "'") |> String.concat ", "
                    fail 0 (sprintf "impl %s: '%s isn't a type variable of %s; the other parameters are made of the head's (%s), such as 'a * int or list<'a>" (shortName tr) v (shortName hn) theirs)
                | None -> toTy (Some hvars) o)

        let given = defs |> List.map (fun (_, n, _, _, _) -> n)

        for m in methods do
            if not (List.contains m given) then
                fail 0 (sprintf "impl %s<%s> is missing '%s'" tr hn m)

        for m in given do
            if not (methods.Contains m) then
                fail 0 (sprintf "trait %s has no method '%s'" tr m)

        // registered before the bodies, so they may use the impl recursively
        let table = Dictionary<string, string>()
        impls[(tr, hn)] <- table
        implRequires[(tr, hn)] <- List.map (fun _ -> Set.empty) hvars

        let items =
            defs
            |> List.map (fun (dl, m, ps, ret, body) ->
                let tm = traitMethods[tr + "." + m]
                let fname = sprintf "%s<%s>#%s" tr hn m
                table[m] <- fname
                let ps = if ps.IsEmpty then [ PUnit, None ] else ps

                let expected () =
                    let h = toTy None head
                    let t = substGen (h :: List.map (toTy None) others @ [ fresh kRow ]) tm.ty
                    if tm.isConst then tfun tUnit t else t

                dl, fname, true, ps, ret, body, Some expected)

        let results = defineGroupWith false items

        // what the impl needs from each type argument: the union over its methods
        implRequires[(tr, hn)] <-
            hvars
            |> List.map (fun v ->
                results
                |> List.collect (fun (g, tvs) ->
                    match tvs.TryGetValue v with
                    | true, t ->
                        match prune t with
                        | TGen i -> (List.item i g.kinds).traits |> Set.toList
                        | _ -> []
                    | _ -> [])
                |> Set.ofList)

    let shapeOf (tname: string) : Derive.ShapeInfo =
        match types[tname].def with
        | RecordDef fs ->
            let defaults =
                match recordDefaults.TryGetValue tname with
                | true, ds when ds.Length = fs.Length -> ds
                | _ -> List.map (fun _ -> None) fs

            Derive.RecordShape(List.zip (List.map fst fs) defaults)
        | UnionDef cs ->
            Derive.UnionShape(
                cs
                |> List.map (fun (c, fts) ->
                    c,
                    List.mapi
                        (fun j n -> defaultArg n (sprintf "item%d" (j + 1)))
                        (match ctorFieldNames.TryGetValue c with
                         | true, ns -> ns
                         | _ -> List.map (fun _ -> None) fts))
            )

    /// Implements trait `tr` for type `tname` by expanding `derive tr`.
    let deriveImpl (context: string) (tr: string) (tname: string) =
        if not (derives.ContainsKey tr) then
            fail 0 (sprintf "no derive named '%s'" tr)

        let head = STName(tname, List.init types[tname].npars (fun i -> STVar(sprintf "t%d" i)))
        // hygiene: a trait method named in a derive (show, compare, hash…) means the trait's,
        // as the derive's module sees it, even where the program defines a function of the
        // same name
        // ponytail: a local in a derive body named like a trait method would be rewritten too
        let methodOf (x: string) =
            if x.Contains "." then
                None
            else
                [ (match deriveModules[tr] with
                   | Some m -> m + "." + x
                   | None -> x)
                  x ]
                |> List.tryFind traitAliases.ContainsKey
                |> Option.map (fun a -> traitAliases[a])

        let rec hygienic (e: Expr) =
            match e with
            | Var x when (methodOf x).IsSome -> Var (methodOf x).Value
            | Call(x, args) when (methodOf x).IsSome -> Call((methodOf x).Value, List.map hygienic args)
            | _ -> mapExpr hygienic e

        let defs =
            Derive.expand tr tname head (shapeOf tname) derives[tr]
            |> List.map (fun (l, n, ps, r, body) -> l, n, ps, r, hygienic body)

        let saved = Dictionary<string, Ty>(tyvars) // may run in the middle of another function

        try
            try
                declareImpl tr head [] defs
            with
            | CompileError(l, msg) -> fail l (sprintf "%s: %s" context msg)
            | CompileErrorPos(l, c, msg) -> raise (CompileErrorPos(l, c, sprintf "%s: %s" context msg))
        finally
            tyvars.Clear()

            for kv in saved do
                tyvars[kv.Key] <- kv.Value

    // Eq, Ord, Hash and Show come from the prelude's derives, the first time they're needed
    autoDerive <-
        fun tr n ->
            let ok =
                List.contains tr [ "Eq"; "Ord"; "Hash"; "Show"; "Diff" ]
                && derives.ContainsKey tr
                && not (manualImpls.Contains((tr, n)) || optOut.Contains((tr, n)))
                && (match types.TryGetValue n with
                    | true, { def = RecordDef _ } -> true
                    | true, { def = UnionDef cs } -> not cs.IsEmpty
                    | _ -> false)

            if ok then
                st.autoDerived.Add((tr, n)) |> ignore
                deriveImpl (sprintf "automatic %s for %s" tr n) tr n

            ok

    /// A constant expression: literals, operators, conditionals, tuples, records, constructors
    /// and number conversions over constants. Its uses are the expression itself. Arrays, lists
    /// and calls make a top-level value computed once at startup instead.
    let rec isConstant (e: Expr) =
        let conversion (f: string) = nums.Contains f || List.contains f [ "float"; "c_int"; "double" ]

        match e with
        | Lit _
        | FloatLit _
        | StrLit _
        | CharLit _
        | BoolLit _
        | UnitLit -> true
        | At(_, a)
        | Neg a
        | Not a
        | Measured(a, _)
        | Typed(a, _) -> isConstant a
        | Var x ->
            // a case without fields, [] too (a static cell; a list of elements allocates, so it's a
            // value computed at startup)
            match resolveName x with
            | Some q -> consts.ContainsKey q || ctors.ContainsKey q
            | None -> false
        | Bin(_, a, b) -> isConstant a && isConstant b
        | If(c, t, Some f) -> isConstant c && isConstant t && isConstant f
        | Tuple xs -> List.forall isConstant xs
        | ArrayLit [] -> true // an empty array (HashMap.empty's buckets)
        | RecordLit fs -> fs |> List.forall (snd >> isConstant)
        | Call(f, args) ->
            let ctor =
                match resolveName f with
                | Some q -> ctors.ContainsKey q && q <> "::"
                | None -> false

            // a Buffer of constants: a constant's uses are its expression, so each use is a new
            // Buffer (Buffer.empty)
            let freshBuffer = resolveName f = Some "Collections.Buffer.ofArray"
            (ctor || conversion f || freshBuffer) && List.forall isConstant args
        | _ -> false

    /// The expression with every name resolved where it is written (for inlining elsewhere).
    let rec qualifyNames (e: Expr) =
        match e with
        | Var x ->
            match resolveName x with
            | Some q -> Var q
            | None -> e
        | Call(f, args) ->
            let f' =
                match resolveName f with
                | Some q -> q
                | None -> f

            Call(f', List.map qualifyNames args)
        | _ -> mapExpr qualifyNames e

    /// Declares with error recovery (set below): a nested module's declarations each get it.
    let declareRecovering: (int -> Decl -> unit) ref = ref (fun _ _ -> ())

    let rec declare (ln: int) (d: Decl) =
            match d with
            | TypeDecl(name, tps, body, ms) ->
                let name = qualify name

                if prims.Contains name || builtinCons.ContainsKey name || types.ContainsKey name then
                    fail 0 (sprintf "type '%s' is already defined" name)

                // registered first so the body can refer to the type itself
                types[name] <- { npars = tps.Length; def = UnionDef [] }
                let tt = toTy (Some tps)

                match body with
                | RecordTy fields ->
                    let fs = fields |> List.map (fun (f, st, _) -> f, tt st)

                    let rec contains t =
                        match t with
                        | TCon(n, args) -> n = name || List.exists contains args
                        | TTuple ts -> List.exists contains ts
                        | _ -> false

                    if fs |> List.exists (snd >> contains) then
                        fail 0 (sprintf "record '%s' cannot contain itself; use a union" name)

                    if (fs |> List.map fst |> List.distinct).Length <> fs.Length then
                        fail 0 "duplicate field name"

                    types[name] <- { npars = tps.Length; def = RecordDef fs }
                    records.Add name
                    recordDefaults[name] <- fields |> List.map (fun (_, _, d) -> d)
                | UnionTy cases ->
                    types[name] <-
                        { npars = tps.Length
                          def = UnionDef(cases |> List.map (fun (c, fs) -> qualify c, fs |> List.map (snd >> tt))) }

                    cases
                    |> List.iteri (fun i (c, fs) ->
                        let c = qualify c

                        if ctors.ContainsKey c then
                            fail 0 (sprintf "constructor '%s' is already defined" c)

                        ctors[c] <- (name, i)
                        ctorFieldNames[c] <- List.map fst fs)

                declareMembers name tps ms
            | Extern(name, args, variadic, ret) ->
                if externs.ContainsKey name || globals.ContainsKey name then
                    fail 0 (sprintf "'%s' is already defined" name)

                let cty (isParam: bool) st =
                    let t = toTy (Some []) st

                    match t with
                    | TCon("callback", [ f ]) when isParam -> checkCallback (sprintf "extern '%s'" name) f
                    | TCon("span", [ el ]) when isParam -> checkCType (sprintf "extern '%s'" name) el // a pointer and a length
                    | _ -> checkCArg (sprintf "extern '%s'" name) t

                    t

                externs[name] <-
                    { pars = List.map (cty true) args
                      ret = cty false ret
                      variadic = variadic }
            | Fun(name, isRec, ps, ret, body) when name.StartsWith "|" ->
                // active pattern: cases become constructors of a hidden union (total) or option (partial)
                let names = name.Trim('|').Split('|') |> List.ofArray
                let fn = qualify name
                let partial = List.last names = "_"

                if partial then
                    if names.Length <> 2 then
                        fail 0 "a partial active pattern has one case: (|Name|_|)"

                    activePatterns[qualify names.Head] <- (fn, false, ps.Length - 1)
                else
                    let u = qualify ("$AP" + name)
                    types[u] <- { npars = names.Length; def = UnionDef(names |> List.mapi (fun i c -> qualify c, [ TGen i ])) }

                    names
                    |> List.iteri (fun i c ->
                        let qc = qualify c

                        if ctors.ContainsKey qc then
                            fail 0 (sprintf "constructor '%s' is already defined" c)

                        ctors[qc] <- (u, i)
                        ctorFieldNames[qc] <- [ None ]
                        apCtors.Add qc |> ignore
                        activePatterns[qc] <- (fn, true, ps.Length - 1))

                defineGroup [ ln, fn, isRec, ps, ret, body ]
            | Fun(name, isRec, ps, ret, body) ->
                let name = qualify name

                if globals.ContainsKey name || externs.ContainsKey name then
                    fail 0 (sprintf "'%s' is already defined" name)

                try
                    defineGroup [ ln, name, isRec, ps, ret, body ]
                with _ ->
                    globals.Remove name |> ignore // keep later declarations from seeing a half-defined function
                    reraise ()

                recordKey d name globals[name].ty false name true

                // its effects in words (0025), with the parameters' names
                let names =
                    ps
                    |> List.map (fun (p, _) ->
                        match p with
                        | PIdent(x, None) when System.Char.IsLower x[0] -> x
                        | _ -> "the argument")

                if hovers.Count > 0 && hovers[hovers.Count - 1].name = name then
                    hovers[hovers.Count - 1] <- { hovers[hovers.Count - 1] with decl = true; explain = explain names globals[name].ty }

                // a generic function's hover shows what its type variables need
                let g = globals[name]

                let needs =
                    g.kinds
                    |> List.indexed
                    |> List.collect (fun (i, k) ->
                        k.traits
                        |> Set.toList
                        |> List.map (fun tr ->
                            match k.params.TryFind tr with
                            | Some ps -> sprintf "%s : %s<%s>" (show (TGen i)) tr (ps |> List.map show |> String.concat ", ")
                            | None -> sprintf "%s : %s" (show (TGen i)) tr))

                if not needs.IsEmpty && hovers.Count > 0 && hovers[hovers.Count - 1].name = name then
                    hovers[hovers.Count - 1] <- { hovers[hovers.Count - 1] with constraints = String.concat ", " needs }
            | Effect(name, tps, ops) ->
                // effect E<'a> = abstract op : T -> R: performed as E.op, given meaning by a handle
                let name = qualify name

                if effects.ContainsKey name then
                    fail 0 (sprintf "effect '%s' is already defined" name)

                let rec varsOf (st: SType) =
                    match st with
                    | STVar v -> [ v ]
                    | STName(_, args)
                    | STTuple args -> List.collect varsOf args
                    | STFun(a, b) -> varsOf a @ varsOf b
                    | STRow(t, ls, tail) -> varsOf t @ List.collect varsOf ls @ Option.toList tail
                    | STMeasure _ -> []

                let infos =
                    ops
                    |> List.map (fun (op, st) ->
                        // the operation's own type variables (throw's 'a) after the effect's
                        let own = varsOf st |> List.distinct |> List.filter (fun v -> not (List.contains v tps))
                        let t = toTy (Some(tps @ own)) st

                        let rec split (t: Ty) =
                            match t with
                            | TFun(a, r, _) ->
                                let ps, res = split r
                                a :: ps, res
                            | r -> [], r

                        let pars, ret = split t

                        if pars.IsEmpty then
                            fail 0 (sprintf "operation '%s' must be a function type: abstract %s : unit -> %s for one that takes nothing" op op (show t))

                        let rec mentionsOwn (t: Ty) =
                            match t with
                            | TGen i -> i >= tps.Length
                            | TCon(_, ts)
                            | TTuple ts -> List.exists mentionsOwn ts
                            | TFun(a, b, r) -> mentionsOwn a || mentionsOwn b || mentionsOwn r
                            | _ -> false

                        if List.exists mentionsOwn pars then
                            fail 0 (sprintf "operation '%s' has a type variable of its own in a parameter; an operation's own variables are for its result only (abstract throw : 'e -> 'a), the others are the effect's (effect %s<%s>)" op name (String.concat ", " (tps |> List.map (fun v -> "'" + v))))

                        ({ name = op; pars = pars; ret = ret; own = own.Length }: EffectOp))

                match infos |> List.countBy (fun o -> o.name) |> List.tryFind (fun (_, n) -> n > 1) with
                | Some(op, _) -> fail 0 (sprintf "effect '%s' declares '%s' twice" name op)
                | None -> ()

                effects[name] <- { npars = tps.Length; ops = infos }

                for i, o in List.indexed infos do
                    let q = name + "." + o.name
                    effectOps[q] <- (name, i)
                    // hover and definition: the operation as it's performed
                    let label = TCon(name, List.init tps.Length TGen)
                    recordKey (fst ops[i]) o.name (funTyRow o.pars o.ret (rowExt label rowEmpty)) false q true
            | Trait(name, tps, methods) ->
                let name = qualify name

                if not (traitNames.Add name) then
                    fail 0 (sprintf "trait '%s' is already defined" name)

                for m, st in methods do
                    let t = methodType tps st

                    let isConst =
                        match t with
                        | TFun _ -> false
                        | _ -> true

                    let qname = name + "." + m

                    traitMethods[qname] <-
                        { owner = name
                          name = m
                          ty = t
                          nparams = tps.Length
                          isConst = isConst }

                    traitAliases[qname] <- qname

                    // the method by its own name in the trait's module, except for the operator traits
                    // (whose methods are the operators)
                    if not (List.contains name [ "Add"; "Num"; "Eq" ]) && not (traitAliases.ContainsKey(qualify m)) then
                        traitAliases[qualify m] <- qname

                if name = "Show" then
                    traitAliases["string"] <- "Show.show"
            | Impl(tr, head, others, defs) -> declareImpl tr head others defs
            | Derive(name, defs) ->
                derives[qualify name] <- defs
                deriveModules[qualify name] <- currentModule.Value
            | DeriveGroup(name, members) ->
                let full =
                    members
                    |> List.map (fun m ->
                        match resolveWith (fun q -> derives.ContainsKey q || st.deriveGroups.ContainsKey q) m with
                        | Some q -> q
                        | None -> fail 0 (sprintf "no derive named '%s'" m))

                st.deriveGroups[qualify name] <- full
            | Private inner ->
                declare ln inner

                match inner with
                | Fun(n, _, _, _, _)
                | Value(n, _, _) -> privates[qualify n] <- currentModule.Value
                | TypeDecl(n, _, body, _) ->
                    privates[qualify n] <- currentModule.Value

                    match body with
                    | UnionTy cases ->
                        for c, _ in cases do
                            privates[qualify c] <- currentModule.Value
                    | RecordTy _ -> ()
                | _ -> fail 0 "'private' applies to 'let' and 'type' declarations"
            | Const(name, v) -> consts[name] <- v
            | FunGroup items ->
                // let rec f … and g …: checked together, so each may call the others
                let defs =
                    items
                    |> List.map (fun (l, d) ->
                        match d with
                        | Fun(n, _, ps, ret, body) -> l, n, ps, ret, body, d, false
                        | Private(Fun(n, _, ps, ret, body) as f) -> l, n, ps, ret, body, f, true
                        | _ -> fail l "'and' joins functions")

                for _, n, _, _, _, _, _ in defs do
                    let q = qualify n

                    if globals.ContainsKey q || externs.ContainsKey q || consts.ContainsKey q || globalValues.ContainsKey q then
                        fail 0 (sprintf "'%s' is already defined" n)

                try
                    defineRecGroup [ for l, n, ps, ret, body, _, _ in defs -> l, qualify n, true, ps, ret, body ]
                with _ ->
                    for _, n, _, _, _, _, _ in defs do
                        globals.Remove(qualify n) |> ignore

                    reraise ()

                for _, n, _, _, _, node, isPrivate in defs do
                    let q = qualify n
                    recordKey node n globals[q].ty false q true

                    if isPrivate then
                        privates[q] <- currentModule.Value
            | Value(name, ann, e) ->
                let q = qualify name

                if globals.ContainsKey q || externs.ContainsKey q || consts.ContainsKey q || globalValues.ContainsKey q then
                    fail 0 (sprintf "'%s' is already defined" name)

                let body =
                    match ann with
                    | Some t -> Typed(e, t)
                    | None -> e

                tyvars.Clear()

                if isConstant body then
                    // checked here, so errors point at the definition; then inlined at each use, with
                    // its names resolved here (a local at the use site can't capture them)
                    let body = qualifyNames body
                    let c = infer Map.empty 0 body
                    consts[q] <- body
                    recordKey d name c.ty false q true
                else
                    // computed once at startup, in module order; it has one type, so literals settle now
                    let c = withRowAs rowEmpty "a top-level value's initializer (it runs at startup, where no handler is)" (fun () -> infer Map.empty 0 body)

                    let rec generic (t: Ty) =
                        match prune t with
                        | TVar r -> (kindOf r).allowed.IsNone
                        | TCon(_, ts)
                        | TTuple ts -> List.exists generic ts
                        | TFun(a, b, _) -> generic a || generic b
                        | _ -> false

                    if generic c.ty then
                        fail 0 (sprintf "a top-level value of type %s must be a constant to be generic; make it a function, or give it a type" (show (schemed c.ty)))

                    resolve c.ty |> ignore
                    let init = "$init." + q

                    funs.Add
                        { name = init
                          pars = []
                          ret = c.ty
                          row = rowEmpty
                          body = c
                          ngen = 0
                          rows = 0
                          file = currentFile.Value
                          line = ln }

                    globalValues[q] <- c.ty
                    valueList.Add(q, init)
                    recordKey d name c.ty false q true
            | Open m ->
                // a module, or one nested in the current module or a module enclosing it
                match resolveWith moduleNames.Contains m with
                | Some full -> opens.Value <- full :: opens.Value
                | None -> fail 0 (sprintf "unknown module '%s'" m)
            | ModuleHeader _ -> ()
            | NestedModule(name, decls) ->
                // module Inner = …: its names are Outer.Inner.x; it sees the enclosing modules'
                // names, and an open inside it lasts to its end
                let full = qualify name

                // a program's module may share a name with a library namespace (Text); the
                // names in both are still distinct
                if not (nestedModules.Add full) then
                    fail 0 (sprintf "module '%s' is already defined" full)

                moduleNames.Add full |> ignore
                st.moduleNames.Add full |> ignore

                if currentModule.Value.IsNone then
                    mainNested.Add full |> ignore

                let outer, outerOpens = currentModule.Value, opens.Value
                currentModule.Value <- Some full

                try
                    for l, inner in decls do
                        declareRecovering.Value l inner
                finally
                    currentModule.Value <- outer
                    opens.Value <- outerOpens
            | Attrs(attrs, inner) when attrs |> List.exists (fst >> (=) "NoWarn") ->
                // [<NoWarn "unused-value">]: the declaration's warnings of those kinds aren't
                // reported (0021)
                let kinds = attrs |> List.filter (fst >> (=) "NoWarn") |> List.collect snd

                if kinds.IsEmpty then
                    fail 0 "[<NoWarn>] takes the warning's name: [<NoWarn \"unused-value\">]"

                for k in kinds do
                    if not (List.contains k warningKinds) then
                        fail 0 (sprintf "unknown warning '%s' (the kinds are %s)" k (String.concat ", " warningKinds))

                let rest = attrs |> List.filter (fst >> (<>) "NoWarn")
                let outer = silenced.Value
                silenced.Value <- Set.union outer (set kinds)

                try
                    declare ln (if rest.IsEmpty then inner else Attrs(rest, inner))
                finally
                    silenced.Value <- outer
            | Attrs([ "Measure", [] ], TypeDecl(name, [], UnionTy [], [])) -> measures.Add name |> ignore
            | Attrs([ "Export", cname ], (Fun(name, _, _, _, _) as f)) ->
                exporting.Value <- true

                try
                    declare ln f
                finally
                    exporting.Value <- false

                let q = qualify name
                let g = globals[q]

                if not g.kinds.IsEmpty then
                    fail 0 (sprintf "exported function '%s' must not be generic; add type annotations" name)

                // C calls it, and no handler is in C (the C-callback rule)
                match g.arity, prune g.ty with
                | n, t when n > 0 ->
                    let rec rowOfArrow k t =
                        match prune t with
                        | TFun(_, r, row) -> if k = 1 then row else rowOfArrow (k - 1) r
                        | _ -> rowEmpty

                    let row = rowOfArrow n t

                    if not (isRowEmpty row) then
                        fail 0 (sprintf "a function given to C must have no effects: '%s' performs %s (the C-callback rule)" name (effectsText row))
                | _ -> ()

                let cname =
                    match cname with
                    | [ c ] -> c
                    | _ -> name

                let ptys, ret = peel g.arity g.ty
                let what = sprintf "export '%s'" cname

                for t in ptys do
                    checkCArg what t

                checkCArg what ret

                exports.Add
                    { cname = cname
                      fname = q
                      pars = ptys |> List.filter (fun t -> prune t <> tUnit)
                      ret = resolve ret }
            | Attrs(attrs, (Fun(name, _, _, _, _) as f)) when
                attrs |> List.forall (fun (a, _) -> List.contains a [ "Wrapping"; "FastMath"; "Target"; "Multiversion" ])
                ->
                // [<Wrapping>]: integer + - * in the function, its lambdas included, wrap around
                // instead of panicking on overflow (hashes, checksums). [<FastMath>]: float + - * /
                // may be reassociated (so a reduction vectorizes) and assume no NaNs or infinities
                let has a = attrs |> List.exists (fst >> (=) a)
                wrapping.Value <- has "Wrapping"
                fastMath.Value <- has "FastMath"

                try
                    declare ln f
                finally
                    wrapping.Value <- false
                    fastMath.Value <- false

                // [<Target "avx2,fma">]: compiled for those CPU features; [<Multiversion("avx2",
                // "sse4.2")>]: a version for each, and one for the baseline, chosen at startup
                let features (args: string list) =
                    if args |> List.exists (fun f -> f = "" || f.Contains " ") then
                        fail 0 "CPU features are names such as \"avx2\", or several separated by commas: \"avx2,fma\""

                    args

                match has "Target", has "Multiversion" with
                | true, true -> fail 0 "a function is either [<Target>] or [<Multiversion>], not both"
                | true, _ ->
                    match attrs |> List.find (fst >> (=) "Target") |> snd |> features with
                    | [ fs ] -> st.targets[qualify name] <- [ "target"; fs ]
                    | _ -> fail 0 "[<Target>] takes the features as one string: [<Target \"avx2,fma\">]"
                | _, true ->
                    match attrs |> List.find (fst >> (=) "Multiversion") |> snd |> features with
                    | [] -> fail 0 "[<Multiversion>] takes a version's features each: [<Multiversion(\"avx2,fma\", \"sse4.2\")>]"
                    | versions -> st.targets[qualify name] <- "multiversion" :: versions
                | _ -> ()
            | Attrs([ "Test", [] ], Fun(name, _, _, _, _)) ->
                fail 0 (sprintf "tests are values now (0009): [<Tests>] let tests = testList \"%s\" [ test \"…\" (fun () -> assert (…)) ]" name)
            | Attrs([ "Tests", [] ], (Value(name, _, _) as v)) ->
                // a Test or a list of them, which the file's test entry ($tests) runs
                declare ln v
                let q = qualify name
                let t = globalValues[q]
                let test = TCon("Testing.Test", [])

                let isList =
                    try
                        unify test t
                        false
                    with Mismatch ->
                        try
                            unify (TCon("list", [ test ])) t
                            true
                        with Mismatch ->
                            fail 0 (sprintf "a [<Tests>] value is a Test (test, testList, …) or a list of them, not %s" (show t))

                testValues.Add((q, isList))
            | Attrs([ "Tests", [] ], _) -> fail 0 "[<Tests>] marks a top-level value: [<Tests>] let tests = testList \"…\" [ … ]"
            | Attrs([ "CLayout", [] ], (TypeDecl(name, tps, RecordTy fields, _) as d)) ->
                declare ln d
                let q = qualify name

                if not tps.IsEmpty then
                    fail 0 "a [<CLayout>] record can't be generic"

                clayouts.Add q |> ignore

                for f, ft in (match types[q].def with
                              | RecordDef fs -> fs
                              | UnionDef _ -> []) do
                    match prune ft with
                    | TCon("unit", []) -> fail 0 (sprintf "[<CLayout>] field '%s' can't be unit" f)
                    | _ -> checkCType (sprintf "[<CLayout>] field '%s'" f) ft
            | Attrs(attrs, inner) ->
                declare ln inner

                match inner with
                | TypeDecl(name, _, _, _) ->
                    let name = qualify name

                    for a, args in attrs do
                        match a with
                        | "Derive" ->
                            // a group's members, in order (a group may name a group)
                            let rec expand (tr: string) =
                                let tr = resolveWith (fun q -> derives.ContainsKey q || st.deriveGroups.ContainsKey q) tr |> Option.defaultValue tr

                                match st.deriveGroups.TryGetValue tr with
                                | true, members -> List.collect expand members
                                | _ -> [ tr ]

                            for tr in List.collect expand args do
                                deriveImpl (sprintf "Derive(%s) on %s" tr name) tr name
                        | "NoEquality" ->
                            optOut.Add(("Eq", name)) |> ignore
                            optOut.Add(("Hash", name)) |> ignore
                        | "NoComparison" -> optOut.Add(("Ord", name)) |> ignore
                        | _ -> fail 0 (sprintf "unknown attribute '%s'" a)
                | _ -> fail 0 "attributes are only supported on type declarations yet"
            | TypeAlias(name, tps, target) ->
                let q = qualify name

                if types.ContainsKey q || aliases.ContainsKey q then
                    fail 0 (sprintf "type '%s' is already defined" name)

                aliases[q] <- (tps.Length, toTy (Some tps) target)
            | TypeExt(name, tps, ms) ->
                let name =
                    match typeAliases.TryGetValue name with
                    | true, c -> c
                    | _ -> name

                let name =
                    resolveWith (fun q -> prims.Contains q || builtinCons.ContainsKey q || types.ContainsKey q) name
                    |> Option.defaultValue name

                if not (prims.Contains name || builtinCons.ContainsKey name || types.ContainsKey name) then
                    fail 0 (sprintf "unknown type '%s'" name)

                declareMembers name tps ms

    let checkMain () =
        match globals.TryGetValue "main" with
        | true, g ->
            match g.arity, prune g.ty with
            | 1, TFun(p, r, row) when prune p = tUnit ->
                match resolve r with
                | TCon(("int" | "i32" | "unit"), []) -> ()
                | t -> fail 0 (sprintf "'main' must return int, c_int or unit, not %s" (show t))

                // nothing handles what main performs
                match fst (rowParts row) with
                | [] -> ()
                | ls ->
                    let consume = if ls |> List.exists (fun l -> labelName l = "Yield") then ", or consume the Seq" else ""
                    fail 0 (sprintf "main performs %s and nothing handles it: wrap the call in handle … with%s" (ls |> List.map show |> String.concat ", ") consume)
            | _ -> fail 0 "'main' must take one unit parameter: let main () = ..."
        | _ -> fail 0 "no 'main' function"

    // errors that mention a declaration that already failed are just its consequences
    let failed = HashSet<string>()

    let report (dg: Diagnostic) =
        if not collect then
            raise (CompileErrorAt(dg.file, dg.line, dg.col, dg.msg))
        elif not (failed |> Seq.exists (fun n -> dg.msg.Contains("'" + n + "'"))) then
            diagnostics.Add dg

    let declaredNames (d: Decl) =
        let rec go d =
            match d with
            | Value(n, _, _)
            | Fun(n, _, _, _, _)
            | TypeDecl(n, _, _, _)
            | TypeAlias(n, _, _) -> [ n ]
            | FunGroup items -> items |> List.collect (snd >> go)
            | Attrs(_, d)
            | Private d -> go d
            | _ -> []

        go d

    let declareOne (ln: int) (d: Decl) =
        let diag l c msg = errorAt currentFile.Value l c msg

        try
            declare ln d
            closeDynCalls ()
            warnDiscarded ()
        with
        | CompileError(l, msg) ->
            discarded.Clear()
            report (diag (if l = 0 then ln else l) 0 msg)

            for n in declaredNames d do
                failed.Add n |> ignore
                failed.Add(qualify n) |> ignore
        | CompileErrorPos(l, c, msg) ->
            discarded.Clear()
            report (diag l c msg)

            for n in declaredNames d do
                failed.Add n |> ignore
                failed.Add(qualify n) |> ignore

    declareRecovering.Value <- declareOne
    let mutable marks = { records = 0; funs = 0; exports = 0; tests = 0; valueList = 0; hovers = 0 }

    let check (file: string) (modName: string option) (decls: (int * Decl) list) =
        // what this module writes from here on is its result; its names and type variables are
        // numbered from 0, so they don't depend on the modules before it
        markState st

        marks <-
            { records = records.Count
              funs = funs.Count
              exports = exports.Count
              tests = tests.Count
              valueList = valueList.Count
              hovers = hovers.Count }

        counter.Value <- 0
        Core.resetTypeVars ()
        localValues.Clear()
        currentModule.Value <- modName
        opens.Value <- []
        currentFile.Value <- file
        let errors () = diagnostics |> Seq.filter isError |> Seq.length
        let errorsBefore = errors ()

        for n in modName |> Option.map withEnclosing |> Option.defaultValue [] do
            st.moduleNames.Add n |> ignore

        testValues.Clear()

        for ln, d in decls do
            declareOne ln d

        // the program's [<Tests>] values, run by the test binary's entry (0009)
        if modName.IsNone && testValues.Count > 0 then
            let all = [ for q, isList in testValues -> if isList then Var q else Call("::", [ Tuple [ Var q; Var "[]" ] ]) ]
            let joined = Call("Collections.List.concat", [ List.foldBack (fun a acc -> Call("::", [ Tuple [ a; acc ] ])) all (Var "[]") ])
            declareOne 0 (Fun("$tests", false, [ PUnit, None ], None, Call("Testing.Runner.main", [ joined ])))
            tests.Add "$tests"

        currentModule.Value <- None
        errors () = errorsBefore

    let finish () =
        try
            if (requireMain && tests.Count = 0) || globals.ContainsKey "main" then // a test file needs no main
                checkMain ()
        with CompileError(_, msg) ->
            // at main when it was checked here; else no place yet (the driver gives main's, when
            // the main module came from the cache)
            let at = funs |> Seq.tryFind (fun f -> f.name = "main")

            report (
                errorAt
                    (at |> Option.map (fun f -> f.file) |> Option.defaultValue "")
                    (at |> Option.map (fun f -> f.line) |> Option.defaultValue 0)
                    0
                    msg
            )

        { types = types.Dict
          externs = externs.Dict
          funs = List.ofSeq funs
          traitMethods = traitMethods.Dict
          effects = st.effects.Dict
          impls = impls.Dict
          exports = List.ofSeq exports
          values = List.ofSeq valueList
          tests = List.ofSeq tests
          clayouts = clayouts.Set
          targets = st.targets.Dict
          diagnostics = List.ofSeq diagnostics
          hovers = List.ofSeq hovers
          memberNames =
            let d = Dictionary<string, string list>()

            for KeyValue(t, table) in members do
                d[t] <- List.map fst table

            d }

    let addProgram (names: string list) (impls: (string * string) list) =
        for m in names do
            for n in withEnclosing m do
                moduleNames.Add n |> ignore

        for i in impls do
            manualImpls.Add i |> ignore

    { state = st
      check = check
      marks = fun () -> marks
      diagnostics = diagnostics
      hovers = hovers
      addProgram = addProgram
      finish = finish }
