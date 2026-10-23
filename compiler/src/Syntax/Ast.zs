/// The AST: what the checker reads, the parser's view of the tree (0019). The parser makes it
/// as it makes the tree, in the F# compiler's shapes (`compiler/tests/ast.sh` compares the two).
/// A node's `at` is where it is, a token's index in the tree (-1 when it has no place of its own:
/// an error inside it is at the nearest node around it that has one, as in the F# compiler); a
/// field name's token is beside it, for rename and references.

/// A type as written.
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
type Param = { param: Pat; ann: option<SType> }

/// An expression, and its place.
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
