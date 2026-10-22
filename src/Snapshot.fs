/// The type checker's state (Typer.State) in a binary form, for the checked library cached
/// between builds. Written out type by type, without reflection, so reading it back takes a few
/// milliseconds. An object reached twice is written once, so what is shared stays shared: a
/// type variable's cell, a syntax node a dictionary is keyed by. Syntax nodes keep their source
/// positions. A new field of State, or a new case of the syntax tree or of Core (before closure
/// conversion), needs its place here: tests/cache.sh fails until it has one.
module Snapshot

open System.Collections.Generic
open System.IO
open Syntax
open Core
open Typer

/// Thrown for something the format has no place for: the state isn't cached.
exception Unwritable of string

// ---------------------------------------------------------------- writing

type private W =
    { w: BinaryWriter
      ids: Dictionary<obj, int>
      strings: Dictionary<string, int>
      position: obj -> (int * int * int) option }

let private int' (c: W) (i: int) = c.w.Write i
let private bool' (c: W) (b: bool) = c.w.Write b
let private tag (c: W) (t: int) = c.w.Write(byte t)

let private str (c: W) (s: string) =
    match c.strings.TryGetValue s with
    | true, i -> c.w.Write i
    | _ ->
        let i = c.strings.Count
        c.strings[s] <- i
        c.w.Write i // the next number: the string follows
        c.w.Write s

let private list' (c: W) (f: W -> 'a -> unit) (xs: 'a list) =
    c.w.Write(List.length xs)

    for x in xs do
        f c x

let private seq' (c: W) (f: W -> 'a -> unit) (xs: 'a seq) =
    let a = Array.ofSeq xs
    c.w.Write a.Length

    for x in a do
        f c x

let private opt (c: W) (f: W -> 'a -> unit) (x: 'a option) =
    match x with
    | Some v ->
        c.w.Write true
        f c v
    | None -> c.w.Write false

/// An object written once; later uses are its number. With pos, its source position follows.
let private shared (c: W) (o: obj) (pos: bool) (body: unit -> unit) =
    match c.ids.TryGetValue o with
    | true, i ->
        c.w.Write 0uy
        c.w.Write i
    | _ ->
        c.w.Write 1uy
        body ()

        if pos then
            match c.position o with
            | Some(l, col, n) ->
                c.w.Write true
                c.w.Write l
                c.w.Write col
                c.w.Write n
            | None -> c.w.Write false

        c.ids[o] <- c.ids.Count

let rec private ty (c: W) (t: Ty) =
    shared c t false (fun () ->
        match t with
        | TCon(n, args) ->
            tag c 0
            str c n
            list' c ty args
        | TFun(a, b) ->
            tag c 1
            ty c a
            ty c b
        | TTuple ts ->
            tag c 2
            list' c ty ts
        | TVar r ->
            tag c 3
            cell c r
        | TGen i ->
            tag c 4
            int' c i
        | TMeas(us, vs) ->
            tag c 5
            list' c (fun c (u, e) -> str c u; int' c e) us
            list' c (fun c (v, e) -> ty c v; int' c e) vs)

and private cell (c: W) (r: TV ref) =
    shared c r false (fun () ->
        match r.Value with
        | Unbound(id, k) ->
            tag c 0
            int' c id
            kind c k
        | Link t ->
            tag c 1
            ty c t)

and private kind (c: W) (k: Kind) =
    opt c (fun c s -> seq' c str s) k.allowed
    seq' c str k.traits

let private tyBinding (c: W) (x: string, t: Ty) =
    str c x
    ty c t

let rec private stype (c: W) (t: SType) =
    match t with
    | STName(n, args) ->
        tag c 0
        str c n
        list' c stype args
    | STVar v ->
        tag c 1
        str c v
    | STTuple ts ->
        tag c 2
        list' c stype ts
    | STFun(a, b) ->
        tag c 3
        stype c a
        stype c b
    | STMeasure ms ->
        tag c 4
        list' c (fun c (u, isVar, e) -> str c u; bool' c isVar; int' c e) ms

let rec private pat (c: W) (p: Pat) =
    shared c p true (fun () ->
        match p with
        | PWild -> tag c 0
        | PIdent(x, q) ->
            tag c 1
            str c x
            opt c pat q
        | PInt n ->
            tag c 2
            c.w.Write n
        | PChar n ->
            tag c 3
            int' c n
        | PStr s ->
            tag c 4
            str c s
        | PBool b ->
            tag c 5
            bool' c b
        | PUnit -> tag c 6
        | PTuple ps ->
            tag c 7
            list' c pat ps
        | POr(a, b) ->
            tag c 8
            pat c a
            pat c b
        | PAs(q, x) ->
            tag c 9
            pat c q
            str c x
        | PNamed fs ->
            tag c 10
            list' c (fun c (n, q) -> str c n; pat c q) fs
        | PRecord fs ->
            tag c 11
            list' c (fun c (n, q) -> str c n; pat c q) fs
        | PArgs ps ->
            tag c 12
            list' c pat ps)

let rec private expr (c: W) (e: Expr) =
    shared c e true (fun () ->
        match e with
        | Lit n ->
            tag c 0
            c.w.Write n
        | CharLit n ->
            tag c 1
            int' c n
        | FloatLit f ->
            tag c 2
            c.w.Write f
        | BoolLit b ->
            tag c 3
            bool' c b
        | StrLit s ->
            tag c 4
            str c s
        | UnitLit -> tag c 5
        | Var x ->
            tag c 6
            str c x
        | Call(f, args) ->
            tag c 7
            str c f
            list' c expr args
        | App(f, args) ->
            tag c 8
            expr c f
            list' c expr args
        | Lambda(ps, b) ->
            tag c 9
            list' c param ps
            expr c b
        | Bin(op, a, b) ->
            tag c 10
            str c op
            expr c a
            expr c b
        | Neg a ->
            tag c 11
            expr c a
        | Not a ->
            tag c 12
            expr c a
        | If(a, b, d) ->
            tag c 13
            expr c a
            expr c b
            opt c expr d
        | Let(p, t, v, b) ->
            tag c 14
            pat c p
            opt c stype t
            expr c v
            expr c b
        | LetFun(n, r, ps, t, b, rest) ->
            tag c 15
            str c n
            bool' c r
            list' c param ps
            opt c stype t
            expr c b
            expr c rest
        | LetRecGroup(fs, rest) ->
            tag c 16
            list' c expr fs
            expr c rest
        | LetMut(x, t, v, b) ->
            tag c 17
            str c x
            opt c stype t
            expr c v
            expr c b
        | Assign(a, b) ->
            tag c 18
            expr c a
            expr c b
        | While(a, b) ->
            tag c 19
            expr c a
            expr c b
        | For(x, a, s, b, body) ->
            tag c 20
            str c x
            expr c a
            opt c expr s
            expr c b
            expr c body
        | ForIn(x, xs, body) ->
            tag c 21
            str c x
            expr c xs
            expr c body
        | Seq(a, b) ->
            tag c 22
            expr c a
            expr c b
        | Tuple xs ->
            tag c 23
            list' c expr xs
        | RecordLit fs ->
            tag c 24
            list' c (fun c (n, v) -> str c n; expr c v) fs
        | Update(r, fs) ->
            tag c 25
            expr c r
            list' c (fun c (n, v) -> str c n; expr c v) fs
        | Field(r, f) ->
            tag c 26
            expr c r
            str c f
        | Index(a, i) ->
            tag c 27
            expr c a
            expr c i
        | ArrayLit xs ->
            tag c 28
            list' c expr xs
        | Match(s, cases) ->
            tag c 29
            expr c s
            list' c (fun c (p, g, b) -> pat c p; opt c expr g; expr c b) cases
        | Question a ->
            tag c 30
            expr c a
        | TryBind(p, v, rest) ->
            tag c 31
            pat c p
            expr c v
            expr c rest
        | DeriveCtx(s, a) ->
            tag c 32
            str c s
            expr c a
        | Measured(a, t) ->
            tag c 33
            expr c a
            stype c t
        | Typed(a, t) ->
            tag c 34
            expr c a
            stype c t
        | At(l, a) ->
            tag c 35
            int' c l
            expr c a
        | Unsafe a ->
            tag c 36
            expr c a)

and private param (c: W) (p: Pat, t: SType option) =
    pat c p
    opt c stype t

let rec private cpat (c: W) (p: CPat) =
    match p with
    | CPWild -> tag c 0
    | CPVar(x, t) ->
        tag c 1
        str c x
        ty c t
    | CPInt n ->
        tag c 2
        c.w.Write n
    | CPStr s ->
        tag c 3
        str c s
    | CPBool b ->
        tag c 4
        bool' c b
    | CPTuple ps ->
        tag c 5
        list' c cpat ps
    | CPRecord(r, fs) ->
        tag c 6
        str c r
        list' c (fun c (n, q) -> str c n; cpat c q) fs
    | CPCtor(u, t, ps) ->
        tag c 7
        str c u
        int' c t
        list' c cpat ps
    | CPOr(a, b) ->
        tag c 8
        cpat c a
        cpat c b
    | CPAs(q, x, t) ->
        tag c 9
        cpat c q
        str c x
        ty c t

let rec private cexpr (c: W) (e: CExpr) =
    shared c e false (fun () ->
        ty c e.ty

        match e.k with
        | CInt n ->
            tag c 0
            c.w.Write n
        | CFloat f ->
            tag c 1
            c.w.Write f
        | CBool b ->
            tag c 2
            bool' c b
        | CStr s ->
            tag c 3
            str c s
        | CUnit -> tag c 4
        | CLocal x ->
            tag c 5
            str c x
        | CGlobalVal x ->
            tag c 6
            str c x
        | CGlobal(g, inst) ->
            tag c 7
            str c g
            opt c (fun c ts -> list' c ty ts) inst
        | CApp(h, args) ->
            tag c 8
            cexpr c h
            list' c cexpr args
        | CLam(ps, b) ->
            tag c 9
            list' c tyBinding ps
            cexpr c b
        | CLetFun(n, r, ps, b, rest) ->
            tag c 10
            str c n
            bool' c r
            list' c tyBinding ps
            cexpr c b
            cexpr c rest
        | CLetRec(fs, rest) ->
            tag c 11
            list' c (fun c (n, ps, b) -> str c n; list' c tyBinding ps; cexpr c b) fs
            cexpr c rest
        | CExtern(n, args) ->
            tag c 12
            str c n
            list' c cexpr args
        | CPrim(n, args) ->
            tag c 13
            str c n
            list' c cexpr args
        | CBin(op, a, b) ->
            tag c 14
            str c op
            cexpr c a
            cexpr c b
        | CNeg a ->
            tag c 15
            cexpr c a
        | CNot a ->
            tag c 16
            cexpr c a
        | CIf(a, b, d) ->
            tag c 17
            cexpr c a
            cexpr c b
            cexpr c d
        | CLet(x, v, b) ->
            tag c 18
            str c x
            cexpr c v
            cexpr c b
        | CSeq(a, b) ->
            tag c 19
            cexpr c a
            cexpr c b
        | CTuple xs ->
            tag c 20
            list' c cexpr xs
        | CField(r, i) ->
            tag c 21
            cexpr c r
            int' c i
        | CCtor(u, t, args) ->
            tag c 22
            str c u
            int' c t
            list' c cexpr args
        | CMatch(s, cases) ->
            tag c 23
            cexpr c s
            list' c (fun c (p, g, b) -> cpat c p; opt c cexpr g; cexpr c b) cases
        | CLetMut(x, v, b) ->
            tag c 24
            str c x
            cexpr c v
            cexpr c b
        | CAssign(x, v) ->
            tag c 25
            str c x
            cexpr c v
        | CArraySet(x, i, v) ->
            tag c 26
            str c x
            cexpr c i
            cexpr c v
        | CWhile(a, b) ->
            tag c 27
            cexpr c a
            cexpr c b
        | CFor(x, a, s, b, body) ->
            tag c 28
            str c x
            cexpr c a
            cexpr c s
            cexpr c b
            cexpr c body
        | CLine(l, a) ->
            tag c 29
            int' c l
            cexpr c a
        | k -> raise (Unwritable(sprintf "%A" k))) // only the passes after checking make the others

let private typeDef (c: W) (d: TypeDef) =
    match d with
    | RecordDef fs ->
        tag c 0
        list' c tyBinding fs
    | UnionDef cs ->
        tag c 1
        list' c (fun c (n, ts) -> str c n; list' c ty ts) cs

let private memberParam (c: W) (p: MemberParam) =
    str c p.mname
    opt c stype p.mty
    bool' c p.optional
    opt c expr p.mdefault

let private deriveDef (c: W) (l: int, n: string, ps: Param list, ret: SType option, body: Expr) =
    int' c l
    str c n
    list' c param ps
    opt c stype ret
    expr c body

let private dict' (c: W) (k: W -> 'k -> unit) (v: W -> 'v -> unit) (d: Dictionary<'k, 'v>) =
    c.w.Write d.Count

    for KeyValue(key, value) in d do
        k c key
        v c value

let private pair (c: W) (a: string, b: string) =
    str c a
    str c b

/// Writes the state; position: a syntax node's source position.
let write (out: Stream) (st: State) (position: obj -> (int * int * int) option) =
    use w = new BinaryWriter(out, System.Text.Encoding.UTF8, true)

    let c =
        { w = w
          ids = Dictionary(HashIdentity.Reference)
          strings = Dictionary()
          position = position }

    let strSeq (c: W) (s: string seq) = seq' c str s
    let optStr (c: W) (s: string option) = opt c str s
    dict' c str (fun c (i: TypeInfo) -> int' c i.npars; typeDef c i.def) st.types
    dict' c str (fun c (u, t) -> str c u; int' c t) st.ctors
    strSeq c st.records
    dict' c str (fun c ds -> list' c (fun c d -> opt c expr d) ds) st.recordDefaults
    dict' c str (fun c ns -> list' c optStr ns) st.ctorFieldNames

    dict'
        c
        str
        (fun c (ms: Dictionary<string, MemberInfo>) ->
            dict' c str (fun c (m: MemberInfo) -> str c m.gname; bool' c m.isStatic; bool' c m.isProperty; list' c memberParam m.mpars) ms)
        st.members

    strSeq c st.memberTypeNames
    dict' c str (fun c (m: TraitMethod) -> str c m.owner; str c m.name; ty c m.ty; bool' c m.isConst) st.traitMethods
    dict' c str str st.traitAliases
    strSeq c st.traitNames
    dict' c pair (fun c t -> dict' c str str t) st.impls
    dict' c pair (fun c reqs -> list' c (fun c s -> strSeq c s) reqs) st.implRequires
    dict' c str (fun c defs -> list' c deriveDef defs) st.derives
    dict' c str optStr st.deriveModules
    dict' c str (fun c (f, total, n) -> str c f; bool' c total; int' c n) st.activePatterns
    strSeq c st.apCtors
    seq' c pair st.ownImpls
    seq' c pair st.autoDerived
    seq' c pair st.optOut
    dict' c str (fun c (g: Global) -> ty c g.ty; list' c kind g.kinds; int' c g.arity; bool' c g.defining) st.globals
    dict' c str (fun c (s: ExternSig) -> list' c ty s.pars; ty c s.ret; bool' c s.variadic) st.externs

    seq'
        c
        (fun c (f: FunDef) ->
            str c f.name
            list' c tyBinding f.pars
            ty c f.ret
            cexpr c f.body
            int' c f.ngen
            str c f.file
            int' c f.line)
        st.funs

    int' c st.counter.Value
    strSeq c st.measures
    strSeq c st.clayouts
    seq' c (fun c (e: Export) -> str c e.cname; str c e.fname; list' c ty e.pars; ty c e.ret) st.exports
    strSeq c st.tests
    dict' c str expr st.consts
    dict' c str ty st.globalValues
    seq' c pair st.valueList
    dict' c expr str st.literalRecords
    dict' c str optStr st.privates
    strSeq c st.moduleNames
    strSeq c st.mainNested
    strSeq c st.nestedModules
    dict' c str (fun c ms -> list' c str ms) st.enclosingOf
    int' c st.typeVars

// ---------------------------------------------------------------- reading

type private R =
    { r: BinaryReader
      objs: ResizeArray<obj>
      strs: ResizeArray<string>
      place: obj -> int * int * int -> unit }

let private rint (c: R) = c.r.ReadInt32()
let private rbool (c: R) = c.r.ReadBoolean()
let private rtag (c: R) = int (c.r.ReadByte())

let private rstr (c: R) =
    let i = c.r.ReadInt32()

    if i < c.strs.Count then
        c.strs[i]
    else
        let s = c.r.ReadString()
        c.strs.Add s
        s

let private rlist (c: R) (f: R -> 'a) : 'a list =
    let n = c.r.ReadInt32()
    List.init n (fun _ -> f c)

let private ropt (c: R) (f: R -> 'a) : 'a option = if c.r.ReadBoolean() then Some(f c) else None

let private rshared (c: R) (pos: bool) (body: unit -> 'a) : 'a =
    match c.r.ReadByte() with
    | 0uy -> c.objs[c.r.ReadInt32()] :?> 'a
    | _ ->
        let x = body ()

        if pos && c.r.ReadBoolean() then
            let l = c.r.ReadInt32()
            let col = c.r.ReadInt32()
            let n = c.r.ReadInt32()
            c.place (box x) (l, col, n)

        c.objs.Add(box x)
        x

let rec private rty (c: R) : Ty =
    rshared c false (fun () ->
        match rtag c with
        | 0 ->
            let n = rstr c
            TCon(n, rlist c rty)
        | 1 ->
            let a = rty c
            TFun(a, rty c)
        | 2 -> TTuple(rlist c rty)
        | 3 -> TVar(rcell c)
        | 4 -> TGen(rint c)
        | _ ->
            let us = rlist c (fun c -> (let u = rstr c in u, rint c))
            TMeas(us, rlist c (fun c -> (let v = rty c in v, rint c))))

and private rcell (c: R) : TV ref =
    rshared c false (fun () ->
        match rtag c with
        | 0 ->
            let id = rint c
            ref (Unbound(id, rkind c))
        | _ -> ref (Link(rty c)))

and private rkind (c: R) : Kind =
    let allowed = ropt c (fun c -> Set.ofList (rlist c rstr))
    { allowed = allowed; traits = Set.ofList (rlist c rstr) }

let private rtyBinding (c: R) =
    let x = rstr c
    x, rty c

let rec private rstype (c: R) : SType =
    match rtag c with
    | 0 ->
        let n = rstr c
        STName(n, rlist c rstype)
    | 1 -> STVar(rstr c)
    | 2 -> STTuple(rlist c rstype)
    | 3 ->
        let a = rstype c
        STFun(a, rstype c)
    | _ ->
        STMeasure(
            rlist c (fun c ->
                let u = rstr c
                let isVar = rbool c
                u, isVar, rint c)
        )

let rec private rpat (c: R) : Pat =
    rshared c true (fun () ->
        match rtag c with
        | 0 -> PWild
        | 1 ->
            let x = rstr c
            PIdent(x, ropt c rpat)
        | 2 -> PInt(c.r.ReadInt64())
        | 3 -> PChar(rint c)
        | 4 -> PStr(rstr c)
        | 5 -> PBool(rbool c)
        | 6 -> PUnit
        | 7 -> PTuple(rlist c rpat)
        | 8 ->
            let a = rpat c
            POr(a, rpat c)
        | 9 ->
            let q = rpat c
            PAs(q, rstr c)
        | 10 -> PNamed(rlist c (fun c -> (let n = rstr c in n, rpat c)))
        | 11 -> PRecord(rlist c (fun c -> (let n = rstr c in n, rpat c)))
        | _ -> PArgs(rlist c rpat))

let rec private rexpr (c: R) : Expr =
    rshared c true (fun () ->
        match rtag c with
        | 0 -> Lit(c.r.ReadInt64())
        | 1 -> CharLit(rint c)
        | 2 -> FloatLit(c.r.ReadDouble())
        | 3 -> BoolLit(rbool c)
        | 4 -> StrLit(rstr c)
        | 5 -> UnitLit
        | 6 -> Var(rstr c)
        | 7 ->
            let f = rstr c
            Call(f, rlist c rexpr)
        | 8 ->
            let f = rexpr c
            App(f, rlist c rexpr)
        | 9 ->
            let ps = rlist c rparam
            Lambda(ps, rexpr c)
        | 10 ->
            let op = rstr c
            let a = rexpr c
            Bin(op, a, rexpr c)
        | 11 -> Neg(rexpr c)
        | 12 -> Not(rexpr c)
        | 13 ->
            let a = rexpr c
            let b = rexpr c
            If(a, b, ropt c rexpr)
        | 14 ->
            let p = rpat c
            let t = ropt c rstype
            let v = rexpr c
            Let(p, t, v, rexpr c)
        | 15 ->
            let n = rstr c
            let r = rbool c
            let ps = rlist c rparam
            let t = ropt c rstype
            let b = rexpr c
            LetFun(n, r, ps, t, b, rexpr c)
        | 16 ->
            let fs = rlist c rexpr
            LetRecGroup(fs, rexpr c)
        | 17 ->
            let x = rstr c
            let t = ropt c rstype
            let v = rexpr c
            LetMut(x, t, v, rexpr c)
        | 18 ->
            let a = rexpr c
            Assign(a, rexpr c)
        | 19 ->
            let a = rexpr c
            While(a, rexpr c)
        | 20 ->
            let x = rstr c
            let a = rexpr c
            let s = ropt c rexpr
            let b = rexpr c
            For(x, a, s, b, rexpr c)
        | 21 ->
            let x = rstr c
            let xs = rexpr c
            ForIn(x, xs, rexpr c)
        | 22 ->
            let a = rexpr c
            Seq(a, rexpr c)
        | 23 -> Tuple(rlist c rexpr)
        | 24 -> RecordLit(rlist c (fun c -> (let n = rstr c in n, rexpr c)))
        | 25 ->
            let r = rexpr c
            Update(r, rlist c (fun c -> (let n = rstr c in n, rexpr c)))
        | 26 ->
            let r = rexpr c
            Field(r, rstr c)
        | 27 ->
            let a = rexpr c
            Index(a, rexpr c)
        | 28 -> ArrayLit(rlist c rexpr)
        | 29 ->
            let s = rexpr c

            Match(
                s,
                rlist c (fun c ->
                    let p = rpat c
                    let g = ropt c rexpr
                    p, g, rexpr c)
            )
        | 30 -> Question(rexpr c)
        | 31 ->
            let p = rpat c
            let v = rexpr c
            TryBind(p, v, rexpr c)
        | 32 ->
            let s = rstr c
            DeriveCtx(s, rexpr c)
        | 33 ->
            let a = rexpr c
            Measured(a, rstype c)
        | 34 ->
            let a = rexpr c
            Typed(a, rstype c)
        | 36 -> Unsafe(rexpr c)
        | _ ->
            let l = rint c
            At(l, rexpr c))

and private rparam (c: R) : Param =
    let p = rpat c
    p, ropt c rstype

let rec private rcpat (c: R) : CPat =
    match rtag c with
    | 0 -> CPWild
    | 1 ->
        let x = rstr c
        CPVar(x, rty c)
    | 2 -> CPInt(c.r.ReadInt64())
    | 3 -> CPStr(rstr c)
    | 4 -> CPBool(rbool c)
    | 5 -> CPTuple(rlist c rcpat)
    | 6 ->
        let r = rstr c
        CPRecord(r, rlist c (fun c -> (let n = rstr c in n, rcpat c)))
    | 7 ->
        let u = rstr c
        let t = rint c
        CPCtor(u, t, rlist c rcpat)
    | 8 ->
        let a = rcpat c
        CPOr(a, rcpat c)
    | _ ->
        let q = rcpat c
        let x = rstr c
        CPAs(q, x, rty c)

let rec private rcexpr (c: R) : CExpr =
    rshared c false (fun () ->
        let t = rty c

        let k =
            match rtag c with
            | 0 -> CInt(c.r.ReadInt64())
            | 1 -> CFloat(c.r.ReadDouble())
            | 2 -> CBool(rbool c)
            | 3 -> CStr(rstr c)
            | 4 -> CUnit
            | 5 -> CLocal(rstr c)
            | 6 -> CGlobalVal(rstr c)
            | 7 ->
                let g = rstr c
                CGlobal(g, ropt c (fun c -> rlist c rty))
            | 8 ->
                let h = rcexpr c
                CApp(h, rlist c rcexpr)
            | 9 ->
                let ps = rlist c rtyBinding
                CLam(ps, rcexpr c)
            | 10 ->
                let n = rstr c
                let r = rbool c
                let ps = rlist c rtyBinding
                let b = rcexpr c
                CLetFun(n, r, ps, b, rcexpr c)
            | 11 ->
                let fs =
                    rlist c (fun c ->
                        let n = rstr c
                        let ps = rlist c rtyBinding
                        n, ps, rcexpr c)

                CLetRec(fs, rcexpr c)
            | 12 ->
                let n = rstr c
                CExtern(n, rlist c rcexpr)
            | 13 ->
                let n = rstr c
                CPrim(n, rlist c rcexpr)
            | 14 ->
                let op = rstr c
                let a = rcexpr c
                CBin(op, a, rcexpr c)
            | 15 -> CNeg(rcexpr c)
            | 16 -> CNot(rcexpr c)
            | 17 ->
                let a = rcexpr c
                let b = rcexpr c
                CIf(a, b, rcexpr c)
            | 18 ->
                let x = rstr c
                let v = rcexpr c
                CLet(x, v, rcexpr c)
            | 19 ->
                let a = rcexpr c
                CSeq(a, rcexpr c)
            | 20 -> CTuple(rlist c rcexpr)
            | 21 ->
                let r = rcexpr c
                CField(r, rint c)
            | 22 ->
                let u = rstr c
                let tag = rint c
                CCtor(u, tag, rlist c rcexpr)
            | 23 ->
                let s = rcexpr c

                CMatch(
                    s,
                    rlist c (fun c ->
                        let p = rcpat c
                        let g = ropt c rcexpr
                        p, g, rcexpr c)
                )
            | 24 ->
                let x = rstr c
                let v = rcexpr c
                CLetMut(x, v, rcexpr c)
            | 25 ->
                let x = rstr c
                CAssign(x, rcexpr c)
            | 26 ->
                let x = rstr c
                let i = rcexpr c
                CArraySet(x, i, rcexpr c)
            | 27 ->
                let a = rcexpr c
                CWhile(a, rcexpr c)
            | 28 ->
                let x = rstr c
                let a = rcexpr c
                let s = rcexpr c
                let b = rcexpr c
                CFor(x, a, s, b, rcexpr c)
            | _ ->
                let l = rint c
                CLine(l, rcexpr c)

        { k = k; ty = t })

let private rtypeDef (c: R) : TypeDef =
    match rtag c with
    | 0 -> RecordDef(rlist c rtyBinding)
    | _ -> UnionDef(rlist c (fun c -> (let n = rstr c in n, rlist c rty)))

let private rmemberParam (c: R) : MemberParam =
    let n = rstr c
    let t = ropt c rstype
    let o = rbool c

    { mname = n
      mty = t
      optional = o
      mdefault = ropt c rexpr }

let private rderiveDef (c: R) =
    let l = rint c
    let n = rstr c
    let ps = rlist c rparam
    let ret = ropt c rstype
    l, n, ps, ret, rexpr c

let private rdict (c: R) (d: Dictionary<'k, 'v>) (k: R -> 'k) (v: R -> 'v) =
    for _ in 1 .. c.r.ReadInt32() do
        let key = k c
        d[key] <- v c

    d

let private rinto (c: R) (add: 'a -> unit) (f: R -> 'a) =
    for _ in 1 .. c.r.ReadInt32() do
        add (f c)

let private rpair (c: R) =
    let a = rstr c
    a, rstr c

/// Reads a state write wrote; place o p: a syntax node's source position.
let read (input: Stream) (place: obj -> int * int * int -> unit) : State =
    use r = new BinaryReader(input, System.Text.Encoding.UTF8, true)

    let c =
        { r = r
          objs = ResizeArray()
          strs = ResizeArray()
          place = place }

    let set (h: HashSet<'a>) (f: R -> 'a) =
        rinto c (fun x -> h.Add x |> ignore) f
        h

    let resize (l: ResizeArray<'a>) (f: R -> 'a) =
        rinto c l.Add f
        l

    let optStr (c: R) = ropt c rstr
    let types = rdict c (Dictionary()) rstr (fun c -> (let n = rint c in { npars = n; def = rtypeDef c }))
    let ctors = rdict c (Dictionary()) rstr (fun c -> (let u = rstr c in u, rint c))
    let records = resize (ResizeArray()) rstr
    let recordDefaults = rdict c (Dictionary()) rstr (fun c -> rlist c (fun c -> ropt c rexpr))
    let ctorFieldNames = rdict c (Dictionary()) rstr (fun c -> rlist c optStr)

    let members =
        rdict c (Dictionary()) rstr (fun c ->
            rdict c (Dictionary()) rstr (fun c ->
                let g = rstr c
                let s = rbool c
                let p = rbool c

                { gname = g
                  isStatic = s
                  isProperty = p
                  mpars = rlist c rmemberParam }))

    let memberTypeNames = set (HashSet()) rstr

    let traitMethods =
        rdict c (Dictionary()) rstr (fun c ->
            let o = rstr c
            let n = rstr c
            let t = rty c

            { owner = o
              name = n
              ty = t
              isConst = rbool c })

    let traitAliases = rdict c (Dictionary()) rstr rstr
    let traitNames = set (HashSet()) rstr
    let impls = rdict c (Dictionary()) rpair (fun c -> rdict c (Dictionary()) rstr rstr)
    let implRequires = rdict c (Dictionary()) rpair (fun c -> rlist c (fun c -> Set.ofList (rlist c rstr)))
    let derives = rdict c (Dictionary()) rstr (fun c -> rlist c rderiveDef)
    let deriveModules = rdict c (Dictionary()) rstr optStr

    let activePatterns =
        rdict c (Dictionary()) rstr (fun c ->
            let f = rstr c
            let total = rbool c
            f, total, rint c)

    let apCtors = set (HashSet()) rstr
    let ownImpls = set (HashSet()) rpair
    let autoDerived = set (HashSet()) rpair
    let optOut = set (HashSet()) rpair

    let globals =
        rdict c (Dictionary()) rstr (fun c ->
            let t = rty c
            let ks = rlist c rkind
            let a = rint c

            { ty = t
              kinds = ks
              arity = a
              defining = rbool c })

    let externs =
        rdict c (Dictionary()) rstr (fun c ->
            let ps = rlist c rty
            let ret = rty c

            ({ pars = ps
               ret = ret
               variadic = rbool c }
            : ExternSig))

    let funs =
        resize (ResizeArray()) (fun c ->
            let n = rstr c
            let ps = rlist c rtyBinding
            let ret = rty c
            let body = rcexpr c
            let ngen = rint c
            let file = rstr c

            ({ name = n
               pars = ps
               ret = ret
               body = body
               ngen = ngen
               file = file
               line = rint c }
            : FunDef))

    let counter = ref (rint c)
    let measures = set (HashSet()) rstr
    let clayouts = set (HashSet()) rstr

    let exports =
        resize (ResizeArray()) (fun c ->
            let cn = rstr c
            let fn = rstr c
            let ps = rlist c rty

            ({ cname = cn
               fname = fn
               pars = ps
               ret = rty c }
            : Export))

    let tests = resize (ResizeArray()) rstr
    let consts = rdict c (Dictionary()) rstr rexpr
    let globalValues = rdict c (Dictionary()) rstr rty
    let valueList = resize (ResizeArray()) rpair
    let literalRecords = rdict c (Dictionary(HashIdentity.Reference)) rexpr rstr
    let privates = rdict c (Dictionary()) rstr optStr
    let moduleNames = set (HashSet()) rstr
    let mainNested = set (HashSet()) rstr
    let nestedModules = set (HashSet()) rstr
    let enclosingOf = rdict c (Dictionary()) rstr (fun c -> rlist c rstr)

    { types = types
      ctors = ctors
      records = records
      recordDefaults = recordDefaults
      ctorFieldNames = ctorFieldNames
      members = members
      memberTypeNames = memberTypeNames
      traitMethods = traitMethods
      traitAliases = traitAliases
      traitNames = traitNames
      impls = impls
      implRequires = implRequires
      derives = derives
      deriveModules = deriveModules
      activePatterns = activePatterns
      apCtors = apCtors
      ownImpls = ownImpls
      autoDerived = autoDerived
      optOut = optOut
      globals = globals
      externs = externs
      funs = funs
      counter = counter
      measures = measures
      clayouts = clayouts
      exports = exports
      tests = tests
      consts = consts
      globalValues = globalValues
      valueList = valueList
      literalRecords = literalRecords
      privates = privates
      moduleNames = moduleNames
      mainNested = mainNested
      nestedModules = nestedModules
      enclosingOf = enclosingOf
      typeVars = rint c }
