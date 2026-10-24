/// Types (DESIGN §3) as plain values: a type variable is a number, and what it's bound to is in
/// the checker's context (`Vars`), so a type is Share and crosses threads as data (decision 78).
/// What this module has needs no variable's binding: the types, the kinds, the built-in names.

/// A type.
[<Derive(Binary)>]
type Ty =
  /// int, f64, string, list<_>, user types; a number's argument is its unit of measure
  | TCon of string * list<Ty>
  /// a function: its parameter, its result, and what calling it performs (its row, DESIGN §6.1)
  | TFun of Ty * Ty * Ty
  | TTuple of list<Ty>
  /// a type variable: its number in the checker's context
  | TVar of int
  /// a type scheme's or a type definition's i-th variable
  | TGen of int
  /// a unit of measure: base units and measure variables (TVar or TGen), with exponents; only a
  /// number type's argument: f64<m/s> is TCon("f64", [ TMeas … ])
  | TMeas of list<string * int> * list<Ty * int>

/// What a type variable may become: one of `allowed` (a literal's: None is anything) that
/// implements every trait in `traits`; a trait's other parameters (Iter<int>'s int), which the
/// impl for the type determines (0017).
[<Derive(Binary)>]
type Kind = { allowed: option<Set<string>>; traits: Set<string>; params: Map<string, list<Ty>> }

/// What a type definition is (field types mention TGen, the type's parameters).
[<Derive(Binary)>]
type TypeDef =
  | RecordDef of list<string * Ty>
  | UnionDef of list<string * list<Ty>>

[<Derive(Binary)>]
type TypeInfo = { npars: int; def: TypeDef }

// ------------------------------------------------------------ names

let private setOf (xs: list<string>) : Set<string> = Set.ofList xs

/// int and usize are the machine word (64 bits, or 32 on a 32-bit chip); i64 and u64 always 64.
let ints : Set<string> = setOf [ "int"; "i8"; "i16"; "i32"; "i64"; "u8"; "u16"; "u32"; "u64"; "usize" ]

let unsigned : Set<string> = setOf [ "u8"; "u16"; "u32"; "u64"; "usize" ]

let floats : Set<string> = setOf [ "f64"; "f32" ]

let nums : Set<string> = Set.union ints floats

/// SIMD vectors (DESIGN §8): 128-, 256- and 512-bit vectors of each number type (f32x4, f64x4,
/// i8x32, …): name, element type, lanes.
let vectorTypes : list<string * string * int> =
  [ for (e, bits) in [ ("f32", 32); ("f64", 64); ("i8", 8); ("i16", 16); ("i32", 32); ("i64", 64); ("u8", 8); ("u16", 16); ("u32", 32); ("u64", 64) ] do
      for width in [ 128; 256; 512 ] do
        yield ($"{e}x{width / bits}", e, width / bits) ]

/// The target intrinsics on SIMD vectors (DESIGN §8): the function, the LLVM intrinsic, the
/// parameter types, the result type, and the CPU feature it needs ("" for the baseline).
let simdIntrinsics : list<string * string * list<string> * string * string> =
  [ ("Simd.X86.rsqrt4", "llvm.x86.sse.rsqrt.ps", [ "f32x4" ], "f32x4", "")
    ("Simd.X86.rsqrt8", "llvm.x86.avx.rsqrt.ps.256", [ "f32x8" ], "f32x8", "avx")
    ("Simd.X86.rcp4", "llvm.x86.sse.rcp.ps", [ "f32x4" ], "f32x4", "")
    ("Simd.X86.rcp8", "llvm.x86.avx.rcp.ps.256", [ "f32x8" ], "f32x8", "avx")
    ("Simd.X86.hadd4", "llvm.x86.sse3.hadd.ps", [ "f32x4"; "f32x4" ], "f32x4", "sse3")
    ("Simd.X86.hadd8", "llvm.x86.avx.hadd.ps.256", [ "f32x8"; "f32x8" ], "f32x8", "avx")
    ("Simd.X86.movemask4", "llvm.x86.sse.movmsk.ps", [ "f32x4" ], "i32", "")
    ("Simd.X86.movemask8", "llvm.x86.avx.movmsk.ps.256", [ "f32x8" ], "i32", "avx")
    ("Simd.X86.movemaskBytes16", "llvm.x86.sse2.pmovmskb.128", [ "i8x16" ], "i32", "")
    ("Simd.X86.movemaskBytes32", "llvm.x86.avx2.pmovmskb", [ "i8x32" ], "i32", "avx2")
    ("Simd.X86.shuffleBytes16", "llvm.x86.ssse3.pshuf.b.128", [ "i8x16"; "i8x16" ], "i8x16", "ssse3")
    ("Simd.X86.shuffleBytes32", "llvm.x86.avx2.pshuf.b", [ "i8x32"; "i8x32" ], "i8x32", "avx2")
    ("Simd.X86.maddPairs8", "llvm.x86.sse2.pmadd.wd", [ "i16x8"; "i16x8" ], "i32x4", "")
    ("Simd.X86.maddPairs16", "llvm.x86.avx2.pmadd.wd", [ "i16x16"; "i16x16" ], "i32x8", "avx2")
    ("Simd.X86.sadBytes16", "llvm.x86.sse2.psad.bw", [ "u8x16"; "u8x16" ], "u64x2", "")
    ("Simd.X86.sadBytes32", "llvm.x86.avx2.psad.bw", [ "u8x32"; "u8x32" ], "u64x4", "avx2")
    ("Simd.Arm.rsqrtEstimate4", "llvm.aarch64.neon.frsqrte.v4f32", [ "f32x4" ], "f32x4", "")
    ("Simd.Arm.recipEstimate4", "llvm.aarch64.neon.frecpe.v4f32", [ "f32x4" ], "f32x4", "")
    ("Simd.Arm.pairwiseAdd4", "llvm.aarch64.neon.faddp.v4f32", [ "f32x4"; "f32x4" ], "f32x4", "")
    ("Simd.Arm.tableLookup16", "llvm.aarch64.neon.tbl1.v16i8", [ "i8x16"; "i8x16" ], "i8x16", "")
    ("Simd.Arm.dotBytes16", "llvm.aarch64.neon.sdot.v4i32.v16i8", [ "i32x4"; "i8x16"; "i8x16" ], "i32x4", "dotprod") ]

/// Masks, what comparing two vectors lane by lane gives: mask2 … mask64.
let maskTypes : list<string * int> = List.map (fun k -> ($"mask{k}", k)) [ 2; 4; 8; 16; 32; 64 ]

let isVectorName (n: string) : bool = List.exists (fun (v, _, _) -> v = n) vectorTypes

let isMaskName (n: string) : bool = List.exists (fun (m, _) -> m = n) maskTypes

let simdNames : Set<string> = Set.ofList (List.append (List.map (fun (n, _, _) -> n) vectorTypes) (List.map fst maskTypes))

/// The module of a SIMD type's functions: F32x4 for f32x4, Mask4 for mask4.
let simdModule (n: string) : string =
  let c = int (String.byte n 0)
  String.ofByte (u8 (if c >= 97 && c <= 122 then c - 32 else c)) + String.sub n 1 (String.length n - 1)

/// The primitive types; cptr is any other C pointer, opaque.
let prims : Set<string> = Set.union (Set.union nums simdNames) (setOf [ "bool"; "char"; "string"; "cstr"; "cptr"; "unit" ])

// ------------------------------------------------------------ kinds

let kAny : Kind = { allowed = None; traits = Set.empty; params = Map.empty }

let private allow (s: Set<string>) : Kind = { allowed = Some s; traits = Set.empty; params = Map.empty }

let kInt : Kind = allow ints

let kFloat : Kind = allow floats

let kNumeric : Kind = allow nums

/// What the conversion functions (int, u8, …) take.
let kConvertible : Kind = allow (Set.add "char" nums)

/// What `char` converts from.
let kIntOrChar : Kind = allow (Set.add "char" ints)

let kStrLit : Kind = allow (setOf [ "string"; "cstr" ])

let kTrait (t: string) : Kind = { allowed = None; traits = setOf [ t ]; params = Map.empty }

let private vectors : Set<string> = Set.ofList (List.map (fun (n, _, _) -> n) vectorTypes)

let private addImpls : Set<string> = Set.add "string" (Set.union nums vectors)

let private numImpls : Set<string> = Set.union nums vectors

let private eqImpls : Set<string> = Set.union (Set.union nums simdNames) (setOf [ "string"; "bool"; "char"; "unit" ])

let private ordImpls : Set<string> = Set.union nums (setOf [ "string"; "char" ])

let private showImpls : Set<string> = Set.union (Set.union nums simdNames) (setOf [ "string"; "bool"; "char" ])

let private scalarImpls : Set<string> = Set.union nums (setOf [ "string"; "bool"; "char" ])

/// The built-in impls of the prelude's operator traits for primitive types.
let builtinImpls (tr: string) : Set<string> =
  match tr with
  | "Add" -> addImpls
  | "Num" -> numImpls
  | "Eq" -> eqImpls
  | "Ord" -> ordImpls
  | "Show" -> showImpls
  | "Diff" -> scalarImpls
  | "Format" -> nums
  | "Hash" -> scalarImpls
  | "Share" -> eqImpls
  | _ -> Set.empty

let hasBuiltinImpl (tr: string) (n: string) : bool = Set.contains n (builtinImpls tr)

/// The name a tuple size's impls are kept under (impl Binary<'a * 'b>: *2).
let tupleHead (n: int) : string = $"*{n}"

/// What a span<T> is after monomorphization: a window into an array's storage (or a string's
/// bytes, C memory, a Buffer's), a value of three words.
let windowType = "$window"

/// What a Buffer<T> is after monomorphization: a ref to a window with room.
let bufferType = "$buffer"

/// The built-in generic type constructors' arities: array<T> a copy-on-write value, Buffer<T>
/// a shared mutable window, span<T> a read-only window, weak<T>, share<F> a function that may
/// cross threads, Atomic, Mutex and Channel what threads share; for C, callback<F>, ptr<T> and
/// fnptr<F>.
let builtinCons (n: string) : option<int> =
  match n with
  | "array"
  | "Buffer"
  | "span"
  | "ref"
  | "weak"
  | "share"
  | "Atomic"
  | "Mutex"
  | "Channel"
  | "callback"
  | "ptr"
  | "fnptr" -> Some 1
  | "fixed" -> Some 2
  | _ -> None

/// The types whose values are references to one object each, as `ref` is.
let isCellType (n: string) : bool = n = "ref" || n = "Atomic" || n = "Mutex" || n = "Channel"

/// `dyn Trait`: a value of any type implementing the trait; its type is named dyn:<the trait>.
let isDynName (n: string) : bool = String.startsWith "dyn:" n

/// C's and F#'s names for types that are other types.
let typeAlias (n: string) : option<string> =
  match n with
  | "c_int" -> Some "i32"
  | "float"
  | "double" -> Some "f64"
  | _ -> None

// ------------------------------------------------------------ types and rows

let tcon (n: string) : Ty = TCon(n, [])

let tInt : Ty = tcon "int"

let tBool : Ty = tcon "bool"

let tUnit : Ty = tcon "unit"

let tStr : Ty = tcon "string"

let tCStr : Ty = tcon "cstr"

let tChar : Ty = tcon "char"

let tCPtr : Ty = tcon "cptr"

/// Effect rows (Leijen's scoped labels): empty, an effect's label in front of another row, or a
/// variable (of kind kRow; TGen once generalized). Labels keep their order, and an effect may be
/// in a row twice: the first is the innermost handler's.
let rowEmpty : Ty = TCon("$total", [])

let rowExt (label: Ty) (rest: Ty) : Ty = TCon("$ext", [ label; rest ])

let kRow : Kind = { allowed = Some(setOf [ "$total" ]); traits = Set.empty; params = Map.empty }

let isRowKind (k: Kind) : bool = k.allowed = kRow.allowed

let mkRow (labels: list<Ty>) (tail: Ty) : Ty = List.fold (fun acc l -> rowExt l acc) tail (List.rev labels)

/// A function type with no effects.
let tfun (a: Ty) (b: Ty) : Ty = TFun(a, b, rowEmpty)

let measOne : Ty = TMeas([], [])

/// The library's namespaces, open in every module at the lowest precedence: `List.map` is
/// Collections.List.map and `File.exists` IO.File.exists, unless the program defines its own.
let autoOpens : list<string> = [ "Collections"; "Text"; "IO"; "Diagnostics"; "Threading"; "Net"; "Time" ]

/// A name as programs write it: without an auto-opened namespace (Collections.Map: Map).
let shortName (q: string) : string =
  match List.tryFind (fun ns -> String.startsWith (ns + ".") q) autoOpens with
  | Some ns -> String.sub q (String.length ns + 1) (String.length q - String.length ns - 1)
  | None -> q

/// windowType's record: its owner, a pointer to its first element, and its length.
let windowDef : TypeInfo =
  { npars = 1
    def = RecordDef [ ("$owner", TCon("array", [ TGen 0 ])); ("$data", TCon("ptr", [ TGen 0 ])); ("$length", tInt) ] }

/// A Buffer's record after monomorphization: a window with room (its owner's length is how many
/// elements hold a value).
let bufferDef : TypeInfo =
  { npars = 1
    def = RecordDef [ ("$owner", TCon("array", [ TGen 0 ])); ("$data", TCon("ptr", [ TGen 0 ])); ("$length", tInt); ("$capacity", tInt) ] }

/// x86-64's SIMD features, each implying those before it.
let x86Levels : list<string> = [ "sse"; "sse2"; "sse3"; "ssse3"; "sse4.1"; "sse4.2"; "avx"; "avx2" ]

/// What --cpu's x86-64 microarchitecture levels have, by the levels' definitions.
let x86CpuFeatures : Map<string, list<string>> =
  Map.ofList [ ("x86-64", [ "sse2" ])
               ("x86-64-v2", [ "sse4.2"; "popcnt" ])
               ("x86-64-v3", [ "avx2"; "fma"; "bmi"; "bmi2"; "f16c" ])
               ("x86-64-v4", [ "avx2"; "fma"; "bmi"; "bmi2"; "f16c"; "avx512f"; "avx512bw"; "avx512cd"; "avx512dq"; "avx512vl" ]) ]

/// Whether these features (with what each implies) include the one needed.
let featuresInclude (have: list<string>) (need: string) : bool =
  let levelOf (f: string) = List.tryFindIndex (fun l -> l = f) x86Levels
  let implies (i: int) (h: string) =
    match levelOf h with
    | Some j -> j >= i
    | None -> (h = "fma" && i <= 6) || String.startsWith "avx512" h
  let impliedByLevel =
    match levelOf need with
    | Some i -> List.exists (implies i) have
    | None -> false
  need = "" || List.contains need have || impliedByLevel

/// A SIMD vector type's element type and lanes.
let vectorInfo (n: string) : option<string * int> =
  match List.tryFind (fun (m, _, _) -> m = n) vectorTypes with
  | Some(_, e, k) -> Some(e, k)
  | None -> None
