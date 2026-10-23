/// Core, the typed intermediate language every pass after checking works on (the F# compiler's
/// Core IR): expressions with their types, local names unique per function, and patterns.
open Types.Ty

/// A pattern of a match in Core.
type CPat =
  | CPWild
  | CPVar of string * Ty
  | CPInt of i64
  | CPStr of string
  | CPBool of bool
  | CPTuple of list<CPat>
  /// every field of the record, in declaration order
  | CPRecord of string * list<string * CPat>
  /// a union's case: the union, the case's tag, its fields' patterns
  | CPCtor of string * int * list<CPat>
  | CPOr of CPat * CPat
  | CPAs of CPat * string * Ty

/// An expression and its type, and its number in the tree when a pass has numbered it (number):
/// 0 for a node made since (mk), which a pass keying tables by node tells apart that way.
type CExpr = { k: CKind; ty: Ty; id: int }

and CKind =
  | CInt of i64
  | CFloat of f64
  | CBool of bool
  | CStr of string
  | CUnit
  /// a local: its name is unique in its function
  | CLocal of string
  /// a top-level value computed at startup (not a constant)
  | CGlobalVal of string
  /// a top-level function, at an instantiation (None: the enclosing one's)
  | CGlobal of string * option<list<Ty>>
  | CApp of CExpr * list<CExpr>
  | CLam of list<string * Ty> * CExpr
  | CLetFun of string * bool * list<string * Ty> * CExpr * CExpr
  /// local functions that call each other, then the rest
  | CLetRec of list<string * list<string * Ty> * CExpr> * CExpr
  | CExtern of string * list<CExpr>
  | CPrim of string * list<CExpr>
  | CBin of string * CExpr * CExpr
  | CNeg of CExpr
  | CNot of CExpr
  | CIf of CExpr * CExpr * CExpr
  | CLet of string * CExpr * CExpr
  | CSeq of CExpr * CExpr
  /// tuples and records (fields in declaration order)
  | CTuple of list<CExpr>
  | CField of CExpr * int
  /// a union's case: the union, the tag, the fields
  | CCtor of string * int * list<CExpr>
  | CMatch of CExpr * list<CPat * option<CExpr> * CExpr>
  | CLetMut of string * CExpr * CExpr
  | CAssign of string * CExpr
  /// a.[i] <- v on a `let mutable` array: in place when the array is unique, else copied first
  | CArraySet of string * CExpr * CExpr
  | CWhile of CExpr * CExpr
  /// a range loop: the variable, from, step, to, the body
  | CFor of string * CExpr * CExpr * CExpr * CExpr
  | CLine of int * CExpr
  /// an effect's operation (its label, Yield<int>; its index), performed with the arguments:
  /// what the innermost handler of the effect gives (DESIGN §6.1); until Evidence
  | CPerform of Ty * int * list<CExpr>
  /// handle body with clauses: for each operation (its index), its parameters, the resumption's
  /// name and type, and the clause's body; then the return clause, its variable bound to the
  /// body's result; until Evidence
  | CHandle of Ty * CExpr * list<int * list<string * Ty> * (string * Ty) * CExpr> * (string * Ty) * CExpr
  // after closure conversion
  | CCallDirect of string * list<CExpr>
  /// a function, and the values of its first parameters
  | CMkClosure of string * list<CExpr>
  /// a closure applied to arguments
  | CApplyClo of CExpr * list<CExpr>
  // after reference counting
  | CDup of string * Ty * CExpr
  | CDrop of string * Ty * CExpr
  /// the drop of a matched cell (its variable, type, tag, kept fields, reuse token, body): unique,
  /// its kept fields move out, the rest are dropped, and the cell is freed or becomes the token;
  /// shared, the kept fields are dup'ed and the count decremented, and the token is null
  | CDropFields of string * Ty * int * Set<int> * option<string> * CExpr
  /// a constructor built in the token's cell when it isn't null
  | CCtorAt of string * string * int * list<CExpr>
  | CFreeToken of string * CExpr
  // after match lowering
  /// a join point (from a decision tree): `rest`, whose paths may end in a jump to it, then the
  /// body with the parameters bound to the jump's arguments: a block with phis, not a function
  | CJoin of string * list<string * Ty> * CExpr * CExpr
  /// a jump to a join point, in a tail position of its rest
  | CJump of string * list<CExpr>

let mk (k: CKind) (ty: Ty) : CExpr = { k = k; ty = ty; id = 0 }

/// A node rebuilt with f applied to each of its direct child expressions, in evaluation order.
let mapChildren (f: CExpr -> CExpr) (k: CKind) : CKind =
  match k with
  | CInt _
  | CFloat _
  | CBool _
  | CStr _
  | CUnit
  | CLocal _
  | CGlobalVal _
  | CGlobal _ -> k
  | CApp(h, args) ->
    let h = f h
    CApp(h, List.map f args)
  | CLam(ps, b) -> CLam(ps, f b)
  | CLetFun(n, r, ps, b, rest) ->
    let b = f b
    CLetFun(n, r, ps, b, f rest)
  | CLetRec(fs, rest) ->
    let fs = List.map (fun (n, ps, b) -> (n, ps, f b)) fs
    CLetRec(fs, f rest)
  | CExtern(n, args) -> CExtern(n, List.map f args)
  | CPrim(n, args) -> CPrim(n, List.map f args)
  | CBin(op, a, b) ->
    let a = f a
    CBin(op, a, f b)
  | CNeg a -> CNeg(f a)
  | CNot a -> CNot(f a)
  | CIf(c, t, e) ->
    let c = f c
    let t = f t
    CIf(c, t, f e)
  | CLet(x, v, b) ->
    let v = f v
    CLet(x, v, f b)
  | CSeq(a, b) ->
    let a = f a
    CSeq(a, f b)
  | CTuple xs -> CTuple(List.map f xs)
  | CField(r, i) -> CField(f r, i)
  | CCtor(u, t, args) -> CCtor(u, t, List.map f args)
  | CMatch(s, cases) ->
    let s = f s
    CMatch(s, List.map (fun (p, g, b) -> (p, Option.map f g, f b)) cases)
  | CLetMut(x, v, b) ->
    let v = f v
    CLetMut(x, v, f b)
  | CAssign(x, v) -> CAssign(x, f v)
  | CArraySet(x, i, v) ->
    let i = f i
    CArraySet(x, i, f v)
  | CWhile(c, b) ->
    let c = f c
    CWhile(c, f b)
  | CFor(x, a, s, b, body) ->
    let a = f a
    let s = f s
    let b = f b
    CFor(x, a, s, b, f body)
  | CLine(l, e) -> CLine(l, f e)
  | CPerform(l, op, args) -> CPerform(l, op, List.map f args)
  | CHandle(l, b, cls, r, rb) ->
    // the body runs first
    let b = f b
    let cls = List.map (fun (op, ps, k, c) -> (op, ps, k, f c)) cls
    CHandle(l, b, cls, r, f rb)
  | CCallDirect(n, args) -> CCallDirect(n, List.map f args)
  | CMkClosure(n, args) -> CMkClosure(n, List.map f args)
  | CApplyClo(c, args) ->
    let c = f c
    CApplyClo(c, List.map f args)
  | CDup(x, t, e) -> CDup(x, t, f e)
  | CDrop(x, t, e) -> CDrop(x, t, f e)
  | CDropFields(x, t, tag, keep, tok, e) -> CDropFields(x, t, tag, keep, tok, f e)
  | CCtorAt(tok, u, tag, args) -> CCtorAt(tok, u, tag, List.map f args)
  | CFreeToken(tok, e) -> CFreeToken(tok, f e)
  | CJoin(j, ps, b, r) ->
    // the rest runs first
    let r = f r
    CJoin(j, ps, f b, r)
  | CJump(j, args) -> CJump(j, List.map f args)

/// A node's direct child expressions, in evaluation order.
let children (k: CKind) : list<CExpr> =
  let acc = Buffer.empty
  let push (e: CExpr) =
    Buffer.push e acc
    e
  mapChildren push k |> ignore
  Array.toList (Buffer.toArray acc)

/// The variables a pattern binds.
let rec patVars (p: CPat) : list<string * Ty> =
  match p with
  | CPWild
  | CPInt _
  | CPStr _
  | CPBool _ -> []
  | CPVar(x, t) -> [ (x, t) ]
  | CPAs(q, x, t) -> (x, t) :: patVars q
  | CPTuple ps
  | CPCtor(_, _, ps) -> List.concat (List.map patVars ps)
  | CPRecord(_, fs) -> List.concat (List.map (fun (_, q) -> patVars q) fs)
  | CPOr(a, _) -> patVars a

/// The names a node binds itself (not those bound inside its children).
let ownBinders (k: CKind) : list<string> =
  match k with
  | CLam(ps, _) -> List.map fst ps
  | CLetFun(n, _, ps, _, _) -> n :: List.map fst ps
  | CLetRec(fs, _) -> List.concat (List.map (fun (n, ps, _) -> n :: List.map fst ps) fs)
  | CJoin(_, ps, _, _) -> List.map fst ps
  | CLet(x, _, _)
  | CLetMut(x, _, _)
  | CFor(x, _, _, _, _) -> [ x ]
  | CMatch(_, cases) -> List.concat (List.map (fun (p, _, _) -> List.map fst (patVars p)) cases)
  | CHandle(_, _, cls, (r, _), _) -> r :: List.concat (List.map (fun (_, ps, (k, _), _) -> k :: List.map fst ps) cls)
  | _ -> []

/// The names bound inside an expression.
let rec binders (e: CExpr) : list<string> = List.append (ownBinders e.k) (List.concat (List.map binders (children e.k)))

// the variables a node references itself (not through its children)
let private ownRefs (e: CExpr) : list<string * Ty> =
  match e.k with
  | CLocal x -> [ (x, e.ty) ]
  | CAssign(x, v) -> [ (x, v.ty) ]
  | CArraySet(x, _, v) -> [ (x, TCon("array", [ v.ty ])) ]
  | CDup(x, t, _)
  | CDrop(x, t, _)
  | CDropFields(x, t, _, _, _, _) -> [ (x, t) ]
  | _ -> []

/// The variables an expression references.
let rec refs (e: CExpr) : list<string * Ty> = List.append (ownRefs e) (List.concat (List.map refs (children e.k)))

/// The variables free in an expression (names are unique: referenced and not bound inside).
let freeVars (e: CExpr) : Set<string> =
  Set.difference (Set.ofList (List.map fst (refs e))) (Set.ofList (binders e))

/// The tree with every node numbered from 1 (the order doesn't matter), for a pass that keys
/// tables by node.
let number (e: CExpr) : CExpr =
  let count = ref 0
  let rec go (x: CExpr) : CExpr =
    count.Value <- count.Value + 1
    let n = count.Value
    { x with k = mapChildren go x.k; id = n }
  go e

/// freeVars, remembered for the numbered nodes (bottom-up: a node's set from its children's and
/// its own references, less what it binds), for a pass that asks about the same nodes again and
/// again; a node made since is computed from its children.
let cachedFreeVars () : CExpr -> Set<string> =
  let cache = ref Map.empty
  let rec fv (e: CExpr) : Set<string> =
    match (if e.id > 0 then Map.tryFind e.id cache.Value else None) with
    | Some s -> s
    | None ->
      let below = List.fold (fun (acc: Set<string>) c -> Set.union acc (fv c)) Set.empty (children e.k)
      let s = Set.difference (Set.union below (Set.ofList (List.map fst (ownRefs e)))) (Set.ofList (ownBinders e.k))
      if e.id > 0 then
        cache.Value <- Map.add e.id s cache.Value
      s
  fv

/// A top-level function in Core.
type FunDef =
  { name: string
    pars: list<string * Ty>
    ret: Ty
    /// what the body performs: the row of the last parameter's arrow (the others have none)
    row: Ty
    body: CExpr
    /// how many quantified variables it has (TGen 0 … ngen - 1)
    ngen: int
    /// how many of them are effect rows: the last ones (instantiated with empty rows, the function
    /// is its pure instance, under its own name, so its module owns it)
    rows: int
    /// where it's defined (debug info): the file, and its first token's line
    file: string
    line: int }

/// A C function's signature.
type ExternSig = { pars: list<Ty>; ret: Ty; variadic: bool }

/// An effect's operation: its parameter types and result, over the effect's type parameters (TGen
/// 0 … n - 1) and its own (TGen n …, which appear in the result only: throw : 'e -> 'a).
type EffectOp = { name: string; pars: list<Ty>; ret: Ty; own: int }

/// An effect (DESIGN §6.1): its number of type parameters and its operations, in order.
type EffectInfo = { npars: int; ops: list<EffectOp> }

/// A trait's method: TGen 0 is the trait's first type parameter, the others follow (0017), and
/// TGen nparams is the method's ambient row (0025); `abstract zero : 'a` is a constant,
/// implemented as unit -> 'a.
type TraitMethod = { owner: string; name: string; ty: Ty; nparams: int; isConst: bool }

/// [<Export "cname">]: a C entry point for a monomorphic function (unit parameters left out).
type Export = { cname: string; fname: string; pars: list<Ty>; ret: Ty }

/// A pattern with f applied to its variables' types.
let rec mapPatTypes (f: Ty -> Ty / 'e) (p: CPat) : CPat / 'e =
  match p with
  | CPVar(x, t) -> CPVar(x, f t)
  | CPAs(q, x, t) -> CPAs(mapPatTypes f q, x, f t)
  | CPTuple ps -> CPTuple(List.map (mapPatTypes f) ps)
  | CPRecord(r, fs) -> CPRecord(r, List.map (fun (n, q) -> (n, mapPatTypes f q)) fs)
  | CPCtor(u, tag, ps) -> CPCtor(u, tag, List.map (mapPatTypes f) ps)
  | CPOr(a, b) -> CPOr(mapPatTypes f a, mapPatTypes f b)
  | q -> q

/// An expression with f applied to every type in it: its nodes', its binders', its patterns', an
/// instantiation's, an effect's label.
let rec mapTypes (f: Ty -> Ty / 'e) (e: CExpr) : CExpr / 'e =
  let pars (ps: list<string * Ty>) = List.map (fun (x, t) -> (x, f t)) ps
  let go = mapTypes f
  let k =
    match e.k with
    | CGlobal(g, Some inst) -> CGlobal(g, Some(List.map f inst))
    | CLam(ps, b) -> CLam(pars ps, go b)
    | CLetFun(n, r, ps, b, rest) -> CLetFun(n, r, pars ps, go b, go rest)
    | CLetRec(fs, rest) -> CLetRec(List.map (fun (n, ps, b) -> (n, pars ps, go b)) fs, go rest)
    | CMatch(s, cases) -> CMatch(go s, List.map (fun (p, g, b) -> (mapPatTypes f p, Option.map go g, go b)) cases)
    | CPerform(l, op, args) -> CPerform(f l, op, List.map go args)
    | CHandle(l, b, cls, (r, rt), rb) ->
      let clause (c: int * list<string * Ty> * (string * Ty) * CExpr) =
        match c with
        | (op, ps, (kn, kt), body) -> (op, pars ps, (kn, f kt), go body)
      CHandle(f l, go b, List.map clause cls, (r, f rt), go rb)
    | CDup(x, t, b) -> CDup(x, f t, go b)
    | CDrop(x, t, b) -> CDrop(x, f t, go b)
    | CDropFields(x, t, tag, keep, tok, b) -> CDropFields(x, f t, tag, keep, tok, go b)
    | CJoin(j, ps, b, r) -> CJoin(j, pars ps, go b, go r)
    | other -> mapChildren go other
  { k = k; ty = f e.ty; id = 0 }

/// The type of each local an expression refers to (a local function's at its uses: the definition
/// has its parameters' types only), by unique name.
let localTypesIn (e: CExpr) : Map<string, Ty> =
  let found = ref Map.empty
  let rec walk (x: CExpr) =
    match x.k with
    | CLocal n -> found.Value <- Map.add n x.ty found.Value
    | _ -> ()
    for c in children x.k do
      walk c
  walk e
  found.Value

/// The function a monomorphized name comes from: f for f<int>, and for f$lam2 (a lambda in f).
let baseFunName (n: string) : string =
  let noLambda =
    match String.indexOf "$" n with
    | Some i -> String.sub n 0 i
    | None -> n
  match String.indexOf "<" noLambda with
  | Some i when i > 0 -> String.sub noLambda 0 i
  | _ -> noLambda

/// Core as indented text, for reading what a pass did (ZS_DUMP_CORE); showTy shows an effect's
/// label.
let rec showCore (showTy: Ty -> string) (ind: int) (e: CExpr) : string =
  let pad = String.repeat ind "  "
  let sub (x: CExpr) = showCore showTy (ind + 1) x
  let line (s: string) = pad + s
  let rec pat (p: CPat) : string =
    match p with
    | CPWild -> "_"
    | CPVar(x, _) -> x
    | CPInt n -> $"{n}"
    | CPStr s -> "\"" + s + "\""
    | CPBool b -> if b then "True" else "False"
    | CPTuple ps -> "(" + String.join ", " (List.map pat ps) + ")"
    | CPRecord(_, fs) -> "{ " + String.join "; " (List.map (fun (n, q) -> n + " = " + pat q) fs) + " }"
    | CPCtor(_, tag, ps) -> $"#{tag}(" + String.join ", " (List.map pat ps) + ")"
    | CPOr(a, b) -> pat a + " | " + pat b
    | CPAs(q, x, _) -> pat q + " as " + x
  let flat (x: CExpr) = String.replace (showCore showTy 0 x) "\n" " "
  let args (xs: list<CExpr>) = String.join ", " (List.map flat xs)
  match e.k with
  | CInt n -> line $"{n}"
  // as .NET shows a float: an exponent with E
  | CFloat f -> line (String.replace $"{f}" "e" "E")
  | CBool b -> line (if b then "True" else "False")
  | CStr s -> line ("\"" + s + "\"")
  | CUnit -> line "()"
  | CLocal x -> line x
  | CGlobalVal x
  | CGlobal(x, _) -> line ("@" + x)
  | CLet(x, v, b) -> line ("let " + x + " = " + flat v) + "\n" + showCore showTy ind b
  | CLetMut(x, v, b) -> line ("let mutable " + x + " = " + flat v) + "\n" + showCore showTy ind b
  | CIf(c, t, f) -> line ("if " + flat c) + "\n" + sub t + "\n" + line "else" + "\n" + sub f
  | CMatch(s, cases) ->
    let guardText (g: option<CExpr>) =
      match g with
      | Some x -> " when " + flat x
      | None -> ""
    let clause (c: CPat * option<CExpr> * CExpr) =
      match c with
      | (p, g, b) -> "\n" + line ("| " + pat p + guardText g + " ->") + "\n" + sub b
    line ("match " + flat s) + String.concat (List.map clause cases)
  | CDup(x, _, b) -> line ("dup " + x) + "\n" + showCore showTy ind b
  | CDrop(x, _, b) -> line ("drop " + x) + "\n" + showCore showTy ind b
  | CDropFields(x, _, tag, keep, tok, b) ->
    let kept = "[" + String.join "; " (List.map (fun (i: int) -> $"{i}") (Set.toList keep)) + "]"
    let token =
      match tok with
      | Some t -> " token " + t
      | None -> ""
    line $"dropfields {x} #{tag} keep {kept}{token}" + "\n" + showCore showTy ind b
  | CFreeToken(t, b) -> line ("free " + t) + "\n" + showCore showTy ind b
  | CCtorAt(t, _, tag, xs) -> line ($"#{tag}@{t}(" + args xs + ")")
  | CCtor(_, tag, xs) -> line ($"#{tag}(" + args xs + ")")
  | CJoin(j, ps, b, r) -> showCore showTy ind r + "\n" + line ("join " + j + "(" + String.join ", " (List.map fst ps) + ") =") + "\n" + sub b
  | CJump(j, xs) -> line ("jump " + j + "(" + args xs + ")")
  | CCallDirect(f, xs) -> line (f + "(" + args xs + ")")
  | CPrim(op, xs) -> line (op + "(" + args xs + ")")
  | CBin(op, a, b) -> line (flat a + " " + op + " " + flat b)
  | CTuple xs -> line ("(" + args xs + ")")
  | CField(r, i) -> line (flat r + $".{i}")
  | CLine(_, x) -> showCore showTy ind x
  | CSeq(a, b) -> showCore showTy ind a + "\n" + showCore showTy ind b
  | CAssign(x, v) -> line (x + " <- " + flat v)
  | CWhile(c, b) -> line ("while " + flat c) + "\n" + sub b
  | CFor(x, a, _, b, body) -> line ("for " + x + " in " + flat a + " .. " + flat b) + "\n" + sub body
  | CMkClosure(f, xs) -> line ("closure " + f + "(" + args xs + ")")
  | CApplyClo(c, xs) -> line (flat c + " $ (" + args xs + ")")
  | CExtern(f, xs) -> line ("extern " + f + "(" + args xs + ")")
  | CNot a -> line ("not " + flat a)
  | CNeg a -> line ("-" + flat a)
  | CPerform(l, op, xs) -> line ($"perform {showTy l}#{op}(" + args xs + ")")
  | CHandle(l, b, cls, (r, _), rb) ->
    let clause (c: int * list<string * Ty> * (string * Ty) * CExpr) =
      match c with
      | (op, ps, (k, _), body) -> "\n" + line ($"| #{op}(" + String.join ", " (List.map fst ps) + $"), {k} ->") + "\n" + sub body
    line ("handle " + showTy l) + "\n" + sub b + String.concat (List.map clause cls) + "\n" + line ("| return " + r + " ->") + "\n" + sub rb
  | CApp(h, xs) -> line (flat h + " (" + args xs + ")")
  | CLam(ps, b) -> line ("fun (" + String.join ", " (List.map fst ps) + ") ->") + "\n" + sub b
  | CLetFun(n, _, ps, b, rest) -> line ("let " + n + "(" + String.join ", " (List.map fst ps) + ") =") + "\n" + sub b + "\n" + showCore showTy ind rest
  | CLetRec(fs, rest) ->
    let one (f: string * list<string * Ty> * CExpr) =
      match f with
      | (n, ps, b) -> line ("let rec " + n + "(" + String.join ", " (List.map fst ps) + ") =") + "\n" + sub b
    String.join "\n" (List.map one fs) + "\n" + showCore showTy ind rest
  | CArraySet(x, i, w) -> line (x + ".[" + flat i + "] <- " + flat w)
