/// Types and the typed Core IR shared by every pass after parsing.
module Core

open System.Collections.Generic

// ---------------------------------------------------------------- types

/// What a type variable may become: one of `allowed` (literals; None = anything) that
/// implements every trait in `traits`.
type Kind =
    { allowed: Set<string> option
      traits: Set<string> }

type Ty =
    | TCon of string * Ty list // int, f64, string, list<_>, user types; args can later carry units of measure
    | TFun of Ty * Ty
    | TTuple of Ty list
    | TVar of TV ref
    | TGen of int // quantified variable of a type scheme or type definition
    /// A unit of measure: base units and measure variables (TVar/TGen), with exponents.
    /// Appears only as the argument of a numeric type: f64<m/s> = TCon("f64", [TMeas ...]).
    | TMeas of (string * int) list * (Ty * int) list

and TV =
    | Unbound of int * Kind
    | Link of Ty

// int and usize are the machine word (64 bits, or 32 on a 32-bit chip); i64 and u64 always 64
let ints = set [ "int"; "i8"; "i16"; "i32"; "i64"; "u8"; "u16"; "u32"; "u64"; "usize" ]
let unsigned = set [ "u8"; "u16"; "u32"; "u64"; "usize" ]
let floats = set [ "f64"; "f32" ]
let nums = ints + floats
let prims = nums + set [ "bool"; "char"; "string"; "cstr"; "cptr"; "unit" ] // cptr: any other C pointer, opaque
let kAny = { allowed = None; traits = Set.empty }
let private allow s = { allowed = Some s; traits = Set.empty }
let kInt, kFloat, kNumeric = allow ints, allow floats, allow nums
let kConvertible = allow (nums.Add "char") // what the conversion functions (int, u8, …) take
let kIntOrChar = allow (ints.Add "char") // what `char` converts from
let kStrLit = allow (set [ "string"; "cstr" ])
let kTrait (t: string) = { allowed = None; traits = set [ t ] }

/// Built-in impls of the prelude's operator traits for primitive types.
let builtinImpls =
    dict
        [ "Add", nums.Add "string"
          "Num", nums
          "Eq", nums + set [ "string"; "bool"; "char"; "unit" ]
          "Ord", nums + set [ "string"; "char" ]
          "Show", nums + set [ "string"; "bool"; "char" ]
          "Hash", nums + set [ "string"; "bool"; "char" ] ]

let hasBuiltinImpl (tr: string) (n: string) =
    match builtinImpls.TryGetValue tr with
    | true, s -> s.Contains n
    | _ -> false

/// Built-in generic type constructors and their arity.
// array<T>: a copy-on-write value; Buffer<T>: the same storage as a shared mutable reference;
// callback<F>: FFI only
let builtinCons = dict [ "array", 1; "Buffer", 1; "ref", 1; "callback", 1 ]

let typeAliases = dict [ "c_int", "i32"; "float", "f64"; "double", "f64" ]

let tcon n = TCon(n, [])
let tInt, tBool, tUnit, tStr, tCStr = tcon "int", tcon "bool", tcon "unit", tcon "string", tcon "cstr"
let tChar = tcon "char"

let mutable private nextVar = 0

/// How many type variables were made (a checked snapshot carries the count on).
let typeVars () = nextVar
let setTypeVars (n: int) = nextVar <- max nextVar n

let fresh kind =
    nextVar <- nextVar + 1
    TVar(ref (Unbound(nextVar, kind)))

let rec prune t =
    match t with
    | TVar r ->
        match r.Value with
        | Link t -> prune t
        | Unbound _ -> t
    | _ -> t

let private defaultOf (k: Kind) =
    let fits n =
        (k.allowed |> Option.forall (fun s -> s.Contains n))
        && k.traits |> Set.forall (fun tr -> hasBuiltinImpl tr n)

    match [ "int"; "f64"; "string"; "bool"; "unit" ] |> List.tryFind fits with
    | Some n -> tcon n
    | None ->
        match k.allowed with
        | Some s -> tcon (Seq.head s)
        | None -> tInt

/// A measure in normal form: variables expanded, like terms merged, zeros dropped, sorted.
let rec normMeas (t: Ty) : (string * int) list * (Ty * int) list =
    let units = Dictionary<string, int>()
    let vars = ResizeArray<Ty * int>()

    let addVar (v: Ty) e =
        let same (w: Ty) =
            match v, w with
            | TVar a, TVar b -> obj.ReferenceEquals(a, b)
            | TGen i, TGen j -> i = j
            | _ -> false

        match Seq.tryFindIndex (fst >> same) vars with
        | Some i -> vars[i] <- (v, snd vars[i] + e)
        | None -> vars.Add(v, e)

    let rec go (t: Ty) k =
        match prune t with
        | TMeas(us, vs) ->
            for u, e in us do
                units[u] <- (match units.TryGetValue u with
                             | true, x -> x
                             | _ -> 0)
                            + e * k

            for v, e in vs do
                go v (e * k)
        | v -> addVar v k

    go t 1

    [ for kv in units do
          if kv.Value <> 0 then
              yield kv.Key, kv.Value ]
    |> List.sortBy fst,
    vars |> Seq.filter (fun (_, e) -> e <> 0) |> List.ofSeq

let measOne = TMeas([], [])

let isOneMeas t =
    match normMeas t with
    | [], [] -> true
    | _ -> false

/// A numeric type with a measure; unitless when the measure is 1.
let numWith (n: string) (m: Ty) =
    if isOneMeas m then TCon(n, []) else TCon(n, [ TMeas(normMeas m) ])

let measOf (args: Ty list) =
    match args with
    | [ m ] -> m
    | _ -> measOne

let measMul (a: Ty) (b: Ty) = TMeas(normMeas (TMeas([], [ a, 1; b, 1 ])))
let measDiv (a: Ty) (b: Ty) = TMeas(normMeas (TMeas([], [ a, 1; b, -1 ])))

/// The library's namespaces, open in every module at the lowest precedence: `List.map` is
/// Collections.List.map and `File.exists` IO.File.exists, unless the program defines its own.
let autoOpens = [ "Collections"; "Text"; "IO"; "Diagnostics" ]

/// A name as programs write it: without an auto-opened namespace (Collections.Map -> Map).
let shortName (q: string) =
    match autoOpens |> List.tryFind (fun ns -> q.StartsWith(ns + ".")) with
    | Some ns -> q.Substring(ns.Length + 1)
    | None -> q

/// A type as text. With full, names keep their namespaces (for symbol names and lookup keys,
/// which must tell a program's own Map from Collections.Map); without, they read as written.
let rec showWith (full: bool) t =
    let show = showWith full

    match prune t with
    | TMeas _ as m ->
        let us, vs = normMeas m

        let term (name: string) e =
            if abs e = 1 then name else sprintf "%s^%d" name (abs e)

        let parts =
            (us |> List.map (fun (u, e) -> term u e, e))
            @ (vs |> List.map (fun (v, e) -> term (show v) e, e))

        let pos = parts |> List.filter (fun (_, e) -> e > 0) |> List.map fst
        let neg = parts |> List.filter (fun (_, e) -> e < 0) |> List.map fst

        match pos, neg with
        | [], [] -> "1"
        | _, [] -> String.concat " " pos
        | [], _ -> "1/" + String.concat " " neg
        | _ -> String.concat " " pos + "/" + String.concat " " neg
    | TCon(n, args) ->
        let n = if full then n else shortName n
        if args.IsEmpty then n else n + "<" + (args |> List.map show |> String.concat ", ") + ">"
    | TFun(a, b) ->
        match prune a with
        | TFun _ -> "(" + show a + ") -> " + show b
        | _ -> show a + " -> " + show b
    | TTuple ts ->
        ts
        |> List.map (fun t ->
            match prune t with
            | TTuple _
            | TFun _ -> "(" + show t + ")"
            | _ -> show t)
        |> String.concat " * "
    | TGen i -> "'" + string (char (int 'a' + i))
    | TVar r ->
        match r.Value with
        | Unbound(_, { allowed = Some k }) when k.Contains "int" -> "int"
        | Unbound(_, { allowed = Some k }) when k.Contains "f64" -> "f64"
        | Unbound(_, { allowed = Some k }) when k.Contains "string" -> "string"
        | Unbound(id, _) -> sprintf "'t%d" id
        | Link t -> show t

let show = showWith false
let showFull = showWith true

/// Fully resolves a type, defaulting unconstrained variables (int, f64 or string by kind).
let rec resolve t =
    match prune t with
    | TVar r ->
        match r.Value with
        | Unbound(_, k) ->
            let d = defaultOf k
            r.Value <- Link d
            d
        | Link t -> resolve t
    | TCon(n, args) -> TCon(n, List.map resolve args)
    | TFun(a, b) -> TFun(resolve a, resolve b)
    | TTuple ts -> TTuple(List.map resolve ts)
    | TGen _ as t -> t
    | TMeas(us, vs) ->
        // an unconstrained measure variable is 1
        for v, _ in vs do
            match prune v with
            | TVar r -> r.Value <- Link measOne
            | _ -> ()

        TMeas(normMeas (TMeas(us, vs)))

/// Replaces TGen i with args[i].
let rec substGen (args: Ty list) t =
    match prune t with
    | TGen i -> List.item i args
    | TMeas(us, vs) -> TMeas(normMeas (TMeas(us, vs |> List.map (fun (v, e) -> substGen args v, e))))
    | TCon(n, a) -> TCon(n, List.map (substGen args) a)
    | TFun(a, b) -> TFun(substGen args a, substGen args b)
    | TTuple ts -> TTuple(List.map (substGen args) ts)
    | t -> t

type TypeDef =
    | RecordDef of (string * Ty) list // field types may mention TGen (type parameters)
    | UnionDef of (string * Ty list) list

type TypeInfo = { npars: int; def: TypeDef }

// ---------------------------------------------------------------- core IR

type CPat =
    | CPWild
    | CPVar of string * Ty
    | CPInt of int64
    | CPStr of string
    | CPBool of bool
    | CPTuple of CPat list
    | CPRecord of record: string * (string * CPat) list // every field, in declaration order
    | CPCtor of union: string * tag: int * CPat list
    | CPOr of CPat * CPat
    | CPAs of CPat * string * Ty

type CExpr = { k: CKind; ty: Ty }

and CKind =
    | CInt of int64
    | CFloat of float
    | CBool of bool
    | CStr of string
    | CUnit
    | CLocal of string // variable names are unique per program after type checking
    | CGlobalVal of string // a top-level value computed at startup (not a constant)
    | CGlobal of string * Ty list option // top-level function; instantiation (None = enclosing one)
    | CApp of CExpr * CExpr list
    | CLam of (string * Ty) list * CExpr
    | CLetFun of string * bool * (string * Ty) list * CExpr * CExpr
    | CLetRec of (string * (string * Ty) list * CExpr) list * CExpr // local functions that call each other, then the rest
    | CExtern of string * CExpr list
    | CPrim of string * CExpr list
    | CBin of string * CExpr * CExpr
    | CNeg of CExpr
    | CNot of CExpr
    | CIf of CExpr * CExpr * CExpr
    | CLet of string * CExpr * CExpr
    | CSeq of CExpr * CExpr
    | CTuple of CExpr list // tuples and records (fields in declaration order)
    | CField of CExpr * int
    | CCtor of union: string * tag: int * CExpr list
    | CMatch of CExpr * (CPat * CExpr option * CExpr) list
    | CLetMut of string * CExpr * CExpr
    | CAssign of string * CExpr
    /// a.[i] <- v on a `let mutable` array: in place when the array is unique, else copied first
    | CArraySet of string * CExpr * CExpr
    | CWhile of CExpr * CExpr
    | CFor of string * CExpr * CExpr * CExpr * CExpr // var, from, step, to, body
    | CLine of int * CExpr
    // after closure conversion
    | CCallDirect of string * CExpr list
    | CMkClosure of string * CExpr list // function, values for its first parameters
    | CApplyClo of CExpr * CExpr list // a closure applied to arguments
    // after RC insertion
    | CDup of string * Ty * CExpr
    | CDrop of string * Ty * CExpr
    /// Specialized drop of a matched cell (var, type, tag, kept fields, reuse token, body).
    /// Unique: kept fields move out, the rest are dropped, and the cell is freed or becomes
    /// the token. Shared: kept fields are dup'ed and the count decremented; token = null.
    | CDropFields of string * Ty * int * Set<int> * string option * CExpr
    | CCtorAt of string * union: string * tag: int * CExpr list // constructor built in token's cell if non-null
    | CFreeToken of string * CExpr
    // after match lowering
    /// A join point (from a decision tree): `rest`, whose paths may end in a jump to it, then
    /// `body` with the parameters bound to the jump's arguments. A block with phis, not a
    /// function: the body refers only to its parameters (and other join points).
    | CJoin of name: string * pars: (string * Ty) list * body: CExpr * rest: CExpr
    | CJump of string * CExpr list // to a join point, in a tail position of its rest

/// Rebuilds a node with f applied to each direct child expression.
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
    | CApp(h, args) -> CApp(f h, List.map f args)
    | CLam(ps, b) -> CLam(ps, f b)
    | CLetFun(n, r, ps, b, rest) -> CLetFun(n, r, ps, f b, f rest)
    | CLetRec(fs, rest) -> CLetRec(fs |> List.map (fun (n, ps, b) -> n, ps, f b), f rest)
    | CExtern(n, args) -> CExtern(n, List.map f args)
    | CPrim(n, args) -> CPrim(n, List.map f args)
    | CBin(op, a, b) -> CBin(op, f a, f b)
    | CNeg a -> CNeg(f a)
    | CNot a -> CNot(f a)
    | CIf(c, t, e) -> CIf(f c, f t, f e)
    | CLet(x, v, b) -> CLet(x, f v, f b)
    | CSeq(a, b) -> CSeq(f a, f b)
    | CTuple xs -> CTuple(List.map f xs)
    | CField(r, i) -> CField(f r, i)
    | CCtor(u, t, args) -> CCtor(u, t, List.map f args)
    | CMatch(s, cases) -> CMatch(f s, cases |> List.map (fun (p, g, b) -> p, Option.map f g, f b))
    | CLetMut(x, v, b) -> CLetMut(x, f v, f b)
    | CAssign(x, v) -> CAssign(x, f v)
    | CArraySet(x, i, v) -> CArraySet(x, f i, f v)
    | CWhile(c, b) -> CWhile(f c, f b)
    | CFor(x, a, s, b, body) -> CFor(x, f a, f s, f b, f body)
    | CLine(l, e) -> CLine(l, f e)
    | CCallDirect(n, args) -> CCallDirect(n, List.map f args)
    | CMkClosure(n, args) -> CMkClosure(n, List.map f args)
    | CApplyClo(c, args) -> CApplyClo(f c, List.map f args)
    | CDup(x, t, e) -> CDup(x, t, f e)
    | CDrop(x, t, e) -> CDrop(x, t, f e)
    | CDropFields(x, t, tag, keep, tok, e) -> CDropFields(x, t, tag, keep, tok, f e)
    | CCtorAt(tok, u, tag, args) -> CCtorAt(tok, u, tag, List.map f args)
    | CFreeToken(tok, e) -> CFreeToken(tok, f e)
    | CJoin(j, ps, b, r) ->
        let r' = f r // the rest runs first
        CJoin(j, ps, f b, r')
    | CJump(j, args) -> CJump(j, List.map f args)

/// Direct child expressions, in evaluation order.
let children (k: CKind) : CExpr list =
    let acc = ResizeArray()

    mapChildren
        (fun e ->
            acc.Add e
            e)
        k
    |> ignore

    List.ofSeq acc

/// Variables bound by a pattern.
let rec patVars p =
    match p with
    | CPWild
    | CPInt _
    | CPStr _
    | CPBool _ -> []
    | CPVar(x, t) -> [ x, t ]
    | CPAs(p, x, t) -> (x, t) :: patVars p
    | CPTuple ps
    | CPCtor(_, _, ps) -> List.collect patVars ps
    | CPRecord(_, fs) -> fs |> List.collect (snd >> patVars)
    | CPOr(a, _) -> patVars a

let rec mapPatTypes (f: Ty -> Ty) p =
    match p with
    | CPVar(x, t) -> CPVar(x, f t)
    | CPAs(p, x, t) -> CPAs(mapPatTypes f p, x, f t)
    | CPTuple ps -> CPTuple(List.map (mapPatTypes f) ps)
    | CPRecord(r, fs) -> CPRecord(r, fs |> List.map (fun (n, p) -> n, mapPatTypes f p))
    | CPCtor(u, tag, ps) -> CPCtor(u, tag, List.map (mapPatTypes f) ps)
    | CPOr(a, b) -> CPOr(mapPatTypes f a, mapPatTypes f b)
    | p -> p

/// The names a node binds itself (not those bound inside its children).
let ownBinders (k: CKind) : string list =
    match k with
    | CLam(ps, _) -> List.map fst ps
    | CLetFun(n, _, ps, _, _) -> n :: List.map fst ps
    | CLetRec(fs, _) -> fs |> List.collect (fun (n, ps, _) -> n :: List.map fst ps)
    | CJoin(_, ps, _, _) -> List.map fst ps
    | CLet(x, _, _)
    | CLetMut(x, _, _)
    | CFor(x, _, _, _, _) -> [ x ]
    | CMatch(_, cases) -> cases |> List.collect (fun (p, _, _) -> patVars p |> List.map fst)
    | _ -> []

/// Names bound inside an expression (binders), excluding the expression's free variables.
let rec binders (e: CExpr) : string list =
    ownBinders e.k @ (children e.k |> List.collect binders)

/// Core as indented text, for reading what the optimizer did (ZS_DUMP_CORE=name).
let rec showCore (ind: int) (e: CExpr) : string =
    let pad = String.replicate ind "  "
    let sub (x: CExpr) = showCore (ind + 1) x
    let line (s: string) = pad + s

    let rec pat p =
        match p with
        | CPWild -> "_"
        | CPVar(x, _) -> x
        | CPInt n -> string n
        | CPStr s -> sprintf "%A" s
        | CPBool b -> string b
        | CPTuple ps -> "(" + (ps |> List.map pat |> String.concat ", ") + ")"
        | CPRecord(_, fs) -> "{ " + (fs |> List.map (fun (n, q) -> n + " = " + pat q) |> String.concat "; ") + " }"
        | CPCtor(_, tag, ps) -> sprintf "#%d(%s)" tag (ps |> List.map pat |> String.concat ", ")
        | CPOr(a, b) -> pat a + " | " + pat b
        | CPAs(q, x, _) -> pat q + " as " + x

    let flat (x: CExpr) = (showCore 0 x).Replace("\n", " ")
    let args (xs: CExpr list) = xs |> List.map flat |> String.concat ", "

    match e.k with
    | CInt n -> line (string n)
    | CFloat f -> line (string f)
    | CBool b -> line (string b)
    | CStr s -> line (sprintf "%A" s)
    | CUnit -> line "()"
    | CLocal x -> line x
    | CGlobalVal x
    | CGlobal(x, _) -> line ("@" + x)
    | CLet(x, v, b) -> line ("let " + x + " = " + flat v) + "\n" + showCore ind b
    | CLetMut(x, v, b) -> line ("let mutable " + x + " = " + flat v) + "\n" + showCore ind b
    | CIf(c, t, f) -> line ("if " + flat c) + "\n" + sub t + "\n" + line "else" + "\n" + sub f
    | CMatch(s, cases) ->
        line ("match " + flat s)
        + (cases |> List.map (fun (p, g, b) -> "\n" + line ("| " + pat p + (match g with Some g -> " when " + flat g | None -> "") + " ->") + "\n" + sub b) |> String.concat "")
    | CDup(x, _, b) -> line ("dup " + x) + "\n" + showCore ind b
    | CDrop(x, _, b) -> line ("drop " + x) + "\n" + showCore ind b
    | CDropFields(x, _, tag, keep, tok, b) ->
        line (sprintf "dropfields %s #%d keep %A%s" x tag (Set.toList keep) (match tok with Some t -> " token " + t | None -> "")) + "\n" + showCore ind b
    | CFreeToken(t, b) -> line ("free " + t) + "\n" + showCore ind b
    | CCtorAt(t, _, tag, xs) -> line (sprintf "#%d@%s(%s)" tag t (args xs))
    | CCtor(_, tag, xs) -> line (sprintf "#%d(%s)" tag (args xs))
    | CJoin(j, ps, b, r) -> showCore ind r + "\n" + line ("join " + j + "(" + (ps |> List.map fst |> String.concat ", ") + ") =") + "\n" + sub b
    | CJump(j, xs) -> line ("jump " + j + "(" + args xs + ")")
    | CCallDirect(f, xs) -> line (f + "(" + args xs + ")")
    | CPrim(op, xs) -> line (op + "(" + args xs + ")")
    | CBin(op, a, b) -> line (flat a + " " + op + " " + flat b)
    | CTuple xs -> line ("(" + args xs + ")")
    | CField(r, i) -> line (flat r + "." + string i)
    | CLine(_, x) -> showCore ind x
    | CSeq(a, b) -> showCore ind a + "\n" + showCore ind b
    | CAssign(x, v) -> line (x + " <- " + flat v)
    | CWhile(c, b) -> line ("while " + flat c) + "\n" + sub b
    | CFor(x, a, _, b, body) -> line ("for " + x + " in " + flat a + " .. " + flat b) + "\n" + sub body
    | CMkClosure(f, xs) -> line ("closure " + f + "(" + args xs + ")")
    | CApplyClo(c, xs) -> line (flat c + " $ (" + args xs + ")")
    | CExtern(f, xs) -> line ("extern " + f + "(" + args xs + ")")
    | CNot a -> line ("not " + flat a)
    | CNeg a -> line ("-" + flat a)
    | k -> line (sprintf "<%s>" ((sprintf "%A" k).Split(' ', '\n')[0]))

/// The variables a node references itself (not through its children).
let private ownRefs (e: CExpr) : (string * Ty) list =
    match e.k with
    | CLocal x -> [ x, e.ty ]
    | CAssign(x, v) -> [ x, v.ty ]
    | CArraySet(x, _, v) -> [ x, TCon("array", [ v.ty ]) ]
    | CDup(x, t, _)
    | CDrop(x, t, _)
    | CDropFields(x, t, _, _, _, _) -> [ x, t ]
    | _ -> []

/// Variables referenced by an expression (names are unique, so free = referenced - bound).
let rec refs (e: CExpr) : (string * Ty) list =
    ownRefs e @ (children e.k |> List.collect refs)

let freeVars (e: CExpr) : Set<string> =
    Set.difference (refs e |> List.map fst |> Set.ofList) (Set.ofList (binders e))

/// freeVars, remembered per node (by reference): bottom-up, each node's set from its
/// children's, for a pass that asks about the same nodes again and again. Names are unique,
/// so a node's free variables are its children's and its own references, less what it binds.
let cachedFreeVars () : CExpr -> Set<string> =
    let cache = System.Collections.Generic.Dictionary<CExpr, Set<string>>(HashIdentity.Reference)

    let rec fv (e: CExpr) =
        match cache.TryGetValue e with
        | true, s -> s
        | _ ->
            let below = children e.k |> List.map fv |> Set.unionMany
            let s = Set.difference (Set.union below (ownRefs e |> List.map fst |> Set.ofList)) (Set.ofList (ownBinders e.k))
            cache[e] <- s
            s

    fv

type FunDef =
    { name: string
      pars: (string * Ty) list
      ret: Ty
      body: CExpr
      ngen: int // number of quantified variables (TGen 0..ngen-1)
      file: string // where it is defined (debug info)
      line: int }

type ExternSig =
    { pars: Ty list
      ret: Ty
      variadic: bool }

type TraitMethod =
    { owner: string
      name: string
      ty: Ty // TGen 0 is the trait's type parameter
      isConst: bool } // `abstract zero : 'a`: implemented as unit -> 'a

type Program =
    { types: Dictionary<string, TypeInfo>
      externs: Dictionary<string, ExternSig>
      funs: FunDef list
      traitMethods: Dictionary<string, TraitMethod> // "Show.show" -> method
      impls: Dictionary<string * string, Dictionary<string, string>> // (trait, type) -> method -> function
      exports: Export list
      values: (string * string) list // top-level values computed at startup, in order: name, init function
      tests: string list // [<Test>] functions (unit -> unit), in source order
      clayouts: HashSet<string> // [<CLayout>] records
      errors: Diagnostic list // when type-checking in collect mode
      hovers: Hover list // inferred types at source positions (editor support)
      memberNames: Dictionary<string, string list> } // type -> its members (completion)

and Diagnostic =
    { file: string
      line: int
      col: int // 0 = unknown
      msg: string }

/// What an identifier at a position is: a use, or a binder (an inlay-hint candidate when its
/// type wasn't written).
and Hover =
    { hfile: string
      hline: int
      hcol: int
      hlen: int
      name: string
      hty: Ty
      constraints: string // "'a : Add" for generic functions
      decl: bool // a top-level function's name
      key: string // what it refers to: a local's unique name or a global's qualified name ("" = unknown)
      isDef: bool // this is where `key` is defined
      inlay: bool }

/// [<Export "cname">]: a C entry point for a monomorphic function.
and Export =
    { cname: string
      fname: string
      pars: Ty list // unit parameters excluded
      ret: Ty }

/// Does a value of this type hold a reference count (directly or in a field)?
/// Does a value of this type hold a reference count (directly or in a field)? `visiting`: the
/// unions being looked through, so a recursive union is found (and stays boxed).
let rec private heapIn (types: Dictionary<string, TypeInfo>) (visiting: Set<string>) t =
    match prune t with
    | TCon(("string" | "array" | "Buffer" | "ref"), _)
    | TFun _ -> true
    | TCon(n, args) ->
        match types.TryGetValue n with
        | true, { def = UnionDef _ } -> visiting.Contains n || not (plainUnionIn types visiting t)
        | true, { def = RecordDef fs } -> fs |> List.exists (fun (_, ft) -> heapIn types visiting (substGen args ft))
        | _ -> false
    | TTuple ts -> List.exists (heapIn types visiting) ts
    | _ -> false

/// A union kept as a plain value ({ tag, fields }) instead of a heap cell: not recursive, at
/// most 4 fields over all its cases, none of them holding a reference count (option<int>,
/// result<int, f64>, enums, small state machines). Others are boxed.
and private plainUnionIn (types: Dictionary<string, TypeInfo>) (visiting: Set<string>) t =
    match prune t with
    | TCon(n, args) ->
        match types.TryGetValue n with
        | true, { def = UnionDef cs } ->
            let fields = cs |> List.collect (fun (_, fs) -> fs |> List.map (substGen args))
            fields.Length <= 4 && fields |> List.forall (fun ft -> not (heapIn types (visiting.Add n) ft))
        | _ -> false
    | _ -> false

let needsRc (types: Dictionary<string, TypeInfo>) t = heapIn types Set.empty t

let plainUnion (types: Dictionary<string, TypeInfo>) t = plainUnionIn types Set.empty t

/// How a union's values are represented.
type UnionRep =
    /// A value: { tag, every case's fields } (small, not recursive, no heap data).
    | Plain
    /// Two cases, one without fields and one whose single field is a pointer: that field
    /// itself, or a static object for the other case. So `Some s` allocates nothing for
    /// option<string>.
    | Niche of noneTag: int * payload: Ty
    /// Heap cells for the cases with fields, with a tag in the cell only when there are several
    /// such cases. A case without fields is a static cell, told apart by its address.
    | Boxed of tagged: bool

let private cases (types: Dictionary<string, TypeInfo>) t =
    match prune t with
    | TCon(n, args) ->
        match types.TryGetValue n with
        | true, { def = UnionDef cs } -> Some(cs |> List.map (fun (c, fs) -> c, List.map (substGen args) fs))
        | _ -> None
    | _ -> None

/// Two cases, one without fields and one with a single field (option's shape): the tag of the
/// one without, and the field's type.
let private nicheShaped cs =
    match cs with
    | [ (_, []); (_, [ f ]) ] -> Some(0, f)
    | [ (_, [ f ]); (_, []) ] -> Some(1, f)
    | _ -> None

let unionRep (types: Dictionary<string, TypeInfo>) (t: Ty) : UnionRep =
    // an object that can't be the static one standing for a niche's empty case: a union of
    // option's shape may be that one, so it never is a niche's payload (option<option<string>>
    // boxes its outer Some)
    let pointer (f: Ty) =
        match prune f with
        | TCon(("string" | "array" | "Buffer" | "ref"), _)
        | TFun _ -> true
        | f ->
            match cases types f with
            | Some cs -> (nicheShaped cs).IsNone && not (plainUnion types f)
            | None -> false

    if plainUnion types t then
        Plain
    else
        let cs = (cases types t).Value

        match nicheShaped cs with
        | Some(noneTag, f) when pointer f -> Niche(noneTag, f)
        | _ -> Boxed((cs |> List.filter (fun (_, fs) -> not fs.IsEmpty)).Length > 1)

/// The shape of the cell a boxed union's case is built in (with a tag?, field types), which
/// reuse must match; None for a case that isn't a cell.
let cellShape (types: Dictionary<string, TypeInfo>) (t: Ty) (tag: int) : (bool * Ty list) option =
    match unionRep types t, cases types t with
    | Boxed tagged, Some cs when not (snd cs[tag]).IsEmpty -> Some(tagged, snd cs[tag])
    | _ -> None
