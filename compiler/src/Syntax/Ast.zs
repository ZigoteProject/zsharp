/// The AST: what the checker reads, the parser's view of the tree (0019). The parser makes it
/// as it makes the tree, in the F# compiler's shapes (`compiler/tests/ast.sh` compares the two).
/// A node's `at` is where it is, a token's index in the tree (-1 when it has no place of its own:
/// an error inside it is at the nearest node around it that has one, as in the F# compiler); a
/// field name's token is beside it, for rename and references.

/// A type as written.
[<Derive(Binary)>]
type SType =
  | STName of string * list<SType>
  /// 'a (the name without its quote)
  | STVar of string
  | STTuple of list<SType>
  | STFun of SType * SType
  /// a unit or a measure variable (whether it is one), and its exponent: m/s^2
  | STMeasure of list<string * bool * int>
  /// a function's result with its effects: `T / E`, `T / <E, F | 'e>`: the labels, and the row
  /// variable it ends in
  | STRow of SType * list<SType> * option<string>

/// A pattern, and its place.
[<Derive(Binary)>]
type Pat = { pat: PatShape; patAt: int }

and PatShape =
  | PWild
  /// a variable, or a constructor with an optional payload
  | PIdent of string * option<Pat>
  | PInt of i64
  | PChar of int
  | PStr of string
  | PBool of bool
  | PUnit
  | PTuple of list<Pat>
  | POr of Pat * Pat
  | PAs of Pat * string
  /// a constructor's fields by name: Rect(h = h)
  | PNamed of list<string * Pat>
  /// { x = 0; y = y }: the fields left out match anything; each field's name token
  | PRecord of list<string * int * Pat>
  /// several atoms after a name: a parameterized active pattern's arguments
  | PArgs of list<Pat>

/// A parameter: its pattern, and its type when written.
[<Derive(Binary)>]
type Param = { param: Pat; ann: option<SType> }

/// An expression, and its place.
[<Derive(Binary)>]
type Expr = { e: ExprShape; at: int }

/// A field's value in a record literal or an update: its name, its name's token, its value.
and FieldValue = { field: string; nameAt: int; value: Expr }

/// A match's clause.
and Clause = { pattern: Pat; guard: option<Expr>; body: Expr }

/// A handler's clause for an operation: its qualified name, its arguments' patterns, the
/// resumption's name, the body.
and OpClause = { op: string; opAt: int; args: list<Pat>; k: string; opBody: Expr }

and ExprShape =
  | Lit of i64
  | CharLit of int
  | FloatLit of f64
  | BoolLit of bool
  | StrLit of string
  | UnitLit
  | Var of string
  /// a named function, constructor, builtin or extern applied to arguments
  | Call of string * list<Expr>
  /// any other expression applied to arguments
  | App of Expr * list<Expr>
  | Lambda of list<Param> * Expr
  | Bin of string * Expr * Expr
  | Neg of Expr
  | Not of Expr
  | If of Expr * Expr * option<Expr>
  | Let of Pat * option<SType> * Expr * Expr
  | LetFun of string * bool * list<Param> * option<SType> * Expr * Expr
  /// let rec f … and g …: the members are LetFun nodes (their rest unused), then the rest
  | LetRecGroup of list<Expr> * Expr
  | LetMut of string * option<SType> * Expr * Expr
  | Assign of Expr * Expr
  | While of Expr * Expr
  /// a range loop: the variable, from, step, to, body
  | For of string * Expr * option<Expr> * Expr * Expr
  /// for x in xs do body
  | ForIn of string * Expr * Expr
  | Seq of Expr * Expr
  | Tuple of list<Expr>
  | RecordLit of list<FieldValue>
  | Update of Expr * list<FieldValue>
  | Field of Expr * string
  | Index of Expr * Expr
  /// a.[i..j], a.[..j], a.[i..]
  | Slice of Expr * option<Expr> * option<Expr>
  | ArrayLit of list<Expr>
  | Match of Expr * list<Clause>
  /// e?, where a TryBind can be made of it
  | Question of Expr
  /// let p = e? and the rest, which runs only when e is Ok
  | TryBind of Pat * Expr * Expr
  /// 9.58<s>
  | Measured of Expr * SType
  /// (e: T)
  | Typed of Expr * SType
  /// unsafe e: raw pointers and C function pointers allowed inside
  | Unsafe of Expr
  /// [ for x in xs -> e ], [| … |]: its body yields
  | ListComp of bool * Expr
  /// yield e, in a list expression's body
  | Yield of Expr
  /// yield! xs: each of xs
  | YieldAll of Expr
  /// handle e with its operations' clauses and its return clause
  | Handle of Expr * list<OpClause> * option<Pat * Expr>
  /// what a derive's expansion checks (the checker makes it): an error inside says so, "field run: …"
  | DeriveCtx of string * Expr
  /// a statement: an error inside it with no place of its own is at its first token (`at`)
  | At of Expr
  /// what a computation expression or a list expression's `->` makes: an error inside it with
  /// no place of its own is on the line of `at`, with no column
  | AtLine of Expr

/// A field of a record type: its name, its name's token, its type and its default.
type RecordField = { name: string; fieldAt: int; ty: SType; default: option<Expr> }

/// A union's case: its name, and its fields (a field's name when it has one, its type).
type Case = { case: string; fields: list<option<string> * SType> }

/// What a type declaration declares.
type TypeBody =
  | RecordTy of list<RecordField>
  | UnionTy of list<Case>

/// A member's parameter: its name, its type, whether it's optional (?x) and its default.
[<Derive(Binary)>]
type MemberParam = { mname: string; mty: option<SType>; optional: bool; mdefault: option<Expr> }

/// A member of a type: `member v.Name`, `static member Name`, with parameters or a property.
type Member =
  { memberName: string
    isStatic: bool
    self: option<string>
    mpars: option<list<MemberParam>>
    mret: option<SType>
    mbody: Expr
    /// its first token
    mat: int }

/// A definition in a derive or an impl: its token, its name, its parameters, its result's type
/// and its body.
[<Derive(Binary)>]
type Definition = { defAt: int; dname: string; dpars: list<Param>; dret: option<SType>; dbody: Expr }

/// A declaration: its place (its first token) and, for a function's or a value's, its name's.
type Decl = { d: DeclShape; dat: int; named: int }

and DeclShape =
  | Extern of string * list<SType> * bool * SType
  | Fun of string * bool * list<Param> * option<SType> * Expr
  /// let rec f … and g …: Fun declarations (maybe Private) that may call each other
  | FunGroup of list<Decl>
  /// type A = … and B = …: records and unions (maybe Private) that may name each other
  | TypeGroup of list<Decl>
  | TypeDecl of string * list<string> * TypeBody * list<Member>
  /// type string with member …
  | TypeExt of string * list<string> * list<Member>
  /// type Duration = i64<ns>
  | TypeAlias of string * list<string> * SType
  /// trait Iter<'c, 'a> = …: the first parameter dispatches
  | Trait of string * list<string> * list<string * SType>
  /// effect E<'a> = abstract op : T -> R …
  | Effect of string * list<string> * list<string * int * SType>
  | Derive of string * list<Definition>
  /// derive Json = ToJson, FromJson
  | DeriveGroup of string * list<string>
  /// [<Derive(Json); NoEquality>]
  | Attrs of list<string * list<string>> * Decl
  | Private of Decl
  | Open of string
  /// module Name, or namespace Name: the file's first line
  | ModuleHeader of string
  /// module Name = and its declarations, indented
  | NestedModule of string * list<Decl>
  /// impl Iter<list<'a>, 'a> = …: the trait, the head, the trait's other parameters
  | Impl of string * SType * list<SType> * list<Definition>
  /// import c "raylib.h", replaced by the header's declarations
  | ImportC of string
  /// a C constant (an enum's value, a #define): its uses are the literal
  | Const of string * Expr
  /// let name = expr at the top level
  | Value of string * option<SType> * Expr

/// A node of each kind at a place.
let expr (shape: ExprShape) (at: int) : Expr = { e = shape; at = at }

let pat (shape: PatShape) (at: int) : Pat = { pat = shape; patAt = at }

let decl (shape: DeclShape) (at: int) : Decl = { d = shape; dat = at; named = -1 }

/// An expression with no place of its own.
let plain (shape: ExprShape) : Expr = { e = shape; at = -1 }

let plainPat (shape: PatShape) : Pat = { pat = shape; patAt = -1 }

/// The name a desugaring calls (`{x:F2}` calls Format.format, `a @ b` List.append): the library's,
/// whatever the program opens or defines.
let libraryName (name: string) : string = "global::" + name

/// The expression with f applied to each of its direct child expressions (its place kept).
let mapExpr (f: Expr -> Expr / 'e) (x: Expr) : Expr / 'e =
  let fields (fs: list<FieldValue>) = List.map (fun (v: FieldValue) -> { v with value = f v.value }) fs
  let shape =
    match x.e with
    | Lit _
    | CharLit _
    | FloatLit _
    | BoolLit _
    | StrLit _
    | UnitLit
    | Var _ -> x.e
    | Call(n, args) -> Call(n, List.map f args)
    | App(h, args) -> App(f h, List.map f args)
    | Lambda(ps, b) -> Lambda(ps, f b)
    | Bin(op, a, b) -> Bin(op, f a, f b)
    | Neg a -> Neg(f a)
    | Not a -> Not(f a)
    | If(c, t, e) -> If(f c, f t, Option.map f e)
    | Let(p, t, v, b) -> Let(p, t, f v, f b)
    | LetFun(n, r, ps, t, b, rest) -> LetFun(n, r, ps, t, f b, f rest)
    | LetRecGroup(fs, rest) -> LetRecGroup(List.map f fs, f rest)
    | LetMut(n, t, v, b) -> LetMut(n, t, f v, f b)
    | Assign(a, b) -> Assign(f a, f b)
    | While(c, b) -> While(f c, f b)
    | For(n, a, st, b, body) -> For(n, f a, Option.map f st, f b, f body)
    | ForIn(n, xs, b) -> ForIn(n, f xs, f b)
    | Seq(a, b) -> Seq(f a, f b)
    | Tuple xs -> Tuple(List.map f xs)
    | RecordLit fs -> RecordLit(fields fs)
    | Update(r, fs) -> Update(f r, fields fs)
    | Field(r, n) -> Field(f r, n)
    | Index(a, i) -> Index(f a, f i)
    | Slice(a, i, j) -> Slice(f a, Option.map f i, Option.map f j)
    | ArrayLit xs -> ArrayLit(List.map f xs)
    | Match(sc, cases) -> Match(f sc, List.map (fun (c: Clause) -> { c with guard = Option.map f c.guard; body = f c.body }) cases)
    | Question a -> Question(f a)
    | TryBind(p, a, b) -> TryBind(p, f a, f b)
    | DeriveCtx(c, a) -> DeriveCtx(c, f a)
    | Measured(a, m) -> Measured(f a, m)
    | Typed(a, t) -> Typed(f a, t)
    | Unsafe a -> Unsafe(f a)
    | ListComp(isArray, b) -> ListComp(isArray, f b)
    | Yield a -> Yield(f a)
    | YieldAll a -> YieldAll(f a)
    | Handle(b, cls, r) ->
      let ret =
        match r with
        | Some(p, c) -> Some(p, f c)
        | None -> None
      Handle(f b, List.map (fun (c: OpClause) -> { c with opBody = f c.opBody }) cls, ret)
    | At a -> At(f a)
    | AtLine a -> AtLine(f a)
  { x with e = shape }

/// The pattern with no places, its own or its parts' (one written elsewhere, used here).
let rec placelessPat (p: Pat) : Pat =
  let shape =
    match p.pat with
    | PIdent(x, Some q) -> PIdent(x, Some(placelessPat q))
    | PTuple ps -> PTuple(List.map placelessPat ps)
    | POr(a, b) -> POr(placelessPat a, placelessPat b)
    | PAs(q, x) -> PAs(placelessPat q, x)
    | PNamed fs -> PNamed(List.map (fun (n, q) -> (n, placelessPat q)) fs)
    | PRecord fs -> PRecord(List.map (fun (n, _, q) -> (n, -1, placelessPat q)) fs)
    | PArgs ps -> PArgs(List.map placelessPat ps)
    | other -> other
  { pat = shape; patAt = -1 }
