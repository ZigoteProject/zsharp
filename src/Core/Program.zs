/// A checked program as the passes after checking take it (the F# compiler's Core.Program): its
/// types and functions with every type settled (no type variable bound in the checker's context:
/// those still free take their defaults), and what each pass needs of the declarations.
open Types.Ty
open Ir

/// A checked program.
type Program =
  { types: Map<string, TypeInfo>
    externs: Map<string, ExternSig>
    funs: list<FunDef>
    /// "Show.show": the method
    traitMethods: Map<string, TraitMethod>
    /// by full name
    effects: Map<string, EffectInfo>
    /// (trait, type): method to function
    impls: Map<string * string, Map<string, string>>
    exports: list<Export>
    /// top-level values computed at startup, in order: name, init function
    values: list<string * string>
    /// the main file's test entry ($tests, from its [<Tests>] values), if it has any
    tests: list<string>
    /// [<CLayout>] records
    clayouts: Set<string>
    /// [<Target "avx2,fma">] functions: "target" and the features; [<Multiversion("avx2",
    /// "sse4.2")>] ones: "multiversion" and a version's features each
    targets: Map<string, list<string>>
    /// type: its members (completion)
    memberNames: Map<string, list<string>> }

/// What a pass after checking can't go on from: a message and where (the file, "" for the main
/// one, and a line, 0 for none). Rare: most of what's wrong is the checker's to find.
type PassError = { file: string; line: int; message: string }

/// A pass stopping at what it can't go on from.
effect Stops =
  /// Stops with an error.
  abstract stop : PassError -> 'a

/// Stops with a message, at no place (the driver puts it at the main file).
let stop (message: string) : 'a / Stops = Stops.stop { file = ""; line = 0; message = message }

/// A function after monomorphization (the F# compiler's Mono.MFun): its parameters, result and
/// row (what the body performs: the last parameter's arrow's; empty after Evidence), its body, and
/// where it's defined (debug info).
type MFun = { name: string; pars: list<string * Ty>; ret: Ty; row: Ty; body: CExpr; file: string; line: int }
