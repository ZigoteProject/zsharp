/// Types and the typed Core IR shared by every pass after parsing.
module Core

open System.Collections.Generic

// ---------------------------------------------------------------- types

/// What a type variable may become: one of `allowed` (literals; None = anything) that
/// implements every trait in `traits`.
type Kind =
    { allowed: Set<string> option
      traits: Set<string>
      /// a trait's other parameters (Iter<int>'s int), which the impl for the type determines (0017)
      params: Map<string, Ty list> }

and Ty =
    | TCon of string * Ty list // int, f64, string, list<_>, user types; args can later carry units of measure
    /// A function: parameter, result, and the effects calling it performs (its row, DESIGN §6.1).
    | TFun of Ty * Ty * Ty
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

/// SIMD vectors (DESIGN §8): 128-, 256- and 512-bit vectors of each number type (f32x4, f64x4,
/// i8x32, u16x8, …), LLVM's <n x T>: name, element type, lanes. Masks (what comparing two
/// vectors lane by lane gives) are mask2 … mask64, <n x i1>.
let vectorTypes =
    [ for e, bits in [ "f32", 32; "f64", 64; "i8", 8; "i16", 16; "i32", 32; "i64", 64; "u8", 8; "u16", 16; "u32", 32; "u64", 64 ] do
          for width in [ 128; 256; 512 ] do
              sprintf "%sx%d" e (width / bits), e, width / bits ]

let vectorInfo = vectorTypes |> List.map (fun (n, e, k) -> n, (e, k)) |> dict
let maskTypes = [ 2; 4; 8; 16; 32; 64 ] |> List.map (fun k -> sprintf "mask%d" k, k)
let maskLanes = dict maskTypes
let isVectorName (n: string) = vectorInfo.ContainsKey n
let isMaskName (n: string) = maskLanes.ContainsKey n
let simdNames = set (List.map (fun (n, _, _) -> n) vectorTypes @ List.map fst maskTypes)

/// Target intrinsics (DESIGN §8): Simd.X86's and Simd.Arm's functions, each an LLVM intrinsic
/// for one architecture: name, the intrinsic, parameter types, result type, and the CPU feature
/// it needs ("": every x86-64, which has SSE2, or every aarch64, which has NEON).
let simdIntrinsics =
    [ "Simd.X86.rsqrt4", "llvm.x86.sse.rsqrt.ps", [ "f32x4" ], "f32x4", ""
      "Simd.X86.rsqrt8", "llvm.x86.avx.rsqrt.ps.256", [ "f32x8" ], "f32x8", "avx"
      "Simd.X86.rcp4", "llvm.x86.sse.rcp.ps", [ "f32x4" ], "f32x4", ""
      "Simd.X86.rcp8", "llvm.x86.avx.rcp.ps.256", [ "f32x8" ], "f32x8", "avx"
      "Simd.X86.hadd4", "llvm.x86.sse3.hadd.ps", [ "f32x4"; "f32x4" ], "f32x4", "sse3"
      "Simd.X86.hadd8", "llvm.x86.avx.hadd.ps.256", [ "f32x8"; "f32x8" ], "f32x8", "avx"
      "Simd.X86.movemask4", "llvm.x86.sse.movmsk.ps", [ "f32x4" ], "i32", ""
      "Simd.X86.movemask8", "llvm.x86.avx.movmsk.ps.256", [ "f32x8" ], "i32", "avx"
      "Simd.X86.movemaskBytes16", "llvm.x86.sse2.pmovmskb.128", [ "i8x16" ], "i32", ""
      "Simd.X86.movemaskBytes32", "llvm.x86.avx2.pmovmskb", [ "i8x32" ], "i32", "avx2"
      "Simd.X86.shuffleBytes16", "llvm.x86.ssse3.pshuf.b.128", [ "i8x16"; "i8x16" ], "i8x16", "ssse3"
      "Simd.X86.shuffleBytes32", "llvm.x86.avx2.pshuf.b", [ "i8x32"; "i8x32" ], "i8x32", "avx2"
      "Simd.X86.maddPairs8", "llvm.x86.sse2.pmadd.wd", [ "i16x8"; "i16x8" ], "i32x4", ""
      "Simd.X86.maddPairs16", "llvm.x86.avx2.pmadd.wd", [ "i16x16"; "i16x16" ], "i32x8", "avx2"
      "Simd.X86.sadBytes16", "llvm.x86.sse2.psad.bw", [ "u8x16"; "u8x16" ], "u64x2", ""
      "Simd.X86.sadBytes32", "llvm.x86.avx2.psad.bw", [ "u8x32"; "u8x32" ], "u64x4", "avx2"
      "Simd.Arm.rsqrtEstimate4", "llvm.aarch64.neon.frsqrte.v4f32", [ "f32x4" ], "f32x4", ""
      "Simd.Arm.recipEstimate4", "llvm.aarch64.neon.frecpe.v4f32", [ "f32x4" ], "f32x4", ""
      "Simd.Arm.pairwiseAdd4", "llvm.aarch64.neon.faddp.v4f32", [ "f32x4"; "f32x4" ], "f32x4", ""
      "Simd.Arm.tableLookup16", "llvm.aarch64.neon.tbl1.v16i8", [ "i8x16"; "i8x16" ], "i8x16", ""
      "Simd.Arm.dotBytes16", "llvm.aarch64.neon.sdot.v4i32.v16i8", [ "i32x4"; "i8x16"; "i8x16" ], "i32x4", "dotprod" ]

/// x86-64's SIMD features, each implying those before it.
let x86Levels = [ "sse"; "sse2"; "sse3"; "ssse3"; "sse4.1"; "sse4.2"; "avx"; "avx2" ]

/// What --cpu's x86-64 microarchitecture levels have, by the levels' definitions.
let x86CpuFeatures =
    dict
        [ "x86-64", [ "sse2" ]
          "x86-64-v2", [ "sse4.2"; "popcnt" ]
          "x86-64-v3", [ "avx2"; "fma"; "bmi"; "bmi2"; "f16c" ]
          "x86-64-v4", [ "avx2"; "fma"; "bmi"; "bmi2"; "f16c"; "avx512f"; "avx512bw"; "avx512cd"; "avx512dq"; "avx512vl" ] ]

/// Whether these features (with what each implies) include the one needed.
let featuresInclude (have: string list) (need: string) =
    need = ""
    || List.contains need have
    || (match List.tryFindIndex ((=) need) x86Levels with
        | Some i -> have |> List.exists (fun h -> match List.tryFindIndex ((=) h) x86Levels with
                                                  | Some j -> j >= i
                                                  | None -> h = "fma" && i <= 6 || h.StartsWith "avx512")
        | None -> false)

/// The module of a SIMD type's functions: F32x4 for f32x4, Mask4 for mask4.
let simdModule (n: string) = string (System.Char.ToUpper n[0]) + n.Substring 1

let prims = nums + simdNames + set [ "bool"; "char"; "string"; "cstr"; "cptr"; "unit" ] // cptr: any other C pointer, opaque
let kAny = { allowed = None; traits = Set.empty; params = Map.empty }
let private allow s = { allowed = Some s; traits = Set.empty; params = Map.empty }
let kInt, kFloat, kNumeric = allow ints, allow floats, allow nums
let kConvertible = allow (nums.Add "char") // what the conversion functions (int, u8, …) take
let kIntOrChar = allow (ints.Add "char") // what `char` converts from
let kStrLit = allow (set [ "string"; "cstr" ])
let kTrait (t: string) = { allowed = None; traits = set [ t ]; params = Map.empty }

/// Built-in impls of the prelude's operator traits for primitive types.
let builtinImpls =
    let vectors = set (List.map (fun (n, _, _) -> n) vectorTypes)

    dict
        [ "Add", nums + vectors |> Set.add "string"
          "Num", nums + vectors
          "Eq", nums + simdNames + set [ "string"; "bool"; "char"; "unit" ]
          "Ord", nums + set [ "string"; "char" ]
          "Show", nums + simdNames + set [ "string"; "bool"; "char" ]
          "Format", nums
          "Hash", nums + set [ "string"; "bool"; "char" ]
          "Share", nums + simdNames + set [ "string"; "bool"; "char"; "unit" ] ]

let hasBuiltinImpl (tr: string) (n: string) =
    match builtinImpls.TryGetValue tr with
    | true, s -> s.Contains n
    | _ -> false

/// What a span<T> is after monomorphization: a window into an array's storage (or a string's
/// bytes, or C memory for a span from Span.ofPtr, or a Buffer's), as a value of three words.
/// The owner keeps the storage alive; data points at the first element; it's only read.
let windowType = "$window"

/// Built-in generic type constructors and their arity.
// array<T>: a copy-on-write value; Buffer<T>: a window into such storage, shared and mutable;
// span<T>: a read-only window into an array, a string's bytes or a Buffer (both windowType);
// weak<T>: a reference that doesn't keep its target alive; share<F>: a function that may cross
// threads (what it captures is Share); Atomic<T>, Mutex<T>, Channel<T>: values threads share;
// FFI only: callback<F> (a closure called by C), ptr<T> (a raw C pointer), fnptr<F> (a C
// function pointer)
let builtinCons =
    dict
        [ "array", 1
          "Buffer", 1
          "span", 1
          "fixed", 2
          "ref", 1
          "weak", 1
          "share", 1
          "Atomic", 1
          "Mutex", 1
          "Channel", 1
          "callback", 1
          "ptr", 1
          "fnptr", 1 ]

/// The types whose values are references to one object each, as `ref` is.
let isCellType (n: string) = n = "ref" || n = "Atomic" || n = "Mutex" || n = "Channel"

/// `dyn Trait`: a value of any type implementing the trait, behind a pointer to it and the
/// impl's methods. Its type is named dyn:<the trait's full name>.
let isDynName (n: string) = n.StartsWith "dyn:"

let typeAliases = dict [ "c_int", "i32"; "float", "f64"; "double", "f64" ]

// ---------------------------------------------------------------- effect rows

/// Effect rows (Leijen's scoped labels): what calling a function performs. A row is empty, an
/// effect (a label: the effect's type, Yield<int>) in front of another row, or a variable (a
/// TVar of kind kRow, TGen once generalized). Labels keep their order, and an effect may be in
/// a row twice: the first is the innermost handler's.
let rowEmpty = TCon("$total", [])
let rowExt (label: Ty) (rest: Ty) = TCon("$ext", [ label; rest ])
let kRow = { allowed = Some(set [ "$total" ]); traits = Set.empty; params = Map.empty }
let isRowKind (k: Kind) = k.allowed = kRow.allowed
let mkRow (labels: Ty list) (tail: Ty) = List.foldBack rowExt labels tail

let tcon n = TCon(n, [])
let tInt, tBool, tUnit, tStr, tCStr = tcon "int", tcon "bool", tcon "unit", tcon "string", tcon "cstr"
let tChar = tcon "char"
let tCPtr = tcon "cptr"

let mutable private nextVar = 0

/// Numbers type variables from 0 again: each module's are its own (they're told apart by
/// their cells; the number is for showing one).
let resetTypeVars () = nextVar <- 0

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

/// A row's labels, in order, and its tail: the empty row, or a variable.
let rec rowParts (r: Ty) : Ty list * Ty =
    match prune r with
    | TCon("$ext", [ l; rest ]) ->
        let ls, t = rowParts rest
        l :: ls, t
    | t -> [], t

/// An effect label's name: Yield for Yield<int>.
let labelName (l: Ty) =
    match prune l with
    | TCon(n, _) -> n
    | _ -> ""

let isRowEmpty (r: Ty) =
    match rowParts r with
    | [], t -> (match prune t with
                | TCon("$total", []) -> true
                | _ -> false)
    | _ -> false

/// A function type with no effects.
let tfun (a: Ty) (b: Ty) = TFun(a, b, rowEmpty)

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
let autoOpens = [ "Collections"; "Text"; "IO"; "Diagnostics"; "Threading"; "Net"; "Time" ]

/// A name as programs write it: without an auto-opened namespace (Collections.Map -> Map).
let shortName (q: string) =
    match autoOpens |> List.tryFind (fun ns -> q.StartsWith(ns + ".")) with
    | Some ns -> q.Substring(ns.Length + 1)
    | None -> q

/// The type variables of a type, each as often as it occurs.
let rec private varsIn (t: Ty) : Ty list =
    match prune t with
    | TVar _
    | TGen _ as v -> [ v ]
    | TCon(_, ts)
    | TTuple ts -> List.collect varsIn ts
    | TFun(a, b, r) -> varsIn a @ varsIn b @ varsIn r
    | TMeas(_, vs) -> vs |> List.collect (fst >> varsIn)

let private sameVar (a: Ty) (b: Ty) =
    match prune a, prune b with
    | TVar x, TVar y -> obj.ReferenceEquals(x, y)
    | TGen i, TGen j -> i = j
    | _ -> false

/// A function type's last arrow's row (`a -> b -> c / R`: R), if the type is a function.
let rec lastRow (t: Ty) : Ty option =
    match prune t with
    | TFun(_, b, r) ->
        match prune b with
        | TFun _ -> lastRow b
        | _ -> Some r
    | _ -> None

/// The rows in ambient places (0025): a function type's last arrow, and the last arrows of the
/// function types in argument position, at any depth.
let rec private ambientRows (t: Ty) : Ty list =
    match prune t with
    | TFun(a, b, r) ->
        let arg =
            match prune a with
            | TFun _ -> ambientRows a
            | _ -> []

        arg
        @ (match prune b with
           | TFun _ -> ambientRows b
           | _ -> [ r ])
    | _ -> []

/// A type as text. With full, names keep their namespaces (for symbol names and lookup keys,
/// which must tell a program's own Map from Collections.Map) and every row shows; without, they
/// read as written. A function's effects follow its result (`int -> unit / Yield<int>`); one
/// without any shows none. The function's ambient row (its last arrow's row variable) isn't
/// shown where it only connects the function arguments to the function, as their last arrows'
/// rows (`List.iter : ('a -> unit) -> list<'a> -> unit`); an argument that must perform nothing
/// shows `/ <>` (0025).
let rec showWith (full: bool) t =
    // what naming and hiding row variables needs, found once one is shown
    let vars = lazy (varsIn t)
    let rowVars = ResizeArray<Ty>()

    let ambient =
        lazy
            (if full then
                 None
             else
                 match lastRow t |> Option.map (rowParts >> snd >> prune) with
                 | Some(TVar _ | TGen _ as v) ->
                     let all = vars.Force() |> List.filter (sameVar v) |> List.length
                     let placed = ambientRows t |> List.filter (fun r -> sameVar (snd (rowParts r)) v) |> List.length
                     if all = placed then Some v else None
                 | _ -> None)

    let hidden (v: Ty) = ambient.Force() |> Option.exists (sameVar v)

    let rec findRows (t: Ty) =
        match prune t with
        | TFun(a, b, r) ->
            findRows a
            findRows b

            match prune (snd (rowParts r)) with
            | TVar _
            | TGen _ as v when not (rowVars.Exists(fun w -> sameVar v w)) && not (hidden v) -> rowVars.Add v
            | _ -> ()

            fst (rowParts r) |> List.iter findRows
        | TCon(_, ts)
        | TTuple ts -> List.iter findRows ts
        | _ -> ()

    let found = lazy (findRows t)

    let rowVarName (v: Ty) =
        found.Force()

        match rowVars.FindIndex(fun w -> sameVar v w) with
        | 0 -> "'e"
        | i -> sprintf "'e%d" (i + 1)

    // arg: the row of an argument's last arrow, which shows <> when empty
    let rec rowText (arg: bool) (r: Ty) =
        let ls, tail = rowParts r
        let labels = ls |> List.map (show false)

        let tailText =
            match prune tail with
            | TCon("$total", []) -> None
            | v when hidden v -> None
            | v -> Some(rowVarName v)

        match labels, tailText with
        | [], None when arg && not full && isRowEmpty r -> "<>"
        | [], None -> ""
        | [ l ], None -> l
        | [], Some v -> v
        | ls, None -> "<" + String.concat ", " ls + ">"
        | ls, Some v -> "<" + String.concat ", " ls + " | " + v + ">"

    // arg: t is a function type in argument position
    and show (arg: bool) (t: Ty) =
        match prune t with
        | TFun(a, b, r) ->
            let last =
                match prune b with
                | TFun _ -> false
                | _ -> true

            let effects = rowText (arg && last) r

            let param =
                match prune a with
                | TFun _ -> "(" + show true a + ")"
                | _ -> show false a

            let result =
                match prune b with
                | TFun _ when effects <> "" -> "(" + show arg b + ")"
                | TFun _ -> show arg b
                | _ -> show false b

            param + " -> " + result + (if effects = "" then "" else " / " + effects)
        | TCon(("$ext" | "$total"), _) as r -> "<" + rowText false r + ">"
        | TVar r when isRowKind (match r.Value with
                                 | Unbound(_, k) -> k
                                 | _ -> kAny) -> rowVarName t
        | t -> showOne full (show false) t

    show false t

/// One type constructor's text, its parts through show.
and private showOne (full: bool) (show: Ty -> string) (t: Ty) =
    match t with
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
    | TCon(n, []) when isDynName n && not full -> "dyn " + shortName (n.Substring 4)
    | TCon(n, args) ->
        let n = if full then n else shortName n
        if args.IsEmpty then n else n + "<" + (args |> List.map show |> String.concat ", ") + ">"
    | TFun _ -> show t
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

/// A function type's effects in words, for hover and zs doc (0025): what it handles from each
/// function argument (the labels of the argument's row beyond its own, in order), which arguments
/// must perform nothing, and what it performs; "" when no argument's row says anything. `names`
/// are the parameters' names, as the definition has them.
let explain (names: string list) (t: Ty) : string =
    let labelsOf (r: Ty) = fst (rowParts r) |> List.map show

    let rec spine (t: Ty) =
        match prune t with
        | TFun(a, b, _) -> a :: spine b
        | _ -> []

    let own = lastRow t |> Option.map labelsOf |> Option.defaultValue []

    // the multiset difference, in xs's order
    let rec beyond (xs: string list) (ys: string list) =
        match xs with
        | [] -> []
        | x :: rest when List.contains x ys ->
            let i = List.findIndex ((=) x) ys
            beyond rest (List.removeAt i ys)
        | x :: rest -> x :: beyond rest ys

    let args =
        spine t
        |> List.mapi (fun i a ->
            let name = List.tryItem i names |> Option.defaultValue "the argument"

            match lastRow a with
            | Some r when isRowEmpty r -> [], [ name + " must perform nothing" ]
            | Some r ->
                match beyond (labelsOf r) own with
                | [] -> [], []
                | ls -> [ sprintf "handles %s from %s" (String.concat ", " ls) name ], []
            | None -> [], [])

    let handles = args |> List.collect fst
    let pureArgs = args |> List.collect snd

    if handles.IsEmpty && pureArgs.IsEmpty then ""
    else String.concat ", " (handles @ pureArgs @ (if own.IsEmpty then [] else [ "performs " + String.concat ", " own ]))

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
    | TFun(a, b, r) -> TFun(resolve a, resolve b, resolveRow r)
    | TTuple ts -> TTuple(List.map resolve ts)
    | TGen _ as t -> t
    | TMeas(us, vs) ->
        // an unconstrained measure variable is 1
        for v, _ in vs do
            match prune v with
            | TVar r -> r.Value <- Link measOne
            | _ -> ()

        TMeas(normMeas (TMeas(us, vs)))

/// A row resolved: an unconstrained tail is the empty row, and the labels are in canonical
/// order (by effect, the innermost first among one effect's: a stable sort), so equal rows are
/// equal types.
and resolveRow (r: Ty) =
    let ls, tail = rowParts r

    let tail =
        match prune tail with
        | TVar v ->
            v.Value <- Link rowEmpty
            rowEmpty
        | t -> t

    mkRow (ls |> List.map resolve |> List.sortBy labelName) tail

/// Replaces TGen i with args[i].
let rec substGen (args: Ty list) t =
    match prune t with
    | TGen i -> List.item i args
    | TMeas(us, vs) -> TMeas(normMeas (TMeas(us, vs |> List.map (fun (v, e) -> substGen args v, e))))
    | TCon(n, a) -> TCon(n, List.map (substGen args) a)
    | TFun(a, b, r) -> TFun(substGen args a, substGen args b, substGen args r)
    | TTuple ts -> TTuple(List.map (substGen args) ts)
    | t -> t

type TypeDef =
    | RecordDef of (string * Ty) list // field types may mention TGen (type parameters)
    | UnionDef of (string * Ty list) list

type TypeInfo = { npars: int; def: TypeDef }

/// windowType's record: its owner, a pointer to its first element, and its length.
let windowDef =
    { npars = 1
      def = RecordDef [ "$owner", TCon("array", [ TGen 0 ]); "$data", TCon("ptr", [ TGen 0 ]); "$length", TCon("int", []) ] }

/// What a Buffer<T> is after monomorphization: a ref to a window with room, so that every
/// reference to the Buffer sees it grow. The owner's own length is how many of its elements hold
/// a value (a slice of a Buffer is a cell of its own over the same storage, with no room, so
/// pushing on it copies first).
let bufferType = "$buffer"

let bufferDef =
    { npars = 1
      def =
        RecordDef
            [ "$owner", TCon("array", [ TGen 0 ])
              "$data", TCon("ptr", [ TGen 0 ])
              "$length", TCon("int", [])
              "$capacity", TCon("int", []) ] }

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
    /// An effect's operation (its label, Yield<int>; its index), performed with the arguments:
    /// what the innermost handler of the effect gives (DESIGN §6.1). Until Evidence.
    | CPerform of label: Ty * op: int * CExpr list
    /// handle body with clauses: for each operation (its index), its parameters, the
    /// resumption's name and type, and the clause's body; then the return clause, its variable
    /// bound to the body's result. Until Evidence.
    | CHandle of label: Ty * body: CExpr * clauses: (int * (string * Ty) list * (string * Ty) * CExpr) list * ret: (string * Ty) * retBody: CExpr
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
    | CPerform(l, op, args) -> CPerform(l, op, List.map f args)
    | CHandle(l, b, cls, r, rb) ->
        let b' = f b // the body runs first
        CHandle(l, b', cls |> List.map (fun (op, ps, k, c) -> op, ps, k, f c), r, f rb)
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
    | CHandle(_, _, cls, (r, _), _) -> r :: (cls |> List.collect (fun (_, ps, (k, _), _) -> k :: List.map fst ps))
    | _ -> []

/// The type of each local an expression refers to (a local function's at its uses: the
/// definition has its parameters' types only), by unique name.
let localTypesIn (e: CExpr) : Dictionary<string, Ty> =
    let d = Dictionary<string, Ty>()

    let rec walk (e: CExpr) =
        match e.k with
        | CLocal x -> d[x] <- e.ty
        | _ -> ()

        for c in children e.k do
            walk c

    walk e
    d

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
    | CPerform(l, op, xs) -> line (sprintf "perform %s#%d(%s)" (show l) op (args xs))
    | CHandle(l, b, cls, (r, _), rb) ->
        line ("handle " + show l)
        + "\n"
        + sub b
        + (cls
           |> List.map (fun (op, ps, (k, _), c) -> "\n" + line (sprintf "| #%d(%s), %s ->" op (ps |> List.map fst |> String.concat ", ") k) + "\n" + sub c)
           |> String.concat "")
        + "\n"
        + line ("| return " + r + " ->")
        + "\n"
        + sub rb
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
      /// What the body performs: the row of the last parameter's arrow (the others have none).
      row: Ty
      body: CExpr
      ngen: int // number of quantified variables (TGen 0..ngen-1)
      /// How many of them are effect rows: the last ones. Instantiated with empty rows, the
      /// function is its pure instance, under its own name (so its module owns it).
      rows: int
      file: string // where it is defined (debug info)
      line: int }

type ExternSig =
    { pars: Ty list
      ret: Ty
      variadic: bool }

/// An effect's operation: its parameter types and result, over the effect's type parameters
/// (TGen 0 … n-1) and its own (TGen n …, which appear in the result only: throw : 'e -> 'a).
type EffectOp =
    { name: string
      pars: Ty list
      ret: Ty
      own: int }

/// An effect (DESIGN §6.1): its number of type parameters and its operations, in order.
type EffectInfo = { npars: int; ops: EffectOp list }

type TraitMethod =
    { owner: string
      name: string
      ty: Ty // TGen 0 is the trait's first type parameter, the others follow (0017)
      nparams: int // the trait's type parameters; TGen nparams is the method's ambient row (0025)
      isConst: bool } // `abstract zero : 'a`: implemented as unit -> 'a

/// Whether a diagnostic stops the build (0021).
[<RequireQualifiedAccess>]
type Severity =
    | Error
    | Warning

type Program =
    { types: Dictionary<string, TypeInfo>
      externs: Dictionary<string, ExternSig>
      funs: FunDef list
      traitMethods: Dictionary<string, TraitMethod> // "Show.show" -> method
      effects: Dictionary<string, EffectInfo> // by full name
      impls: Dictionary<string * string, Dictionary<string, string>> // (trait, type) -> method -> function
      exports: Export list
      values: (string * string) list // top-level values computed at startup, in order: name, init function
      tests: string list // [<Test>] functions (unit -> unit), in source order
      clayouts: HashSet<string> // [<CLayout>] records
      /// [<Target "avx2,fma">] functions: "target" and the features; [<Multiversion("avx2",
      /// "sse4.2")>] ones: "multiversion" and a version's features each
      targets: Dictionary<string, string list>
      /// errors (every declaration's in collect mode, else the first) and warnings, in the order found
      diagnostics: Diagnostic list
      hovers: Hover list // inferred types at source positions (editor support)
      memberNames: Dictionary<string, string list> } // type -> its members (completion)

/// An error or a warning (0021): a warning has a name, the kind `[<NoWarn "…">]` silences, and
/// notes are the other places it's about.
and Diagnostic =
    { severity: Severity
      name: string // a warning's kind ("unused-value"); "" for an error
      file: string
      line: int
      col: int // 0 = unknown
      msg: string
      notes: Note list }

and Note =
    { nfile: string
      nline: int
      ncol: int
      ntext: string }

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
      explain: string // a top-level function's effects in words (Core.explain), "" if none
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

/// An error at a place (line 0: unknown; col 0: the line's start).
let errorAt (file: string) (line: int) (col: int) (msg: string) : Diagnostic =
    { severity = Severity.Error
      name = ""
      file = file
      line = line
      col = col
      msg = msg
      notes = [] }

let isError (d: Diagnostic) = d.severity = Severity.Error

/// The warning kinds (0021's table): the names `[<NoWarn "…">]` takes.
let warningKinds = [ "unused-value" ]

/// Does a value of this type hold a reference count (directly or in a field)?
/// Does a value of this type hold a reference count (directly or in a field)? `visiting`: the
/// unions being looked through, so a recursive union is found (and stays boxed).
let rec private heapIn (types: Dictionary<string, TypeInfo>) (visiting: Set<string>) t =
    match prune t with
    | TCon(("string" | "array" | "Buffer" | "span" | "weak"), _)
    | TFun _ -> true
    | TCon(n, _) when isCellType n -> true
    | TCon("share", [ f ]) -> heapIn types visiting f
    | TCon("fixed", [ el; _ ]) -> heapIn types visiting el
    | TCon(n, _) when isDynName n -> true
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

/// The function a monomorphized name comes from: f for f<int>, and for f$lam2 (a lambda in f).
let baseFunName (n: string) =
    let n = match n.IndexOf '$' with
            | -1 -> n
            | i -> n.Substring(0, i)

    match n.IndexOf '<' with
    | i when i > 0 -> n.Substring(0, i)
    | _ -> n

/// What keeps a type's values from being shared between threads (the Share trait, DESIGN §7):
/// None when they can be. Numbers, strings and the like, share<F> functions, the values threads
/// share (Atomic, Mutex, Channel), and records, unions, tuples and arrays of those can; ref,
/// Buffer, weak, dyn, C pointers and other functions can't. A type variable goes to onVar (the
/// type checker requires Share of it).
let rec shareBlocker (onVar: Ty -> unit) (types: Dictionary<string, TypeInfo>) (visiting: Set<string>) (t: Ty) : Ty option =
    let inner = shareBlocker onVar types

    match prune t with
    | TVar _ as v ->
        onVar v
        None
    | TCon(n, []) when hasBuiltinImpl "Share" n -> None
    | TCon("fixed", [ el; _ ]) -> inner visiting el
    | TCon(n, [ TMeas _ ]) when nums.Contains n -> None
    | TMeas _ -> None
    | TCon(("share" | "fnptr" | "Atomic"), _) -> None
    | TCon(("array" | "Mutex" | "Channel"), [ el ]) -> inner visiting el
    | TCon(n, args) as t when not (isDynName n) && not (builtinCons.ContainsKey n) ->
        let key = showFull t

        match types.TryGetValue n with
        | _ when visiting.Contains key -> None // recursive: Share if the rest of it is
        | true, { def = RecordDef fs } -> fs |> List.tryPick (fun (_, ft) -> inner (visiting.Add key) (substGen args ft))
        | true, { def = UnionDef cs } -> cs |> List.tryPick (fun (_, fs) -> fs |> List.tryPick (fun ft -> inner (visiting.Add key) (substGen args ft)))
        | _ -> Some t
    | TTuple ts -> List.tryPick (inner visiting) ts
    | t -> Some t

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
    let rec pointer (f: Ty) =
        match prune f with
        | TCon(("string" | "array" | "Buffer" | "weak"), _)
        | TFun _ -> true
        | TCon(n, _) when isCellType n -> true
        | TCon("share", [ f ]) -> pointer f
        | TCon(n, _) when isDynName n -> true
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
