/// The AST as both compilers print it (`zs ast`), for comparing their parsers: a node a line, its
/// children two spaces deeper, a node with a place followed by @line:col.
open Ast

// a node's place, as " @line:col" (none: "")
let private place (src: Source.Source) (toks: array<Token.Token>) (at: int) : string =
  if at < 0 then
    ""
  else
    let (l, c) = Source.position src toks.[at].offset
    $" @{l}:{c}"

let private quote (s: string) : string =
  let parts = Buffer.empty
  Buffer.push "\"" parts
  let mutable i = 0
  while i < String.length s do
    let c = int (String.byte s i)
    if c = 92 then Buffer.push "\\\\" parts
    else if c = 34 then Buffer.push "\\\"" parts
    else if c = 10 then Buffer.push "\\n" parts
    else if c = 9 then Buffer.push "\\t" parts
    else if c = 13 then Buffer.push "\\r" parts
    else if c < 32 then Buffer.push $"\\u{{{c:X}}}" parts
    else Buffer.push (String.sub s i 1) parts
    i <- i + 1
  Buffer.push "\"" parts
  String.concat (Array.toList (Buffer.toArray parts))

let rec private ty (t: SType) : string =
  match t with
  | STName(n, []) -> n
  | STName(n, args) -> n + "<" + String.join ", " (List.map ty args) + ">"
  | STVar v -> "'" + v
  | STTuple ts -> "(" + String.join " * " (List.map ty ts) + ")"
  | STFun(a, b) -> "(" + ty a + " -> " + ty b + ")"
  | STMeasure us ->
    "[" + String.join " " (List.map (fun (u, v, e) -> (if v then "'" else "") + u + "^" + $"{e}") us) + "]"
  | STRow(t, ls, tail) ->
    let rest =
      match tail with
      | Some v -> " | '" + v
      | None -> ""
    "(" + ty t + " / <" + String.join ", " (List.map ty ls) + rest + ">)"

let private ann (t: option<SType>) : string =
  match t with
  | Some t -> ty t
  | None -> "-"

/// The dump's lines.
let dump (src: Source.Source) (toks: array<Token.Token>) (decls: list<Decl>) : list<string> =
  let out = Buffer.empty
  let at (i: int) = place src toks i
  let lineOf (i: int) = if i < 0 then 0 else fst (Source.position src toks.[i].offset)
  let rec pat (p: Pat) : string =
    match p.pat with
    | PWild -> "_"
    | PIdent(x, None) -> x + at p.patAt
    | PIdent(x, Some q) -> "(" + x + " " + pat q + ")" + at p.patAt
    | PInt n -> $"{n}"
    | PChar c -> $"#{c}"
    | PStr s -> quote s
    | PBool b -> if b then "true" else "false"
    | PUnit -> "()"
    | PTuple ps -> "(tuple " + String.join " " (List.map pat ps) + ")"
    | POr(a, b) -> "(or " + pat a + " " + pat b + ")"
    | PAs(q, x) -> "(as " + pat q + " " + x + ")"
    | PNamed fs -> "(named " + String.join " " (List.map (fun (f, q) -> f + "=" + pat q) fs) + ")"
    | PRecord fs ->
      "(record " + String.join " " (List.map (fun (f, _, q) -> f + "=" + pat q) fs) + ")"
    | PArgs ps -> "(args " + String.join " " (List.map pat ps) + ")"
  let param (q: Param) = "param " + pat q.param + " : " + ann q.ann
  let line (d: int) (s: string) = Buffer.push (String.repeat (2 * d) " " + s) out
  let rec expr (d: int) (e: Expr) : unit =
    let kids (xs: list<Expr>) =
      for x in xs do
        expr (d + 1) x
    let opt (x: option<Expr>) =
      match x with
      | Some x -> expr (d + 1) x
      | None -> line (d + 1) "None"
    match e.e with
    | Lit n -> line d $"Lit {n}"
    | CharLit c -> line d $"CharLit {c}"
    | FloatLit f -> line d $"FloatLit {Float.toBits f:X16}"
    | BoolLit b -> line d (if b then "BoolLit true" else "BoolLit false")
    | StrLit s -> line d ("StrLit " + quote s)
    | UnitLit -> line d "UnitLit"
    | Var x -> line d ("Var " + x + at e.at)
    | Call(f, args) ->
      line d ("Call " + f + at e.at)
      kids args
    | App(h, args) ->
      line d ("App" + at e.at)
      kids (h :: args)
    | Lambda(ps, b) ->
      line d "Lambda"
      for q in ps do
        line (d + 1) (param q)
      expr (d + 1) b
    | Bin(op, a, b) ->
      line d ("Bin " + op)
      kids [ a; b ]
    | Neg a ->
      line d "Neg"
      kids [ a ]
    | Not a ->
      line d "Not"
      kids [ a ]
    | If(c, t, f) ->
      line d "If"
      kids [ c; t ]
      opt f
    | Let(q, t, v, r) ->
      line d ("Let " + pat q + " : " + ann t)
      kids [ v; r ]
    | LetFun(f, isRec, ps, ret, b, r) ->
      line d ("LetFun " + f + " rec=" + (if isRec then "true" else "false") + at e.at)
      for q in ps do
        line (d + 1) (param q)
      line (d + 1) ("ret " + ann ret)
      kids [ b; r ]
    | LetRecGroup(ms, r) ->
      line d "LetRecGroup"
      kids (List.append ms [ r ])
    | LetMut(x, t, v, r) ->
      line d ("LetMut " + x + " : " + ann t)
      kids [ v; r ]
    | Assign(a, b) ->
      line d ("Assign" + at e.at)
      kids [ a; b ]
    | While(c, b) ->
      line d "While"
      kids [ c; b ]
    | For(x, a, step, b, body) ->
      line d ("For " + x)
      expr (d + 1) a
      opt step
      kids [ b; body ]
    | ForIn(x, a, b) ->
      line d ("ForIn " + x)
      kids [ a; b ]
    | Seq(a, b) ->
      line d "Seq"
      kids [ a; b ]
    | Tuple xs ->
      line d "Tuple"
      kids xs
    | RecordLit fs ->
      line d "RecordLit"
      for f in fs do
        line (d + 1) ("field " + f.field)
        expr (d + 2) f.value
    | Update(r, fs) ->
      line d "Update"
      expr (d + 1) r
      for f in fs do
        line (d + 1) ("field " + f.field)
        expr (d + 2) f.value
    | Field(r, f) ->
      line d ("Field " + f + at e.at)
      kids [ r ]
    | Index(a, i) ->
      line d "Index"
      kids [ a; i ]
    | Slice(a, i, j) ->
      line d "Slice"
      expr (d + 1) a
      opt i
      opt j
    | ArrayLit xs ->
      line d "ArrayLit"
      kids xs
    | Match(sc, cs) ->
      line d "Match"
      expr (d + 1) sc
      for c in cs do
        line (d + 1) ("clause " + pat c.pattern)
        match c.guard with
        | Some g -> expr (d + 2) g
        | None -> line (d + 2) "None"
        expr (d + 2) c.body
    | Question a ->
      line d ("Question" + at e.at)
      kids [ a ]
    | TryBind(q, a, r) ->
      line d ("TryBind " + pat q + at e.at)
      kids [ a; r ]
    | Measured(a, t) ->
      line d ("Measured " + ty t)
      kids [ a ]
    | Typed(a, t) ->
      line d ("Typed " + ty t)
      kids [ a ]
    | Unsafe a ->
      line d "Unsafe"
      kids [ a ]
    | ListComp(isArray, b) ->
      line d ("ListComp array=" + (if isArray then "true" else "false"))
      kids [ b ]
    | Yield a ->
      line d "Yield"
      kids [ a ]
    | YieldAll a ->
      line d "YieldAll"
      kids [ a ]
    | Handle(b, ops, ret) ->
      line d "Handle"
      expr (d + 1) b
      for op in ops do
        line (d + 1) ("op " + op.op + " " + op.k + " " + String.join " " (List.map pat op.args) + at op.opAt)
        expr (d + 2) op.opBody
      match ret with
      | Some(q, body) ->
        line (d + 1) ("return " + pat q)
        expr (d + 2) body
      | None -> line (d + 1) "noreturn"
    | At a ->
      line d ($"At {lineOf e.at}" + at e.at)
      kids [ a ]
    | AtLine a ->
      line d $"At {lineOf e.at}"
      kids [ a ]
  let members (d: int) (ms: list<Member>) =
    for m in ms do
      let self =
        match m.self with
        | Some s -> s
        | None -> "-"
      line d ("member " + m.memberName + " static=" + (if m.isStatic then "true" else "false") + " self=" + self + " ret=" + ann m.mret + $" @{lineOf m.mat}")
      match m.mpars with
      | Some ps ->
        for q in ps do
          line (d + 1) ("param " + (if q.optional then "?" else "") + q.mname + " : " + ann q.mty)
          match q.mdefault with
          | Some v -> expr (d + 2) v
          | None -> ()
      | None -> line (d + 1) "property"
      expr (d + 1) m.mbody
  let tps (vs: list<string>) = String.concat (List.map (fun v -> " '" + v) vs)
  let rec decl (d: int) (x: Decl) : unit =
    let head (s: string) = line d ($"{lineOf x.dat}: " + s)
    let defs (ds: list<Definition>) =
      for def in ds do
        line (d + 1) ("def " + def.dname + $" @{lineOf def.defAt}")
        for q in def.dpars do
          line (d + 2) (param q)
        line (d + 2) ("ret " + ann def.dret)
        expr (d + 2) def.dbody
    // a function's or a value's name's place
    let named (inner: Decl) = at inner.named
    match x.d with
    | Extern(n, args, variadic, ret) ->
      head ("Extern " + n + " variadic=" + (if variadic then "true" else "false") + " : " + String.join " -> " (List.map ty args) + " -> " + ty ret)
    | Fun(n, isRec, ps, ret, body) ->
      head ("Fun " + n + " rec=" + (if isRec then "true" else "false") + named x)
      for q in ps do
        line (d + 1) (param q)
      line (d + 1) ("ret " + ann ret)
      expr (d + 1) body
    | Value(n, t, v) ->
      head ("Value " + n + " : " + ann t + named x)
      expr (d + 1) v
    | FunGroup items ->
      head "FunGroup"
      for m in items do
        decl (d + 1) m
    | TypeGroup items ->
      head "TypeGroup"
      for m in items do
        decl (d + 1) m
    | TypeDecl(n, vs, body, ms) ->
      head ("TypeDecl " + n + tps vs)
      match body with
      | RecordTy fs ->
        line (d + 1) "record"
        for f in fs do
          line (d + 2) ("field " + f.name + " : " + ty f.ty)
          match f.default with
          | Some v -> expr (d + 3) v
          | None -> ()
      | UnionTy cs ->
        line (d + 1) "union"
        let field (f: option<string> * SType) =
          match f with
          | (Some n, t) -> " " + n + ":" + ty t
          | (None, t) -> " _:" + ty t
        for c in cs do
          line (d + 2) ("case " + c.case + String.concat (List.map field c.fields))
      members (d + 1) ms
    | TypeExt(n, vs, ms) ->
      head ("TypeExt " + n + tps vs)
      members (d + 1) ms
    | TypeAlias(n, vs, t) -> head ("TypeAlias " + n + tps vs + " = " + ty t)
    | Trait(n, vs, ms) ->
      head ("Trait " + n + tps vs)
      for (m, t) in ms do
        line (d + 1) ("method " + m + " : " + ty t)
    | Effect(n, vs, ops) ->
      head ("Effect " + n + tps vs)
      for (m, oi, t) in ops do
        line (d + 1) ("op " + m + " : " + ty t + at oi)
    | Derive(n, ds) ->
      head ("Derive " + n)
      defs ds
    | DeriveGroup(n, ms) -> head ("DeriveGroup " + n + " " + String.join " " ms)
    | Attrs(attrs, inner) ->
      head "Attrs"
      for (a, args) in attrs do
        line (d + 1) ("attr " + a + String.concat (List.map (fun x -> " " + quote x) args))
      decl (d + 1) { inner with dat = x.dat }
    | Private inner ->
      head "Private"
      decl (d + 1) { inner with dat = x.dat }
    | Open m -> head ("Open " + m)
    | ModuleHeader m -> head ("ModuleHeader " + m)
    | NestedModule(n, ds) ->
      head ("NestedModule " + n)
      for m in ds do
        decl (d + 1) m
    | Impl(tr, h, others, ds) ->
      head ("Impl " + tr + " " + ty h + String.concat (List.map (fun t -> " " + ty t) others))
      defs ds
    | ImportC h -> head ("ImportC " + quote h)
    | Const(n, v) ->
      head ("Const " + n)
      expr (d + 1) v
  for x in decls do
    decl 0 x
  Array.toList (Buffer.toArray out)
