/// Types and the typed Core IR shared by every pass after parsing.
module Core

open System.Collections.Generic

// ---------------------------------------------------------------- types

/// None = any type; Some s = must become one of these nullary type constructors.
type Kind = Set<string> option

type Ty =
    | TCon of string * Ty list // int, f64, string, list<_>, user types; args can later carry units of measure
    | TFun of Ty * Ty
    | TTuple of Ty list
    | TVar of TV ref
    | TGen of int // quantified variable of a type scheme or type definition

and TV =
    | Unbound of int * Kind
    | Link of Ty

let ints = set [ "int"; "i8"; "i16"; "i32"; "u8"; "u16"; "u32"; "u64"; "usize" ]
let unsigned = set [ "u8"; "u16"; "u32"; "u64"; "usize" ]
let floats = set [ "f64"; "f32" ]
let nums = ints + floats
let kInt, kFloat, kNum = Some ints, Some floats, Some nums
let kPlus = Some(nums.Add "string")
let kOrd = Some(nums.Add "string")
let kEq = Some(nums + set [ "string"; "bool"; "unit" ])
let kStrLit = Some(set [ "string"; "cstr" ])
let kShow = Some(nums + set [ "string"; "bool" ])
let prims = nums + set [ "bool"; "string"; "cstr"; "unit" ]

/// Built-in generic type constructors and their arity.
let builtinCons = dict [ "array", 1; "ref", 1 ]

let typeAliases = dict [ "i64", "int"; "c_int", "i32"; "float", "f64"; "double", "f64" ]

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
    match k with
    | None -> tInt
    | Some s when s.Contains "int" -> tInt
    | Some s when s.Contains "f64" -> tcon "f64"
    | Some s when s.Contains "string" -> tStr
    | Some s -> tcon (Seq.head s)

let rec show t =
    match prune t with
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
        | Unbound(_, Some k) when k.Contains "int" -> "int"
        | Unbound(_, Some k) when k.Contains "f64" -> "f64"
        | Unbound(_, Some k) when k.Contains "string" -> "string"
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

/// Replaces TGen i with args[i].
let rec substGen (args: Ty list) t =
    match prune t with
    | TGen i -> List.item i args
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
      ngen: int } // number of quantified variables (TGen 0..ngen-1)

type ExternSig =
    { pars: Ty list
      ret: Ty
      variadic: bool }

type Program =
    { types: Dictionary<string, TypeInfo>
      externs: Dictionary<string, ExternSig>
      funs: FunDef list }

/// Does a value of this type hold a reference count (directly or in a field)?
let rec needsRc (types: Dictionary<string, TypeInfo>) t =
    match prune t with
    | TCon(("string" | "array" | "ref"), _)
    | TFun _ -> true
    | TCon(n, args) ->
        match types.TryGetValue n with
        | true, { def = UnionDef _ } -> true
        | true, { def = RecordDef fs } -> fs |> List.exists (fun (_, ft) -> needsRc types (substGen args ft))
        | _ -> false
    | TTuple ts -> List.exists (needsRc types) ts
    | _ -> false
