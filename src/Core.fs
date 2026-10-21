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
let prims = nums + set [ "bool"; "string"; "cstr"; "cptr"; "unit" ] // cptr: any other C pointer, opaque
let kAny = { allowed = None; traits = Set.empty }
let private allow s = { allowed = Some s; traits = Set.empty }
let kInt, kFloat, kNumeric = allow ints, allow floats, allow nums
let kStrLit = allow (set [ "string"; "cstr" ])
let kTrait (t: string) = { allowed = None; traits = set [ t ] }

/// Built-in impls of the prelude's operator traits for primitive types.
let builtinImpls =
    dict
        [ "Add", nums.Add "string"
          "Num", nums
          "Eq", nums + set [ "string"; "bool"; "unit" ]
          "Ord", nums.Add "string"
          "Show", nums + set [ "string"; "bool" ]
          "Hash", nums + set [ "string"; "bool" ] ]

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

let mutable private nextVar = 0

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

let rec show t =
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
    | TCon(n, []) -> n
    | TCon(n, args) -> n + "<" + (args |> List.map show |> String.concat ", ") + ">"
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
    | CPBool of bool
    | CPTuple of CPat list
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
    | CApplyClo of CExpr * CExpr
    // after RC insertion
    | CDup of string * Ty * CExpr
    | CDrop of string * Ty * CExpr
    /// Specialized drop of a matched cell (var, type, tag, kept fields, reuse token, body).
    /// Unique: kept fields move out, the rest are dropped, and the cell is freed or becomes
    /// the token. Shared: kept fields are dup'ed and the count decremented; token = null.
    | CDropFields of string * Ty * int * Set<int> * string option * CExpr
    | CCtorAt of string * union: string * tag: int * CExpr list // constructor built in token's cell if non-null
    | CFreeToken of string * CExpr

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
    | CApplyClo(c, a) -> CApplyClo(f c, f a)
    | CDup(x, t, e) -> CDup(x, t, f e)
    | CDrop(x, t, e) -> CDrop(x, t, f e)
    | CDropFields(x, t, tag, keep, tok, e) -> CDropFields(x, t, tag, keep, tok, f e)
    | CCtorAt(tok, u, tag, args) -> CCtorAt(tok, u, tag, List.map f args)
    | CFreeToken(tok, e) -> CFreeToken(tok, f e)

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
    | CPBool _ -> []
    | CPVar(x, t) -> [ x, t ]
    | CPAs(p, x, t) -> (x, t) :: patVars p
    | CPTuple ps
    | CPCtor(_, _, ps) -> List.collect patVars ps
    | CPOr(a, _) -> patVars a

let rec mapPatTypes (f: Ty -> Ty) p =
    match p with
    | CPVar(x, t) -> CPVar(x, f t)
    | CPAs(p, x, t) -> CPAs(mapPatTypes f p, x, f t)
    | CPTuple ps -> CPTuple(List.map (mapPatTypes f) ps)
    | CPCtor(u, tag, ps) -> CPCtor(u, tag, List.map (mapPatTypes f) ps)
    | CPOr(a, b) -> CPOr(mapPatTypes f a, mapPatTypes f b)
    | p -> p

/// Names bound inside an expression (binders), excluding the expression's free variables.
let rec binders (e: CExpr) : string list =
    let own =
        match e.k with
        | CLam(ps, _) -> List.map fst ps
        | CLetFun(n, _, ps, _, _) -> n :: List.map fst ps
        | CLet(x, _, _)
        | CLetMut(x, _, _)
        | CFor(x, _, _, _, _) -> [ x ]
        | CMatch(_, cases) -> cases |> List.collect (fun (p, _, _) -> patVars p |> List.map fst)
        | _ -> []

    own @ (children e.k |> List.collect binders)

/// Variables referenced by an expression (names are unique, so free = referenced - bound).
let rec refs (e: CExpr) : (string * Ty) list =
    let own =
        match e.k with
        | CLocal x -> [ x, e.ty ]
        | CAssign(x, v) -> [ x, v.ty ]
        | CArraySet(x, _, v) -> [ x, TCon("array", [ v.ty ]) ]
        | CDup(x, t, _)
        | CDrop(x, t, _)
        | CDropFields(x, t, _, _, _, _) -> [ x, t ]
        | _ -> []

    own @ (children e.k |> List.collect refs)

let freeVars (e: CExpr) : Set<string> =
    Set.difference (refs e |> List.map fst |> Set.ofList) (Set.ofList (binders e))

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
