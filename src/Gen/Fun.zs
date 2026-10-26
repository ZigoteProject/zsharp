/// A function's code (the F# compiler's Codegen.genFunAs): its patterns, expressions, loops (with
/// versioning, and arrays kept unique across them), a task's waits, and every primitive.
open Types.Ty
open Types.Repr
open Core.Ir
open Core.Program
open Emit
open Layout
open Helpers
open Debug

/// A function being generated: the module's context, its emitter, the function, its debug scope
/// ("" without debug info), the line debug info is at and the latest statement line seen (the
/// return's location), the line of the statement being generated (for errors), the CPU features
/// its code is for, its prototype (to tell calls of its own shape), the join points being
/// generated (their block, and each jump's argument values and block), and the `let mutable`
/// arrays a loop keeps unique (made unique once before it; its writes skip the count check).
type F =
  | F of FData

and FData =
  { g: G
    em: Emitter
    f: MFun
    sp: string
    line: ref<int>
    lastLine: ref<int>
    at: ref<int>
    featureList: list<string>
    selfProto: string
    joinBlocks: ref<Map<string, string * Buffer<list<string> * string>>>
    uniqueSlots: ref<Set<string>> }

type F with
  member fx.g =
    match fx with
    | F { g = x } -> x
  member fx.em =
    match fx with
    | F { em = x } -> x
  member fx.f =
    match fx with
    | F { f = x } -> x
  member fx.sp =
    match fx with
    | F { sp = x } -> x
  member fx.line =
    match fx with
    | F { line = x } -> x
  member fx.lastLine =
    match fx with
    | F { lastLine = x } -> x
  member fx.at =
    match fx with
    | F { at = x } -> x
  member fx.featureList =
    match fx with
    | F { featureList = x } -> x
  member fx.selfProto =
    match fx with
    | F { selfProto = x } -> x
  member fx.joinBlocks =
    match fx with
    | F { joinBlocks = x } -> x
  member fx.uniqueSlots =
    match fx with
    | F { uniqueSlots = x } -> x

/// A function's prototype: its parameters' and result's LLVM types.
let proto (g: G) (f: MFun) : string = String.join ", " (List.map (fun (_, t) -> llty g t) f.pars) + " -> " + llty g f.ret

/// What the program can't be compiled for, at the statement being generated: the first is kept
/// (the build stops with it), and the code made after it isn't used.
let fail (fx: F) (msg: string) : string =
  match fx.g.failure.Value with
  | None -> fx.g.failure.Value <- Some(fx.at.Value, msg)
  | Some _ -> ()
  "poison"

// an argument as a call passes it: its LLVM type and value
let private typed (g: G) (av: CExpr * string) : string = llty g (fst av).ty + " " + snd av

let private isUnitTy (t: Ty) : bool =
  match t with
  | TCon("unit", []) -> true
  | _ -> false

// the types a task's state machine waits for (task.suspend's results; task.abandon's: unit)
let rec private waitsIn (e: CExpr) : list<Ty> =
  let own =
    match e.k with
    | CPrim("task.suspend", _) -> [ e.ty ]
    | CPrim("task.abandon", _) -> [ tUnit ]
    | _ -> []
  List.append own (List.collect waitsIn (children e.k))

let rec private irrefutable (p: CPat) : bool =
  match p with
  | CPWild
  | CPVar _ -> true
  | CPAs(q, _, _) -> irrefutable q
  | CPTuple ps -> List.forall irrefutable ps
  | CPRecord(_, fs) -> List.forall (fun (_, q) -> irrefutable q) fs
  | _ -> false

// only innermost loops without calls are versioned: that's where bounds checks cost, and
// duplicating an outer loop's body (with its inner loops) costs more code than it saves time; nor
// loops that call: the call costs more, and duplicating it blocks inlining
let rec private hasLoop (e: CExpr) : bool =
  match e.k with
  | CWhile _
  | CFor _
  | CCallDirect _
  | CApplyClo _ -> true
  | CLam _ -> false
  | k -> List.exists hasLoop (children k)

let rec private nodes (e: CExpr) : int = 1 + List.sumBy nodes (children e.k)

// a for loop's step that's a constant above 0 (as written: for x in a .. 8 .. b)
let rec private positiveStep (s: CExpr) : bool =
  match s.k with
  | CInt n -> n >= i64 1
  | CLine(_, s2) -> positiveStep s2
  | _ -> false

// a function type's parameters and result
let rec private splitFun (t: Ty) : list<Ty> * Ty =
  match t with
  | TFun(a, r, _) ->
    let (ps, res) = splitFun r
    (a :: ps, res)
  | r -> ([], r)

// an array literal of integer constants: its numbers
let rec private literalInts (c: CExpr) : option<list<i64>> =
  match c.k with
  | CLine(_, c2) -> literalInts c2
  | CPrim("array.lit", xs) ->
    if List.forall (fun (x: CExpr) -> match x.k with | CInt _ -> true | _ -> false) xs then Some(List.map (fun (x: CExpr) -> match x.k with | CInt n -> n | _ -> i64 0) xs) else None
  | _ -> None

// whether a C parameter of this type borrows what's passed for the call (a callback's closure, a
// span's owner)
let private borrowedByC (t: Ty) : bool =
  match t with
  | TCon("callback", _)
  | TCon("span", _) -> true
  | _ -> false

/// In a debug build, a variable gdb can show: v kept in a stack slot described by #dbg_declare
/// (or, with slot given, the existing slot).
let declareVar (fx: F) (x: string) (t: Ty) (v: string) (slot: option<string>) (arg: int) =
  let g = fx.g
  let em = fx.em
  if g.opts.debugInfo then
    match (sourceName x, diType g t) with
    | (Some name, Some dt) ->
      let loc = dbgOf em
      let p =
        match slot with
        | Some p -> p
        | None ->
          let p = "%dbg." + fresh em (String.replace name "." "_")
          alloca em $"{p} = alloca {llty g t}"
          // zero until the variable is bound, so gdb shows the same thing at every run for a
          // variable not bound yet (not the stack's leftovers)
          alloca em $"store {llty g t} zeroinitializer, ptr {p}"
          // a parameter's store has no line, as in C: it is prologue, so a breakpoint on the
          // function stops after it
          if arg > 0 then
            setDbg em ""
          emit em $"store {llty g t} {v}, ptr {p}"
          setDbg em loc
          p
      let argPart = if arg > 0 then $", arg: {arg}" else ""
      let var = meta g $"!DILocalVariable(name: \"{name}\"{argPart}, scope: {fx.sp}, file: {diFile g fx.f.file}, line: {max 1 fx.line.Value}, type: {dt})"
      match t with
      | TCon("string", []) ->
        // its value is the address of its bytes: the object's, past the count and length
        raw em $"#dbg_value(ptr {p}, {var}, !DIExpression(DW_OP_deref, DW_OP_plus_uconst, {2 * pointerBytes g}, DW_OP_stack_value), {loc})"
      | _ -> raw em $"#dbg_declare(ptr {p}, {var}, !DIExpression(), {loc})"
    | _ -> ()

/// Emits the test of pattern p against v (of type t); returns env extended with its bindings.
/// known: p's constructor is the only one v can have, so only its fields are tested.
let rec testIn (fx: F) (known: bool) (p: CPat) (t: Ty) (v: string) (failL: string) (env: Map<string, Binding>) : Map<string, Binding> =
  let g = fx.g
  let em = fx.em
  let test (q: CPat) (qt: Ty) (qv: string) (fl: string) (en: Map<string, Binding>) = testIn fx false q qt qv fl en
  let guardOr (cond: string) =
    let ok = fresh em "ok"
    emit em $"br i1 {cond}, label %{ok}, label %{failL}"
    enter em ok
  match p with
  | CPWild -> env
  | CPVar(x, _) -> Map.add x (Ssa v) env
  | CPAs(q, x, _) -> Map.add x (Ssa v) (test q t v failL env)
  | CPInt k ->
    guardOr (instr em $"icmp eq {llty g t} {v}, {k}")
    env
  | CPStr s ->
    let c = instr em $"call i_W @zs_str_cmp(ptr {v}, ptr {strGlobal g s})"
    guardOr (instr em $"icmp eq i_W {c}, 0")
    env
  | CPBool b ->
    guardOr (instr em $"icmp eq i1 {v}, {(if b then "true" else "false")}")
    env
  | CPTuple ps ->
    let ts =
      match t with
      | TTuple ts -> ts
      | _ -> panic "tuple pattern on non-tuple"
    let part (en: Map<string, Binding>) (ix: int * (CPat * Ty)) =
      let (i, (q, et)) = ix
      test q et (instr em $"extractvalue {llty g t} {v}, {i}") failL en
    List.fold part env (List.indexed (List.zip ps ts))
  | CPRecord(_, fs) ->
    // a record is a struct of its fields in declaration order, like a tuple
    let ts =
      match t with
      | TCon(n, args) ->
        match (Map.find n g.types).def with
        | RecordDef rfs -> List.map (fun (_, ft) -> substGen g args ft) rfs
        | UnionDef _ -> panic "record pattern on a union"
      | _ -> panic "record pattern on a non-record"
    let field (en: Map<string, Binding>) (ix: int * ((string * CPat) * Ty)) =
      let (i, ((_, q), ft)) = ix
      match q with
      | CPWild -> en
      | _ -> test q ft (instr em $"extractvalue {llty g t} {v}, {i}") failL en
    List.fold field env (List.indexed (List.zip fs ts))
  | CPCtor(_, tag, ps) when plainUnion g.v g.types t ->
    let cases = snd (union g t)
    let fields = snd (List.item tag cases)
    if not known then
      let tv = instr em $"extractvalue {llty g t} {v}, 0"
      guardOr (instr em $"icmp eq {tagTy cases} {tv}, {tag}")
    let field (en: Map<string, Binding>) (ix: int * (CPat * Ty)) =
      let (i, (q, ft)) = ix
      match q with
      | CPWild -> en
      | _ -> test q ft (instr em $"extractvalue {llty g t} {v}, {plainField g t tag i}") failL en
    List.fold field env (List.indexed (List.zip ps fields))
  | CPCtor(_, tag, ps) ->
    let cases = snd (union g t)
    let fields = snd (List.item tag cases)
    match (repOf g t, ps) with
    | (Niche(noneTag, _), _) when tag = noneTag ->
      if not known then
        guardOr (instr em $"icmp eq ptr {v}, @zs.none")
      env
    | (Niche(_, payload), [ q ]) ->
      // the value is the field
      if not known then
        guardOr (instr em $"icmp ne ptr {v}, @zs.none")
      test q payload v failL env
    | _ when List.isEmpty fields ->
      if not known then
        guardOr (instr em $"icmp eq ptr {v}, {nullary g t tag}")
      env
    | _ ->
      if not known then
        if not (tagged g t) then
          // the only case with fields: the value isn't one of the static cells
          for (k, (_, fs)) in List.indexed cases do
            if List.isEmpty fs then
              guardOr (instr em $"icmp ne ptr {v}, {nullary g t k}")
        else
          let tv = loadTag g em v (Some(List.length cases))
          guardOr (instr em $"icmp eq i32 {tv}, {tag}")
      let cell = cellTy g t tag
      let field (en: Map<string, Binding>) (ix: int * (CPat * Ty)) =
        let (i, (q, ft)) = ix
        match q with
        | CPWild -> en
        | _ ->
          let fp = instr em $"getelementptr {cell}, ptr {v}, i32 0, i32 {cellField g t i}"
          test q ft (instr em $"load {llty g ft}, ptr {fp}") failL en
      List.fold field env (List.indexed (List.zip ps fields))
  | CPOr(a, b) ->
    // both sides bind the same variables; merge them with phis
    let altL = fresh em "alt"
    let okL = fresh em "or"
    let vars = patVars a
    let envA = test a t v altL env
    let fromA = (List.map (fun (x, _) -> Map.find x envA) vars, current em)
    emit em $"br label %{okL}"
    enter em altL
    let envB = test b t v failL env
    let fromB = (List.map (fun (x, _) -> Map.find x envB) vars, current em)
    emit em $"br label %{okL}"
    enter em okL
    let ssa (bd: Binding) : string =
      match bd with
      | Ssa s -> s
      | Slot _ -> panic "pattern variable in a slot"
    let merge (en: Map<string, Binding>) (ix: int * (string * Ty)) =
      let (i, (x, xt)) = ix
      let va = ssa (List.item i (fst fromA))
      let vb = ssa (List.item i (fst fromB))
      Map.add x (Ssa(instr em $"phi {llty g xt} [ {va}, %{snd fromA} ], [ {vb}, %{snd fromB} ]")) en
    List.fold merge env (List.indexed vars)

let phi (fx: F) (ty: string) (incoming: list<string * string>) : string =
  instr fx.em ("phi " + ty + " " + String.join ", " (List.map (fun (v, b) -> $"[ {v}, %{b} ]") incoming))

/// The array reads of a for loop's body that versioning can prove in bounds: a.[i] and SIMD loads
/// from a (F32x8.load a i, which read lanes elements), where i is x plus or minus constants and
/// variables bound outside the loop (c - x too), with a and those variables not assigned in the
/// loop: the body with those reads marked unchecked (op!, for the version that has proved them),
/// and each one's array, coefficient of x, other terms with their signs, and lanes.
let affineReads (env: Map<string, Binding>) (x: string) (body: CExpr) : CExpr * list<CExpr * int * list<int * CExpr> * int> =
  let assigned = ref Set.empty
  let rec scan (e: CExpr) =
    match e.k with
    | CAssign(y, _) -> assigned.Value <- Set.add y assigned.Value
    | _ -> ()
    List.iter scan (children e.k)
  scan body
  let invariant (c: CExpr) : bool =
    match c.k with
    | CInt _ -> true
    | CLocal y -> y <> x && Map.containsKey y env && not (Set.contains y assigned.Value)
    | _ -> false
  // i as coef * x + the sum of the signed terms, each invariant; None if it isn't
  let rec linear (sign: int) (idx: CExpr) : option<int * list<int * CExpr>> =
    match idx.k with
    | CLocal y when y = x -> Some(sign, [])
    | _ when invariant idx -> Some(0, [ (sign, idx) ])
    | CBin(op, a, b) when op = "+" || op = "-" ->
      match (linear sign a, linear (if op = "+" then sign else -sign) b) with
      | (Some(ca, ta), Some(cb, tb)) -> Some(ca + cb, List.append ta tb)
      | _ -> None
    | CLine(_, e) -> linear sign e
    | _ -> None
  let affine (idx: CExpr) : option<int * list<int * CExpr>> =
    match linear 1 idx with
    | Some(coef, terms) -> if coef = 1 || coef = -1 then Some(coef, terms) else None
    | None -> None
  // an array the loop doesn't assign: a variable, or a field of one
  let rec stable (a: CExpr) : bool =
    match a.k with
    | CLocal arr -> arr <> x && Map.containsKey arr env && not (Set.contains arr assigned.Value)
    | CField(r, _) -> stable r
    | _ -> false
  let found = Buffer.empty
  let rec mark (e: CExpr) : CExpr =
    match e.k with
    | CPrim(op, [ a; idx ]) when (op = "array.get#b" || op = "vec.load#b") && stable a ->
      let lanes = if op = "vec.load#b" then snd (Option.get (vectorInfo (tyName e.ty))) else 1
      match affine idx with
      | Some(coef, terms) ->
        Buffer.push (a, coef, terms, lanes) found
        let idx2 = mark idx
        { e with k = CPrim(op + "!", [ a; idx2 ]) }
      | None -> { e with k = CPrim(op, [ a; mark idx ]) }
    // a closure body doesn't run in the loop
    | CLam _ -> e
    | k -> { e with k = mapChildren mark k }
  let marked = mark body
  (marked, Array.toList (Buffer.toArray found))

/// The `let mutable` arrays a loop writes and can keep unique for its whole run: inside it they
/// are only borrowed (a.[i], Array.length a) or written, never shared or reassigned. Each one's
/// name, slot and type, in the order the loop first writes them.
let loopUniques (fx: F) (env: Map<string, Binding>) (loop: CExpr) : list<string * string * Ty> =
  let written = ref Map.empty
  let order = Buffer.empty
  let shared = ref Set.empty
  let rec walk (e: CExpr) =
    match e.k with
    | CArraySet(x, i, v) ->
      if not (Map.containsKey x written.Value) then
        Buffer.push x order
      written.Value <- Map.add x (TCon("array", [ v.ty ])) written.Value
      walk i
      walk v
    | CPrim(op, { k = CLocal _ } :: rest) when String.endsWith "#b" op -> List.iter walk rest
    | CLocal x
    | CDup(x, _, _)
    | CDrop(x, _, _)
    | CAssign(x, _) ->
      shared.Value <- Set.add x shared.Value
      List.iter walk (children e.k)
    | _ -> List.iter walk (children e.k)
  walk loop
  let pick (x: string) : option<string * string * Ty> =
    match Map.tryFind x env with
    | Some(Slot p) -> if not (Set.contains x shared.Value) && not (Set.contains x fx.uniqueSlots.Value) then Some(x, p, Map.find x written.Value) else None
    | _ -> None
  List.choose pick (Array.toList (Buffer.toArray order))

/// A call of a C function (an extern, or a function pointer's value) with the values of the
/// arguments: strings as their bytes, closures for callback<F> parameters as callback and user
/// data, Z# objects as handles, structs by the C ABI's rules.
let cCall (fx: F) (callee: string) (s: ExternSig) (args: list<CExpr>) (vs: list<string>) : string =
  let g = fx.g
  let em = fx.em
  let (ret, sret) = cRet g s.ret
  let modes = cModes g s.pars sret
  // handles made for the call, released after it
  let handles = Buffer.empty
  let npars = List.length s.pars
  let pass (i: int) (av: CExpr * string) : string =
    let (a, v) = av
    match tyName a.ty with
    | "string" -> "ptr " + instr em $"getelementptr inbounds i8, ptr {v}, i_W HDR2"
    | _ when i < npars ->
      let pt = List.item i s.pars
      match pt with
      | TCon("callback", [ fn ]) ->
        match fn with
        | TCon("share", [ fg ]) ->
          // C may call it on any thread: what it captured is shared; the closure is the user data
          shareValue g em fg v
          $"ptr {thunk g fg true}, ptr {v}"
        | _ ->
          // the closure and this thread, which it may be called on only
          let user = "%" + fresh em "callback"
          alloca em $"{user} = alloca {{ ptr, i64 }}"
          emit em $"store ptr {v}, ptr {user}"
          let owner = instr em $"getelementptr {{ ptr, i64 }}, ptr {user}, i32 0, i32 1"
          emit em $"call void @zs_callback_owner(ptr {owner})"
          $"ptr {thunk g fn false}, ptr {user}"
      | TCon("unit", []) -> ""
      | TCon("span", _) ->
        // its data and its length; the owner is borrowed for the call
        let p1 = instr em $"extractvalue {llty g a.ty} {v}, 1"
        let p2 = instr em $"extractvalue {llty g a.ty} {v}, 2"
        $"ptr {p1}, i_W {p2}"
      | _ when isHandle g pt ->
        // the value's reference goes into a handle C borrows for the call
        let h = handleOf g em pt v
        Buffer.push h handles
        "ptr " + h
      | _ ->
        match List.item i modes with
        | Scalar -> $"{cParam g pt} {v}"
        | Pieces ps -> String.join ", " (List.map (fun (t, x) -> t + " " + x) (toPieces g em pt v ps))
        | Memory ->
          let slot = slotFor g em pt
          emit em $"store {llty g pt} {v}, ptr {slot}"
          $"{byval g pt} {slot}"
    // C default argument promotions for variadic arguments
    | "bool" -> "i32 " + instr em $"zext i1 {v} to i32"
    | "i8"
    | "i16" -> "i32 " + instr em $"sext {llty g a.ty} {v} to i32"
    | "u8"
    | "u16" -> "i32 " + instr em $"zext {llty g a.ty} {v} to i32"
    | "f32" -> "double " + instr em $"fpext float {v} to double"
    | n when Set.contains n prims && n <> "unit" -> $"{llty g a.ty} {v}"
    | _ -> fail fx $"a {showT g a.ty} cannot be passed to a C variadic function"
  let passed = List.filter (fun (x: string) -> x <> "") (List.mapi pass (List.zip args vs))
  let retSlot = if sret then Some(slotFor g em s.ret) else None
  let sretP =
    match retSlot with
    | Some p -> [ $"ptr sret({llty g s.ret}) {p}" ]
    | None -> []
  let argv = String.join ", " (List.append sretP passed)
  let fnTy =
    if s.variadic then
      let sretT = if sret then [ $"ptr sret({llty g s.ret})" ] else []
      ret + " (" + String.join ", " (List.concat [ sretT; cParamList g s.pars sret; [ "..." ] ]) + ")"
    else
      ret
  let call = $"call {fnTy} {callee}({argv})"
  let r =
    if ret = "void" then
      emit em call
      match retSlot with
      | Some p -> instr em $"load {llty g s.ret}, ptr {p}"
      | None -> "zeroinitializer"
    else
      let c = instr em call
      if isHandle g s.ret then
        // C gave a handle: the object, with a reference of its own; the handle goes
        let o = instr em $"call ptr @zs_handle_get(ptr {c})"
        emit em $"call void @zs_release(ptr {c})"
        o
      else
        match abiFor g s.ret true with
        | Scalar -> c
        | Pieces [ p ] -> fromPieces g em s.ret [ (p, c) ]
        | Pieces ps -> fromPieces g em s.ret (List.mapi (fun k p -> (p, instr em $"extractvalue {ret} {c}, {k}")) ps)
        | Memory -> panic "Codegen: a C result in memory comes through sret"
  for h in Buffer.toArray handles do
    emit em $"call void @zs_release(ptr {h})"
  let after (i: int) (av: CExpr * string) =
    let (a, v) = av
    // the string's bytes, the callback's closure, the span's owner were borrowed
    if tyName a.ty = "string" || (i < npars && borrowedByC (List.item i s.pars)) then
      dropValue g em a.ty v
  List.iteri after (List.zip args vs)
  r

/// A variable's value.
let lookup (fx: F) (env: Map<string, Binding>) (x: string) (t: Ty) : string =
  match Map.tryFind x env with
  | Some(Ssa v) -> v
  | Some(Slot p) -> instr fx.em $"load {llty fx.g t}, ptr {p}"
  | None -> panic $"Codegen: {x} isn't bound in {fx.f.name}"

// ------------------------------------------------------------ the primitives' parts

// an array type's element and its object's LLVM type
let private arrTy (g: G) (t: Ty) : Ty * string =
  match t with
  | TCon("array", [ el ]) -> (el, $"{{ i_W, i_W, [0 x {llty g el}] }}")
  | _ -> panic "not an array"

// a window's element (a span after monomorphization: Core's windowType, { owner, data, length })
let private winEl (g: G) (t: Ty) : Ty =
  match t with
  | TCon(_, [ el ]) -> el
  | _ -> panic $"window of {showT g t}"

let private part (g: G) (em: Emitter) (t: Ty) (v: string) (k: int) : string = instr em $"extractvalue {llty g t} {v}, {k}"

// a Buffer's element: a cell { header, { owner, data, length, capacity } }
let private bufEl (g: G) (t: Ty) : Ty =
  match t with
  | TCon("ref", [ TCon(_, [ el ]) ]) -> el
  | _ -> panic $"Buffer of {showT g t}"

let private bufField (em: Emitter) (c: string) (k: int) : string = instr em $"getelementptr {{ i_W, {{ ptr, ptr, i_W, i_W }} }}, ptr {c}, i32 0, i32 1, i32 {k}"

let private bufGet (em: Emitter) (c: string) (k: int) : string =
  let p = bufField em c k
  instr em $"load {(if k < 2 then "ptr" else "i_W")}, ptr {p}"

// a new Buffer's cell: owner, data, length, capacity (the owner's reference moves in)
let private newBuffer (em: Emitter) (owner: string) (data: string) (n: string) (cap: string) : string =
  let size = sizeOf em "{ i_W, { ptr, ptr, i_W, i_W } }"
  let c = instr em $"call ptr @zs_alloc(i_W {size})"
  emit em $"store i32 1, ptr {c}"
  emit em $"store ptr {owner}, ptr {bufField em c 0}"
  emit em $"store ptr {data}, ptr {bufField em c 1}"
  emit em $"store i_W {n}, ptr {bufField em c 2}"
  emit em $"store i_W {cap}, ptr {bufField em c 3}"
  c

// what a span or a Buffer windows: its data and length
let private dataLen (g: G) (em: Emitter) (t: Ty) (v: string) : string * string =
  if isBuf t then
    let d = bufGet em v 1
    (d, bufGet em v 2)
  else
    let d = part g em t v 1
    (d, part g em t v 2)

let private window (g: G) (em: Emitter) (t: Ty) (owner: string) (data: string) (n: string) : string =
  let lt = llty g t
  let w0 = instr em $"insertvalue {lt} poison, ptr {owner}, 0"
  let w1 = instr em $"insertvalue {lt} {w0}, ptr {data}, 1"
  instr em $"insertvalue {lt} {w1}, i_W {n}, 2"

// an array's first element, and its length
let private arrData (g: G) (em: Emitter) (el: Ty) (a: string) : string = instr em $"getelementptr {{ i_W, i_W, [0 x {llty g el}] }}, ptr {a}, i32 0, i32 2, i_W 0"

let private arrLen (g: G) (em: Emitter) (a: string) : string =
  let p = instr em $"getelementptr {{ i_W, i_W }}, ptr {a}, i32 0, i32 1"
  loadLen g em p

// after the bounds check the index is non-negative: nuw tells LLVM an element never overlaps the
// header, so a reference-count check can move out of a loop
let private elemPtr (g: G) (em: Emitter) (t: Ty) (a: string) (i: string) : Ty * string =
  let (el, at) = arrTy g t
  (el, instr em $"getelementptr inbounds nuw {at}, ptr {a}, i32 0, i32 2, i_W {i}")

let private bounds (g: G) (em: Emitter) (a: string) (i: string) =
  let lenp = instr em $"getelementptr {{ i_W, i_W }}, ptr {a}, i32 0, i32 1"
  let len = loadLen g em lenp
  check g em (instr em $"icmp ult i_W {i}, {len}") "index out of bounds"

// how an Atomic stores its value: as it is, except a bool, which is a byte (atomic operations
// take whole bytes)
let private atomicRep (g: G) (em: Emitter) (t: Ty) : string * (string -> string) * (string -> string) =
  match llty g t with
  | "i1" -> ("i8", (fun v -> instr em $"zext i1 {v} to i8"), (fun v -> instr em $"trunc i8 {v} to i1"))
  | lt -> (lt, (fun v -> v), (fun v -> v))

let private newArray (g: G) (em: Emitter) (el: Ty) (n: string) : string =
  let es = sizeOf em (llty g el)
  let size = instr em $"mul i_W {n}, {es}"
  let bytes = instr em $"add i_W HDR2, {size}"
  let a = instr em $"call ptr @zs_alloc(i_W {bytes})"
  emit em $"store i32 1, ptr {a}"
  let lenp = instr em $"getelementptr {{ i_W, i_W }}, ptr {a}, i32 0, i32 1"
  emit em $"store i_W {n}, ptr {lenp}"
  a

// body i for i from 0 to n - 1
let private forEachIndex (em: Emitter) (n: string) (body: string -> unit) =
  let slot = "%" + fresh em "each"
  alloca em $"{slot} = alloca i_W"
  emit em $"store i_W 0, ptr {slot}"
  let lc = fresh em "econd"
  let lb = fresh em "ebody"
  let lend = fresh em "eend"
  emit em $"br label %{lc}"
  enter em lc
  let i = instr em $"load i_W, ptr {slot}"
  let c = instr em $"icmp slt i_W {i}, {n}"
  emit em $"br i1 {c}, label %{lb}, label %{lend}"
  enter em lb
  body i
  let i1 = instr em $"add i_W {i}, 1"
  emit em $"store i_W {i1}, ptr {slot}"
  emit em $"br label %{lc}"
  enter em lend

// the bits of an integer's LLVM type (i32: 32), a float's (float: 32, double: 64)
let private bitsOf (t: string) : int = if t = "float" then 32 else if t = "double" then 64 else toInt (String.sub t 1 (String.length t - 1))

/// SIMD vectors and masks (DESIGN §8): their functions, a module per type (F32x8.load).
let private simdPrim (fx: F) (op: string) (args: list<CExpr>) (vs: list<string>) (ty: Ty) (borrowed0: bool) (unchecked: bool) : string =
  let g = fx.g
  let em = fx.em
  let arg (i: int) = List.item i vs
  let argTy (i: int) = (List.item i args).ty
  // the vector type the function is about: its result's, store's third argument's, or the first
  // argument's
  let vt =
    if List.contains op [ "vec.splat"; "vec.load"; "vec.init"; "vec.convert"; "vec.select"; "vec.shuffle"; "vec.set" ] then ty
    else if op = "vec.store" then argTy 2
    else argTy 0
  let (e, k, et, sfx) = simdShape g vt
  let lt = llty g vt
  let isF = Set.contains e floats
  let uns = Set.contains e unsigned
  let mask = $"<{k} x i1>"
  let un (name: string) = intrinsic g em $"llvm.{name}.{sfx}" lt [ (lt, arg 0) ] ""
  let bin (name: string) = intrinsic g em $"llvm.{name}.{sfx}" lt [ (lt, arg 0); (lt, arg 1) ] ""
  let lane (i: string) = check g em (instr em $"icmp ult i_W {i}, {k}") "lane out of range"
  // the k elements of array arg 0 from index i: all of them in it, or a panic
  let inArray (a: string) (i: string) =
    let lp = instr em $"getelementptr {{ i_W, i_W }}, ptr {a}, i32 0, i32 1"
    let len = loadLen g em lp
    let ok1 = instr em $"icmp ult i_W {i}, {len}"
    let rest = instr em $"sub i_W {len}, {i}"
    let ok2 = instr em $"icmp ule i_W {k}, {rest}"
    check g em (instr em $"and i1 {ok1}, {ok2}") "index out of bounds"
    instr em $"getelementptr inbounds nuw {{ i_W, i_W, [0 x {et}] }}, ptr {a}, i32 0, i32 2, i_W {i}"
  let align =
    match et with
    | "i8" -> "1"
    | "i16" -> "2"
    | "i32"
    | "float" -> "4"
    | _ -> "8"
  match op with
  | "vec.splat" -> splat em k et (arg 0)
  | "vec.load" when isWin (argTy 0) || isBuf (argTy 0) ->
    // from a span (or a Buffer): the k elements from index i of its data
    let t = argTy 0
    let (data, len) = dataLen g em t (arg 0)
    if not unchecked then
      let ok1 = instr em $"icmp ult i_W {arg 1}, {len}"
      let rest = instr em $"sub i_W {len}, {arg 1}"
      let ok2 = instr em $"icmp ule i_W {k}, {rest}"
      check g em (instr em $"and i1 {ok1}, {ok2}") "index out of bounds"
    let p = instr em $"getelementptr inbounds {et}, ptr {data}, i_W {arg 1}"
    let v = instr em $"load {lt}, ptr {p}, align {align}"
    if not borrowed0 then
      dropValue g em t (arg 0)
    v
  | "vec.load" ->
    // unchecked: a versioned loop proved it in bounds
    let p = if unchecked then instr em $"getelementptr inbounds nuw {{ i_W, i_W, [0 x {et}] }}, ptr {arg 0}, i32 0, i32 2, i_W {arg 1}" else inArray (arg 0) (arg 1)
    let v = instr em $"load {lt}, ptr {p}, align {align}"
    if not borrowed0 then
      dropValue g em (argTy 0) (arg 0)
    v
  | "vec.store" ->
    // the array with the lanes written from index i (in place when it was unique)
    let u = instr em $"call ptr {uniqueFn g (argTy 0) false}(ptr {arg 0})"
    let p = inArray u (arg 1)
    emit em $"store {lt} {arg 2}, ptr {p}, align {align}"
    u
  | "vec.get" ->
    lane (arg 1)
    instr em $"extractelement {lt} {arg 0}, i_W {arg 1}"
  | "vec.set" ->
    lane (arg 1)
    instr em $"insertelement {lt} {arg 0}, {et} {arg 2}, i_W {arg 1}"
  | "vec.init" ->
    // f 0, …, f (k - 1), in order
    let cp = instr em $"getelementptr {{ i_W, ptr }}, ptr {arg 0}, i32 0, i32 1"
    let code = instr em $"load ptr, ptr {cp}"
    let laneOf (acc: string) (i: int) =
      let x = instr em $"call {et} {code}(ptr {arg 0}, i_W {i})"
      instr em $"insertelement {lt} {acc}, {et} {x}, i32 {i}"
    let v = List.fold laneOf "poison" (List.init k (fun i -> i))
    dropValue g em (argTy 0) (arg 0)
    v
  | "vec.sum" ->
    // in no particular order (floats: a tree, as SIMD code adds them)
    if isF then intrinsic g em $"llvm.vector.reduce.fadd.{sfx}" et [ (et, "-0.0"); (lt, arg 0) ] "reassoc " else intrinsic g em $"llvm.vector.reduce.add.{sfx}" et [ (lt, arg 0) ] ""
  | "vec.min" -> bin (if isF then "minnum" else if uns then "umin" else "smin")
  | "vec.max" -> bin (if isF then "maxnum" else if uns then "umax" else "smax")
  | "vec.reduceMin"
  | "vec.reduceMax" ->
    let which = if op = "vec.reduceMin" then "min" else "max"
    let name = if isF then "f" + which else if uns then "u" + which else "s" + which
    intrinsic g em $"llvm.vector.reduce.{name}.{sfx}" et [ (lt, arg 0) ] ""
  | "vec.abs" ->
    if isF then un "fabs" else if uns then arg 0 else intrinsic g em $"llvm.abs.{sfx}" lt [ (lt, arg 0); ("i1", "false") ] ""
  | "vec.equal"
  | "vec.notEqual"
  | "vec.lessThan"
  | "vec.lessOrEqual"
  | "vec.greaterThan"
  | "vec.greaterOrEqual" ->
    let rel =
      match String.sub op 4 (String.length op - 4) with
      | "equal" -> "eq"
      | "notEqual" -> "ne"
      | "lessThan" -> "lt"
      | "lessOrEqual" -> "le"
      | "greaterThan" -> "gt"
      | _ -> "ge"
    if isF then
      instr em $"fcmp {(if rel = "ne" then "une" else "o" + rel)} {lt} {arg 0}, {arg 1}"
    else
      let pred = if rel = "eq" || rel = "ne" then rel else if uns then "u" + rel else "s" + rel
      instr em $"icmp {pred} {lt} {arg 0}, {arg 1}"
  | "vec.select" ->
    let vt2 = argTy 1
    instr em $"select {llty g (argTy 0)} {arg 0}, {llty g vt2} {arg 1}, {llty g vt2} {arg 2}"
  | "vec.shuffle" ->
    // the lanes the indices pick from a's then b's: constants
    match literalInts (List.item 2 args) with
    | Some ix when List.length ix = k && List.forall (fun (i: i64) -> i >= i64 0 && i < i64 (2 * k)) ix ->
      dropValue g em (argTy 2) (arg 2)
      let m = String.join ", " (List.map (fun (i: i64) -> $"i32 {i}") ix)
      instr em $"shufflevector {lt} {arg 0}, {lt} {arg 1}, <{k} x i32> <{m}>"
    | _ -> fail fx $"{simdModule (tyName vt)}.shuffle's indices must be an array literal of {k} numbers from 0 to {2 * k - 1}"
  | "vec.sqrt" -> un "sqrt"
  | "vec.floor" -> un "floor"
  | "vec.ceil" -> un "ceil"
  | "vec.round" -> un "roundeven"
  | "vec.mulAdd" -> intrinsic g em $"llvm.fma.{sfx}" lt [ (lt, arg 0); (lt, arg 1); (lt, arg 2) ] ""
  | "vec.convert" ->
    // lane by lane, from the argument's type: floats saturate into integers
    let (e1, _, et1, sfx1) = simdShape g (argTy 0)
    let lt1 = llty g (argTy 0)
    match (Set.contains e1 floats, isF) with
    | (true, true) ->
      if bitsOf et1 = bitsOf et then arg 0 else instr em $"{(if bitsOf et1 < bitsOf et then "fpext" else "fptrunc")} {lt1} {arg 0} to {lt}"
    | (false, true) -> instr em $"{(if Set.contains e1 unsigned then "uitofp" else "sitofp")} {lt1} {arg 0} to {lt}"
    | (true, false) -> intrinsic g em $"llvm.{(if uns then "fptoui" else "fptosi")}.sat.{sfx}.{sfx1}" lt [ (lt1, arg 0) ] ""
    | (false, false) ->
      if bitsOf et1 = bitsOf et then arg 0
      else if bitsOf et1 > bitsOf et then instr em $"trunc {lt1} {arg 0} to {lt}"
      else instr em $"{(if Set.contains e1 unsigned then "zext" else "sext")} {lt1} {arg 0} to {lt}"
  | "mask.any" -> anyLane g em k (arg 0)
  | "mask.all" -> intrinsic g em $"llvm.vector.reduce.and.v{k}i1" "i1" [ (mask, arg 0) ] ""
  | "mask.count" ->
    let bitsN = instr em $"bitcast {mask} {arg 0} to i{k}"
    let n = intrinsic g em $"llvm.ctpop.i{k}" $"i{k}" [ ($"i{k}", bitsN) ] ""
    let w = llty g tInt
    let wbits = bitsOf w
    if wbits = k then n else if wbits > k then instr em $"zext i{k} {n} to {w}" else instr em $"trunc i{k} {n} to {w}"
  | "mask.not" ->
    let ones = String.join ", " (List.replicate k "i1 true")
    instr em $"xor {mask} {arg 0}, <{ones}>"
  | "mask.get" ->
    lane (arg 1)
    instr em $"extractelement {mask} {arg 0}, i_W {arg 1}"
  | _ -> panic $"Codegen: unknown SIMD function {op}"

// ------------------------------------------------------------ expressions

/// The code of e: its value (an SSA name, a constant, or poison after a jump); tail: e is the
/// function's result.
let rec gen (fx: F) (env: Map<string, Binding>) (tail: bool) (e: CExpr) : string =
  let g = fx.g
  let em = fx.em
  match e.k with
  | CPerform _
  | CHandle _ -> panic "Codegen: an effect's node after Evidence"
  | CLine(ln, inner) ->
    let saved = dbgOf em
    let savedLine = fx.line.Value
    let savedAt = fx.at.Value
    if ln > 0 then
      fx.at.Value <- ln
    if g.opts.debugInfo && ln > 0 then
      fx.line.Value <- ln
      fx.lastLine.Value <- max fx.lastLine.Value ln
      setDbg em (diLoc g ln fx.sp)
    let r = gen fx env tail inner
    setDbg em saved
    fx.line.Value <- savedLine
    fx.at.Value <- savedAt
    r
  | CInt k -> if isFloat e.ty then floatConst (llty g e.ty) (f64 k) else $"{k}"
  | CFloat x -> floatConst (llty g e.ty) x
  | CBool b -> if b then "true" else "false"
  | CUnit -> "zeroinitializer"
  | CStr s -> if tyName e.ty = "cstr" then cstrConst g s else strGlobal g s
  | CLocal x -> lookup fx env x e.ty
  | CGlobalVal v -> instr em $"load {llty g e.ty}, ptr {valueSym v}"
  | CLet(x, v, body) ->
    let vv = gen fx env false v
    declareVar fx x v.ty vv None 0
    gen fx (Map.add x (Ssa vv) env) tail body
  | CLetMut(x, v, body) ->
    let vv = gen fx env false v
    // unique: a loop body may be generated twice
    let slot = "%slot." + x + "." + fresh em ""
    alloca em $"{slot} = alloca {llty g v.ty}"
    emit em $"store {llty g v.ty} {vv}, ptr {slot}"
    declareVar fx x v.ty vv (Some slot) 0
    let needsDrop = heap g v.ty
    let r = gen fx (Map.add x (Slot slot) env) (tail && not needsDrop) body
    if needsDrop then
      dropValue g em v.ty (instr em $"load {llty g v.ty}, ptr {slot}")
    r
  | CAssign(x, w) ->
    match w.k with
    | CPrim("slot.moved", [ v ]) ->
      // the old value was moved into the call that computed the new one
      let vv = gen fx env false v
      match Map.find x env with
      | Slot p ->
        emit em $"store {llty g v.ty} {vv}, ptr {p}"
        "zeroinitializer"
      | Ssa _ -> panic "assignment to an immutable variable"
    | _ ->
      let vv = gen fx env false w
      match Map.find x env with
      | Slot p ->
        let old = if heap g w.ty then Some(instr em $"load {llty g w.ty}, ptr {p}") else None
        emit em $"store {llty g w.ty} {vv}, ptr {p}"
        match old with
        | Some o -> dropValue g em w.ty o
        | None -> ()
        "zeroinitializer"
      | Ssa _ -> panic "assignment to an immutable variable"
  | CArraySet(x, i, w) ->
    let vi = gen fx env false i
    let vv = gen fx env false w
    let at = snd (List.head (refs e))
    let el =
      match at with
      | TCon("array", [ el ]) -> el
      | _ -> panic "array set"
    match Map.find x env with
    | Slot p ->
      let u =
        if Set.contains x fx.uniqueSlots.Value then
          // made unique before the enclosing loop, and not shared inside it
          instr em $"load ptr, ptr {p}"
        else
          let a = instr em $"load ptr, ptr {p}"
          let u = instr em $"call ptr {uniqueFn g at false}(ptr {a})"
          emit em $"store ptr {u}, ptr {p}"
          u
      let lp = instr em $"getelementptr {{ i_W, i_W }}, ptr {u}, i32 0, i32 1"
      let len = loadLen g em lp
      check g em (instr em $"icmp ult i_W {vi}, {len}") "index out of bounds"
      let ep = instr em $"getelementptr inbounds nuw {{ i_W, i_W, [0 x {llty g el}] }}, ptr {u}, i32 0, i32 2, i_W {vi}"
      let old = instr em $"load {llty g el}, ptr {ep}"
      emit em $"store {llty g el} {vv}, ptr {ep}"
      dropValue g em el old
      "zeroinitializer"
    | Ssa _ -> panic "array assignment to an immutable variable"
  | CSeq(a, b) ->
    gen fx env false a |> ignore
    gen fx env tail b
  | CDup(x, t, rest) ->
    dupValue g em t (lookup fx env x t)
    gen fx env tail rest
  | CDrop(x, t, rest) ->
    dropValue g em t (lookup fx env x t)
    gen fx env tail rest
  | CDropFields(x, xt, tag, keep, tok, rest) ->
    if isNiche g xt then
      // the value is the field: it keeps the reference, or is dropped
      let v = lookup fx env x xt
      if not (Set.contains 0 keep) then
        match repOf g xt with
        | Niche(_, payload) -> dropValue g em payload v
        | _ -> ()
      let env2 =
        match tok with
        | Some t -> Map.add t (Ssa "null") env
        | None -> env
      gen fx env2 tail rest
    else
      let v = lookup fx env x xt
      let fields = snd (List.item tag (snd (union g xt)))
      let cell = cellTy g xt tag
      let load (i: int) (ft: Ty) =
        let fp = instr em $"getelementptr {cell}, ptr {v}, i32 0, i32 {cellField g xt i}"
        instr em $"load {llty g ft}, ptr {fp}"
      let uniq = fresh em "unique"
      let shared = fresh em "shared"
      let join = fresh em "dropped"
      // with threads, a cell that isn't unique may be another thread's too: its kept fields are
      // dup'd before its reference goes (after, that thread may free it)
      let unique =
        if g.opts.threaded then
          let rc = instr em $"load atomic i32, ptr {v} monotonic, align 4"
          instr em $"icmp eq i32 {rc}, 1"
        else
          instr em $"call i1 @zs.release(ptr {v})"
      emit em $"br i1 {unique}, label %{uniq}, label %{shared}"
      enter em uniq
      // the cell is reused: the object it held has died (its weak references see that)
      if g.opts.checkedHeap && Option.isSome tok then
        emit em $"call void @zs_reused(ptr {v})"
      let dropOne (i: int) (ft: Ty) =
        if heap g ft && not (Set.contains i keep) then
          dropValue g em ft (load i ft)
      List.iteri dropOne fields
      if Option.isNone tok then
        emit em $"call void @zs_free(ptr {v})"
      let fromUniq = current em
      emit em $"br label %{join}"
      enter em shared
      let dupOne (i: int) (ft: Ty) =
        if heap g ft && Set.contains i keep then
          dupValue g em ft (load i ft)
      List.iteri dupOne fields
      if g.opts.threaded then
        dropValue g em xt v
      let fromShared = current em
      emit em $"br label %{join}"
      enter em join
      let env2 =
        match tok with
        | Some t -> Map.add t (Ssa(instr em $"phi ptr [ {v}, %{fromUniq} ], [ null, %{fromShared} ]")) env
        | None -> env
      gen fx env2 tail rest
  | CFreeToken(tok, rest) ->
    let t = lookup fx env tok tUnit
    let yes = fresh em "freetok"
    let no = fresh em "notok"
    let some = instr em $"icmp ne ptr {t}, null"
    emit em $"br i1 {some}, label %{yes}, label %{no}"
    enter em yes
    emit em $"call void @zs_free(ptr {t})"
    emit em $"br label %{no}"
    enter em no
    gen fx env tail rest
  | CCtorAt(tok, _, tag, args) ->
    let vs = List.map (gen fx env false) args
    let cell = cellTy g e.ty tag
    let t = lookup fx env tok tUnit
    let allocL = fresh em "alloc"
    let reuse = fresh em "reuse"
    let join = fresh em "built"
    let none = instr em $"icmp eq ptr {t}, null"
    emit em $"br i1 {none}, label %{allocL}, label %{reuse}"
    enter em allocL
    let a = instr em $"call ptr @zs_alloc(i_W {sizeOf em cell})"
    let fromAlloc = current em
    emit em $"br label %{join}"
    enter em reuse
    emit em $"br label %{join}"
    enter em join
    let c = instr em $"phi ptr [ {a}, %{fromAlloc} ], [ {t}, %{reuse} ]"
    emit em $"store i32 1, ptr {c}"
    if tagged g e.ty then
      storeTag g em c tag
    let store (i: int) (av: CExpr * string) =
      let (arg, x) = av
      let fp = instr em $"getelementptr {cell}, ptr {c}, i32 0, i32 {cellField g e.ty i}"
      emit em $"store {llty g arg.ty} {x}, ptr {fp}"
    List.iteri store (List.zip args vs)
    c
  | CJoin(j, ps, body, rest) ->
    // a block that rest's jumps branch to, its parameters as phis
    let lab = fresh em "join"
    let joined = fresh em "joined"
    let incoming = Buffer.empty
    fx.joinBlocks.Value <- Map.add j (lab, incoming) fx.joinBlocks.Value
    let vr = gen fx env tail rest
    let fromRest = current em
    emit em $"br label %{joined}"
    if Buffer.length incoming = 0 then
      enter em joined
      vr
    else
      enter em lab
      let inc = Array.toList (Buffer.toArray incoming)
      let param (m: Map<string, Binding>) (ix: int * (string * Ty)) =
        let (i, (x, t)) = ix
        Map.add x (Ssa(phi fx (llty g t) (List.map (fun (args, b) -> (List.item i args, b)) inc))) m
      let env2 = List.fold param env (List.indexed ps)
      let vb = gen fx env2 tail body
      let fromBody = current em
      emit em $"br label %{joined}"
      enter em joined
      phi fx (llty g e.ty) [ (vr, fromRest); (vb, fromBody) ]
  | CJump(j, args) ->
    let vs = List.map (gen fx env false) args
    let (lab, incoming) = Map.find j fx.joinBlocks.Value
    Buffer.push (vs, current em) incoming
    emit em $"br label %{lab}"
    dead em
    "poison"
  | CIf(c, t, f) ->
    let vc = gen fx env false c
    let lt = fresh em "then"
    let lf = fresh em "else"
    let lend = fresh em "endif"
    emit em $"br i1 {vc}, label %{lt}, label %{lf}"
    enter em lt
    let vt = gen fx env tail t
    let bt = current em
    emit em $"br label %{lend}"
    enter em lf
    let vf = gen fx env tail f
    let bf = current em
    emit em $"br label %{lend}"
    enter em lend
    phi fx (llty g e.ty) [ (vt, bt); (vf, bf) ]
  | CMatch(s, cases) ->
    // clauses are tested one after another: Decide turns the matches whose patterns nest into
    // decision trees, except where the tree would grow too large
    let v = gen fx env false s
    let endL = fresh em "mend"
    let next = ref (fresh em "case")
    let results = Buffer.empty
    emit em $"br label %{next.Value}"
    // the cases of a union no earlier clause has taken whole: a clause for the last of them needs
    // no test of the case
    let caseCount =
      match repOfUnion g s.ty with
      | Some _ -> Some(List.length (snd (union g s.ty)))
      | None -> None
    let taken = ref Set.empty
    for (p, guard, body) in cases do
      enter em next.Value
      let failL = fresh em "case"
      let known =
        match (p, caseCount) with
        | (CPCtor(_, tag, _), Some n) -> not (Set.contains tag taken.Value) && Set.count taken.Value = n - 1
        | _ -> false
      let env2 = testIn fx known p s.ty v failL env
      match p with
      | CPCtor(_, tag, ps) when Option.isNone guard && List.forall irrefutable ps -> taken.Value <- Set.add tag taken.Value
      | _ -> ()
      match guard with
      | Some gd ->
        let ok = fresh em "guard"
        let gv = gen fx env2 false gd
        emit em $"br i1 {gv}, label %{ok}, label %{failL}"
        enter em ok
      | None -> ()
      let r = gen fx env2 tail body
      Buffer.push (r, current em) results
      emit em $"br label %{endL}"
      next.Value <- failL
    enter em next.Value
    // unreachable: the type checker proved exhaustiveness
    panicWith g em "match failure"
    enter em endL
    phi fx (llty g e.ty) (Array.toList (Buffer.toArray results))
  | CTuple xs ->
    let ty = llty g e.ty
    let vs = List.map (gen fx env false) xs
    let insert (agg: string) (ixv: int * (CExpr * string)) =
      let (i, (x, v)) = ixv
      instr em $"insertvalue {ty} {agg}, {llty g x.ty} {v}, {i}"
    List.fold insert "poison" (List.indexed (List.zip xs vs))
  | CField(r, i) ->
    let rv = gen fx env false r
    instr em $"extractvalue {llty g r.ty} {rv}, {i}"
  | CCtor(_, tag, args) ->
    if plainUnion g.v g.types e.ty then
      // a value: the tag and this case's fields, the other cases' fields zero
      let vs = List.map (gen fx env false) args
      let lt = llty g e.ty
      let withTag = instr em $"insertvalue {lt} zeroinitializer, {tagTy (snd (union g e.ty))} {tag}, 0"
      let insert (agg: string) (iav: int * (CExpr * string)) =
        let (i, (a, v)) = iav
        instr em $"insertvalue {lt} {agg}, {llty g a.ty} {v}, {plainField g e.ty tag i}"
      List.fold insert withTag (List.indexed (List.zip args vs))
    else if isNiche g e.ty then
      // a niche: the field itself, or @zs.none
      match args with
      | [ a ] -> gen fx env false a
      | _ -> "@zs.none"
    else if List.isEmpty args then
      nullary g e.ty tag
    else
      let vs = List.map (gen fx env false) args
      let cell = cellTy g e.ty tag
      let c = instr em $"call ptr @zs_alloc(i_W {sizeOf em cell})"
      emit em $"store i32 1, ptr {c}"
      if tagged g e.ty then
        storeTag g em c tag
      let store (i: int) (av: CExpr * string) =
        let (a, v) = av
        let fp = instr em $"getelementptr {cell}, ptr {c}, i32 0, i32 {cellField g e.ty i}"
        emit em $"store {llty g a.ty} {v}, ptr {fp}"
      List.iteri store (List.zip args vs)
      c
  | CBin(op0, a, b) ->
    let va = gen fx env false a
    let vb = gen fx env false b
    let t = a.ty
    let lt = llty g t
    // a [<FastMath>] function's float + - * /: LLVM's fast ones
    let fast = String.startsWith "fast" op0
    let op1 = if fast then String.sub op0 4 (String.length op0 - 4) else op0
    // a [<Wrapping>] function's + - *: wrapping on integers, the usual ones otherwise
    let op = if String.startsWith "wrap" op1 && not (Set.contains (tyName t) ints) then String.sub op1 4 (String.length op1 - 4) else op1
    let n = tyName t
    if isVectorName n || isMaskName n then
      simdBin g em op t va vb fast
    else if n = "string" then
      let r =
        if op = "+" then
          instr em $"call ptr @zs_str_concat(ptr {va}, ptr {vb})"
        else
          let c = instr em $"call i_W @zs_str_cmp(ptr {va}, ptr {vb})"
          instr em $"icmp {Map.find op icmpS} i_W {c}, 0"
      dropValue g em t va
      dropValue g em t vb
      r
    else if n = "unit" then
      if op = "=" then "true" else "false"
    else if isFloat t then
      match Map.tryFind op farith with
      | Some fo -> instr em $"{fo}{(if fast then " fast" else "")} {lt} {va}, {vb}"
      | None -> instr em $"fcmp {Map.find op fcmp} {lt} {va}, {vb}"
    else if op = "&&&" then
      instr em $"and {lt} {va}, {vb}"
    else if op = "|||" then
      instr em $"or {lt} {va}, {vb}"
    else if op = "^^^" then
      instr em $"xor {lt} {va}, {vb}"
    else if op = "<<<" || op = ">>>" then
      // the shift amount is taken modulo the width, as in F# (LLVM leaves larger ones undefined)
      let bits = bitsOf lt
      let amount = instr em $"and {lt} {vb}, {bits - 1}"
      let ins = if op = "<<<" then "shl" else if isUnsigned t then "lshr" else "ashr"
      instr em $"{ins} {lt} {va}, {amount}"
    else if String.startsWith "wrap" op then
      instr em $"{Map.find (String.sub op 4 (String.length op - 4)) arith} {lt} {va}, {vb}"
    else if Map.containsKey op arith then
      checkedArith g em op (isUnsigned t) lt va vb
    else if op = "/" || op = "%" then
      check g em (instr em $"icmp ne {lt} {vb}, 0") "division by zero"
      if not (isUnsigned t) then
        // MIN / -1 doesn't fit (and is undefined behaviour in LLVM)
        let isMin = instr em $"icmp eq {lt} {va}, {minOf (bitsOf lt)}"
        let isNeg1 = instr em $"icmp eq {lt} {vb}, -1"
        let bad = instr em $"and i1 {isMin}, {isNeg1}"
        check g em (instr em $"xor i1 {bad}, true") "integer overflow"
      let ins = (if isUnsigned t then "u" else "s") + (if op = "/" then "div" else "rem")
      instr em $"{ins} {lt} {va}, {vb}"
    else
      let table = if isUnsigned t then icmpU else icmpS
      instr em $"icmp {Map.find op table} {lt} {va}, {vb}"
  | CNeg a ->
    let va = gen fx env false a
    let n = tyName a.ty
    let floatVector = isVectorName n && Set.contains (fst (Option.get (vectorInfo n))) floats
    // a vector of integers: wrapping, lane by lane
    if isFloat a.ty || floatVector then instr em $"fneg {llty g a.ty} {va}"
    else if isVectorName n then instr em $"sub {llty g a.ty} zeroinitializer, {va}"
    else checkedArith g em "-" (isUnsigned a.ty) (llty g a.ty) "0" va
  | CNot a ->
    let va = gen fx env false a
    instr em $"xor i1 {va}, true"
  | CCallDirect(fname, args) ->
    let fd = Map.find fname g.fnTable
    let vs = List.map (gen fx env false) args
    let argv = String.join ", " (List.map (typed g) (List.zip args vs))
    let rt = llty g fd.ret
    if tail && proto g fd = fx.selfProto then
      // a call to itself is left to LLVM to make a loop (which can then be inlined into callers);
      // other tail calls, and all at -O0, must be tail calls (constant stack), except of a result
      // wider than two registers: x86-64 returns it in memory, where it can't make a musttail
      // call (LLVM still makes a loop of a call to itself, at -O2). In an optimized build, a call
      // to a function of another LLVM module is a plain tail call (a sibling call all the same):
      // ThinLTO imports the callee and inlines it at a musttail call into a module LLVM's
      // verifier then rejects (LLVM 23)
      let inRegisters = not (String.startsWith "{" rt) || (List.length (String.split "," rt) <= 2 && not (String.contains "{" (String.sub rt 1 (String.length rt - 1))) && not (String.contains "[" rt))
      let elsewhere =
        match g.part with
        | Some p -> g.opts.optimized && not (Set.contains fname p.defines)
        | None -> false
      // an empty struct's result (unit) too: -O2 replaces the result with a constant and merges
      // the function's returns, leaving the musttail call before a branch (LLVM 23)
      let unitResult = g.opts.optimized && rt = "{}"
      let kind = if (fname = fx.f.name && g.opts.optimized && not g.opts.debugInfo) || not inRegisters || elsewhere || unitResult then "tail" else "musttail"
      let r = instr em $"{kind} call {rt} {sym g fname}({argv})"
      emit em $"ret {rt} {r}"
      dead em
      "poison"
    else
      instr em $"{(if tail then "tail " else "")}call {rt} {sym g fname}({argv})"
  | CExtern(n, args) ->
    let s = Map.find n g.externs
    cCall fx ("@" + n) s args (List.map (gen fx env false) args)
  | CMkClosure(fname, args) ->
    if List.isEmpty args then
      staticClosure g fname
    else
      let vs = List.map (gen fx env false) args
      allocClosure g em fname (List.zip (List.map (fun (a: CExpr) -> a.ty) args) vs)
  | CApplyClo(c, args) -> applyClosure fx env e c args
  | CWhile _
  | CFor _ -> genLoop fx env tail e
  | CPrim(op, args) when op = "task.suspend" || op = "task.abandon" -> wait fx env op args e.ty
  | CPrim(op, args) -> prim fx env op args e.ty
  | _ -> panic "Codegen: unexpected node"

// a closure applied: one argument at a time (each call but the last gives a closure holding
// more), or all at once when it takes exactly that many
and applyClosure (fx: F) (env: Map<string, Binding>) (e: CExpr) (c: CExpr) (args: list<CExpr>) : string =
  let g = fx.g
  let em = fx.em
  let vc = gen fx env false c
  let vs = List.zip args (List.map (gen fx env false) args)
  let nargs = List.length vs
  let curried (vc0: string) : string =
    let step (cur: string) (iav: int * (CExpr * string)) =
      let (i, (a, v)) = iav
      let cp = instr em $"getelementptr {{ i_W, ptr }}, ptr {cur}, i32 0, i32 1"
      let code = instr em $"load ptr, ptr {cp}"
      let rt = if i = nargs - 1 then llty g e.ty else "ptr"
      let r = instr em $"call {rt} {code}(ptr {cur}, {llty g a.ty} {v})"
      // a closure made on the way
      if i > 0 then
        emit em $"call void @zs.drop.clo(ptr {cur})"
      r
    List.fold step vc0 (List.indexed vs)
  if nargs = 1 then
    curried vc
  else
    let ip = instr em $"getelementptr {{ i_W, ptr, ptr }}, ptr {vc}, i32 0, i32 2"
    let inf = instr em $"load ptr, ptr {ip}"
    let ap = instr em $"getelementptr {{ ptr, i32, ptr }}, ptr {inf}, i32 0, i32 1"
    let arity = instr em $"load i32, ptr {ap}"
    let fullL = fresh em "full"
    let oneL = fresh em "curried"
    let doneL = fresh em "applied"
    let same = instr em $"icmp eq i32 {arity}, {nargs}"
    emit em $"br i1 {same}, label %{fullL}, label %{oneL}"
    enter em fullL
    let fp = instr em $"getelementptr {{ ptr, i32, ptr }}, ptr {inf}, i32 0, i32 2"
    let code = instr em $"load ptr, ptr {fp}"
    let argv = String.join ", " (List.map (typed g) vs)
    let r1 = instr em $"call {llty g e.ty} {code}(ptr {vc}, {argv})"
    let fromFull = current em
    emit em $"br label %{doneL}"
    enter em oneL
    let r2 = curried vc
    let fromOne = current em
    emit em $"br label %{doneL}"
    enter em doneL
    phi fx (llty g e.ty) [ (r1, fromFull); (r2, fromOne) ]

// a loop: the arrays it writes made unique before it when it can keep them so (loopUniques), then
// versioned (a for loop) or as it is
and genLoop (fx: F) (env: Map<string, Binding>) (tail: bool) (e: CExpr) : string =
  let g = fx.g
  let em = fx.em
  let arrays = loopUniques fx env e
  if List.isEmpty arrays then
    genVersioned fx env tail e
  else
    for (_, p, t) in arrays do
      let a = instr em $"load ptr, ptr {p}"
      let u = instr em $"call ptr {uniqueFn g t false}(ptr {a})"
      emit em $"store ptr {u}, ptr {p}"
    for (x, _, _) in arrays do
      fx.uniqueSlots.Value <- Set.add x fx.uniqueSlots.Value
    let r = genVersioned fx env tail e
    for (x, _, _) in arrays do
      fx.uniqueSlots.Value <- Set.remove x fx.uniqueSlots.Value
    r

// loop versioning: if every a.[x ± c] (and SIMD load) the loop reads is in bounds for the whole
// range, a copy of the loop without those bounds checks runs; otherwise the checked one
and genVersioned (fx: F) (env: Map<string, Binding>) (tail: bool) (e: CExpr) : string =
  let g = fx.g
  let em = fx.em
  match e.k with
  | CFor(x, a, step, b, body) ->
    // at -Os only small bodies: duplicating them costs a few dozen bytes
    let (marked, reads) = if hasLoop body || (g.opts.optimizeSize && nodes body > 40) then (body, []) else affineReads env x body
    if not (positiveStep step) || List.isEmpty reads then
      genPlain fx env e
    else
      let lt = llty g a.ty
      let va = gen fx env false a
      let vb = gen fx env false b
      let value (c: CExpr) = gen fx env false c
      let ovf (op: string) (p: string) (q: string) (bad: string) : string * string =
        let name = $"llvm.s{op}.with.overflow.{lt}"
        let decl = $"declare {{ {lt}, i1 }} @{name}({lt}, {lt})"
        if firstTime g decl then
          helper g (decl + "\n")
        let r = instr em $"call {{ {lt}, i1 }} @{name}({lt} {p}, {lt} {q})"
        let v0 = instr em $"extractvalue {{ {lt}, i1 }} {r}, 0"
        let o = instr em $"extractvalue {{ {lt}, i1 }} {r}, 1"
        (v0, instr em $"or i1 {bad}, {o}")
      let readOk (ok: string) (rd: CExpr * int * list<int * CExpr> * int) : string =
        let (arr, coef, terms, lanes) = rd
        // the index's other terms summed (any overflow fails the test)
        let sum (acc: string * string) (st: int * CExpr) =
          let (cur, bad) = acc
          let (sign, t) = st
          let tv = value t
          ovf (if sign > 0 then "add" else "sub") cur tv bad
        let (cv, bad0) = List.fold sum ("0", "false") terms
        let (lo, hi0, bad1) =
          if coef > 0 then
            let (lo, b1) = ovf "add" va cv bad0
            let (hi, b2) = ovf "add" vb cv b1
            (lo, hi, b2)
          else
            let (lo, b1) = ovf "sub" cv vb bad0
            let (hi, b2) = ovf "sub" cv va b1
            (lo, hi, b2)
        // a SIMD load reads lanes elements from its index
        let (hi, bad) = if lanes > 1 then ovf "add" hi0 $"{lanes - 1}" bad1 else (hi0, bad1)
        let len =
          if isWin arr.ty then
            let av = value arr
            instr em $"extractvalue {llty g arr.ty} {av}, 2"
          else
            let av = value arr
            loadLen g em (instr em $"getelementptr {{ i_W, i_W }}, ptr {av}, i32 0, i32 1")
        let ge = instr em $"icmp sge {lt} {lo}, 0"
        let below = instr em $"icmp slt {lt} {hi}, {len}"
        let inRange = instr em $"and i1 {ge}, {below}"
        let noOvf = instr em $"xor i1 {bad}, true"
        let both = instr em $"and i1 {inRange}, {noOvf}"
        instr em $"and i1 {ok}, {both}"
      let ok = List.fold readOk "true" reads
      let fast = fresh em "vfast"
      let slow = fresh em "vslow"
      let join = fresh em "vjoin"
      emit em $"br i1 {ok}, label %{fast}, label %{slow}"
      enter em fast
      genPlain fx env { e with k = CFor(x, a, step, b, marked) } |> ignore
      emit em $"br label %{join}"
      enter em slow
      genPlain fx env e |> ignore
      emit em $"br label %{join}"
      enter em join
      "zeroinitializer"
  | _ -> genPlain fx env e

and genPlain (fx: F) (env: Map<string, Binding>) (e: CExpr) : string =
  let g = fx.g
  let em = fx.em
  match e.k with
  | CWhile(c, b) ->
    let lc = fresh em "wcond"
    let lb = fresh em "wbody"
    let lend = fresh em "wend"
    emit em $"br label %{lc}"
    enter em lc
    let vc = gen fx env false c
    emit em $"br i1 {vc}, label %{lb}, label %{lend}"
    enter em lb
    gen fx env false b |> ignore
    emit em $"br label %{lc}"
    enter em lend
    "zeroinitializer"
  | CFor(x, a, step, b, body) ->
    let lt = llty g a.ty
    let va = gen fx env false a
    let vs = gen fx env false step
    let vb = gen fx env false b
    // unique: a loop body may be generated twice
    let slot = "%slot." + x + "." + fresh em ""
    alloca em $"{slot} = alloca {lt}"
    emit em $"store {lt} {va}, ptr {slot}"
    declareVar fx x a.ty va (Some slot) 0
    let lc = fresh em "fcond"
    let lb = fresh em "fbody"
    let lend = fresh em "fend"
    emit em $"br label %{lc}"
    enter em lc
    let i = instr em $"load {lt}, ptr {slot}"
    let down =
      match step.k with
      | CInt k -> k < i64 0
      | CNeg _ -> true
      | _ -> false
    let cmp = if down then (if isUnsigned a.ty then "uge" else "sge") else (if isUnsigned a.ty then "ule" else "sle")
    let cond = instr em $"icmp {cmp} {lt} {i}, {vb}"
    emit em $"br i1 {cond}, label %{lb}, label %{lend}"
    enter em lb
    gen fx (Map.add x (Ssa i) env) false body |> ignore
    let nx = instr em $"add {lt} {i}, {vs}"
    emit em $"store {lt} {nx}, ptr {slot}"
    emit em $"br label %{lc}"
    enter em lend
    "zeroinitializer"
  | _ -> panic "Codegen: not a loop"

/// What a wait calls between its save and its suspend: work c face, through the closure's
/// description (all at once when it takes both, else one at a time), then work dropped. Not in
/// the coroutine (nor inlined into it), since work may resume it before returning.
and taskStart (g: G) (cTy: Ty) (workTy: Ty) : string =
  let ct = llty g cTy
  let name = $"@\"zs.task.start.{showF g cTy}\""
  if firstTime g name then
    let em = emitter ()
    let wp = instr em "getelementptr { i_W, ptr, ptr }, ptr %work, i32 0, i32 2"
    let winf = instr em $"load ptr, ptr {wp}"
    let ap = instr em $"getelementptr {{ ptr, i32, ptr }}, ptr {winf}, i32 0, i32 1"
    let arity = instr em $"load i32, ptr {ap}"
    let two = instr em $"icmp eq i32 {arity}, 2"
    emit em $"br i1 {two}, label %full, label %curried"
    enter em "full"
    let fp = instr em $"getelementptr {{ ptr, i32, ptr }}, ptr {winf}, i32 0, i32 2"
    let full = instr em $"load ptr, ptr {fp}"
    emit em $"call {{}} {full}(ptr %work, {ct} %c, ptr %face)"
    emit em "br label %called"
    enter em "curried"
    let cp1 = instr em "getelementptr { i_W, ptr }, ptr %work, i32 0, i32 1"
    let code1 = instr em $"load ptr, ptr {cp1}"
    let partial = instr em $"call ptr {code1}(ptr %work, {ct} %c)"
    let cp2 = instr em $"getelementptr {{ i_W, ptr }}, ptr {partial}, i32 0, i32 1"
    let code2 = instr em $"load ptr, ptr {cp2}"
    emit em $"call {{}} {code2}(ptr {partial}, ptr %face)"
    emit em $"call void @zs.drop.clo(ptr {partial})"
    emit em "br label %called"
    enter em "called"
    dropValue g em workTy "%work"
    emit em "ret void"
    helper g $"define private void {name}(ptr %work, {ct} %c, ptr %face) noinline {{\n{bodyOf em}}}\n\n"
  name

/// A wait in a task's state machine: task.suspend(work, c) runs the awaited task's work with the
/// face as its continuation, then suspends until the face is called with the result; task.abandon
/// suspends for good (the task was cancelled). Both end with task.held: what a cancelled task
/// holds here, dropped if the coroutine is destroyed at this suspension.
and wait (fx: F) (env: Map<string, Binding>) (op: string) (args: list<CExpr>) (t: Ty) : string =
  let g = fx.g
  let em = fx.em
  let real = List.take (List.length args - 1) args
  let held =
    match List.last args with
    | { k = CPrim("task.held", xs) } -> xs
    | _ -> []
  let n = fresh em "wait"
  let save =
    if op = "task.suspend" then
      let work = gen fx env false (List.item 0 real)
      let c = gen fx env false (List.item 1 real)
      let (code, inf) = faceFor g t
      let cp = instr em "getelementptr { i_W, ptr, ptr }, ptr %face, i32 0, i32 1"
      emit em $"store ptr {code}, ptr {cp}"
      let ip = instr em "getelementptr { i_W, ptr, ptr }, ptr %face, i32 0, i32 2"
      emit em $"store ptr {inf}, ptr {ip}"
      // the awaited task's reference
      emit em "call void @zs.dup(ptr %face)"
      let save = instr em "call token @llvm.coro.save(ptr %coro.hdl)"
      // one call between the save and the suspend: work may resume the coroutine before it
      // returns, so nothing here may use a value of the frame's after it
      let ct = llty g (List.item 1 real).ty
      let start = taskStart g (List.item 1 real).ty (List.item 0 real).ty
      emit em $"call void {start}(ptr {work}, {ct} {c}, ptr %face)"
      save
    else
      instr em "call token @llvm.coro.save(ptr %coro.hdl)"
  let s = instr em $"call i8 @llvm.coro.suspend(token {save}, i1 false)"
  let resumed = n + ".resumed"
  let cleanup = n + ".cleanup"
  emit em $"switch i8 {s}, label %coro.exit [ i8 0, label %{resumed} i8 1, label %{cleanup} ]"
  enter em cleanup
  for h in held do
    match h.k with
    | CLocal x -> dropValue g em h.ty (lookup fx env x h.ty)
    | _ -> ()
  emit em "br label %coro.destroy"
  enter em resumed
  if op = "task.suspend" then
    let rp = instr em $"getelementptr {{ i_W, ptr, ptr, ptr, {llty g t} }}, ptr %face, i32 0, i32 4"
    instr em $"load {llty g t}, ptr {rp}"
  else
    emit em "unreachable"
    dead em
    "poison"

/// A primitive's code. op!: a read a versioned loop proved in bounds; op#b: the first argument is
/// borrowed (the Rc pass keeps it alive), so it isn't dropped.
and prim (fx: F) (env: Map<string, Binding>) (op0: string) (args: list<CExpr>) (ty: Ty) : string =
  let g = fx.g
  let em = fx.em
  let unchecked = String.endsWith "!" op0
  let op1 = if unchecked then String.sub op0 0 (String.length op0 - 1) else op0
  let borrowed0 = String.endsWith "#b" op1
  let op = if borrowed0 then String.sub op1 0 (String.length op1 - 2) else op1
  let vs = List.map (gen fx env false) args
  let arg (i: int) = List.item i vs
  let argTy (i: int) = (List.item i args).ty
  // the first argument dropped, unless it's borrowed
  let dropFirst () =
    if not borrowed0 then
      dropValue g em (argTy 0) (arg 0)
  match op with
  | "fixed.length" ->
    match argTy 0 with
    | TCon("fixed", [ _; TCon(n, []) ]) ->
      dropFirst ()
      n
    | t -> panic $"fixed.length of {showT g t}"
  | "fixed.get"
  | "fixed.set" ->
    // an element of a fixed-size array (a value): through a copy in memory, which LLVM keeps in
    // registers when it can
    let t = argTy 0
    let (el, n) =
      match t with
      | TCon("fixed", [ el; TCon(n, []) ]) -> (el, n)
      | _ -> panic $"{op} of {showT g t}"
    check g em (instr em $"icmp ult i_W {arg 1}, {n}") "index out of bounds"
    let slot = "%" + fresh em "fixed"
    alloca em $"{slot} = alloca {llty g t}"
    emit em $"store {llty g t} {arg 0}, ptr {slot}"
    let ep = instr em $"getelementptr inbounds {llty g t}, ptr {slot}, i_W 0, i_W {arg 1}"
    let v = instr em $"load {llty g el}, ptr {ep}"
    if op = "fixed.get" then
      dupValue g em el v
      dropFirst ()
      v
    else
      // the changed one: the old element's reference dropped, the new one's moved in
      emit em $"store {llty g el} {arg 2}, ptr {ep}"
      dropValue g em el v
      instr em $"load {llty g t}, ptr {slot}"
  | "fixed.ofArray" ->
    // the elements of an array (or a window) of exactly N, copied in
    let (el, n) =
      match ty with
      | TCon("fixed", [ el; TCon(n, []) ]) -> (el, n)
      | _ -> panic $"fixed.ofArray of {showT g ty}"
    let t = argTy 0
    let (data, len) =
      if isWin t || isBuf t then
        dataLen g em t (arg 0)
      else
        let d = arrData g em el (arg 0)
        (d, arrLen g em (arg 0))
    let good = fresh em "fixedlen"
    let bad = fresh em "badlen"
    let same = instr em $"icmp eq i_W {len}, {n}"
    emit em $"br i1 {same}, label %{good}, label %{bad}"
    enter em bad
    emit em $"call void @zs_fixed_fail(ptr {cstrConst g (showT g ty)}, i_W {len})"
    emit em "unreachable"
    enter em good
    let slot = "%" + fresh em "fixed"
    alloca em $"{slot} = alloca {llty g ty}"
    let bytes = instr em $"mul i_W {n}, {sizeOf em (llty g el)}"
    emit em $"call void @llvm.memcpy.p0.p0.i_W(ptr {slot}, ptr {data}, i_W {bytes}, i1 false)"
    if heap g el then
      let dupAt (i: string) =
        let ep = instr em $"getelementptr inbounds {llty g ty}, ptr {slot}, i_W 0, i_W {i}"
        dupValue g em el (instr em $"load {llty g el}, ptr {ep}")
      forEachIndex em n dupAt
    dropFirst ()
    instr em $"load {llty g ty}, ptr {slot}"
  | "fixed.create" ->
    // N copies of the value
    let (el, n) =
      match ty with
      | TCon("fixed", [ el; TCon(n, []) ]) -> (el, n)
      | _ -> panic $"fixed.create of {showT g ty}"
    let slot = "%" + fresh em "fixed"
    alloca em $"{slot} = alloca {llty g ty}"
    let storeAt (i: string) =
      let ep = instr em $"getelementptr inbounds {llty g ty}, ptr {slot}, i_W 0, i_W {i}"
      emit em $"store {llty g el} {arg 0}, ptr {ep}"
      dupValue g em el (arg 0)
    forEachIndex em n storeAt
    // each element took its own reference
    dropValue g em el (arg 0)
    instr em $"load {llty g ty}, ptr {slot}"
  | "Array.length" when isBuf (argTy 0) ->
    let n = bufGet em (arg 0) 2
    dropFirst ()
    n
  | "array.get" when isBuf (argTy 0) ->
    let t = argTy 0
    let el = bufEl g t
    let (data, len) = dataLen g em t (arg 0)
    if not unchecked then
      check g em (instr em $"icmp ult i_W {arg 1}, {len}") "index out of bounds"
    let ep = instr em $"getelementptr inbounds {llty g el}, ptr {data}, i_W {arg 1}"
    let v = instr em $"load {llty g el}, ptr {ep}"
    dupValue g em el v
    dropFirst ()
    v
  | "array.set" when isBuf (argTy 0) ->
    // a Buffer's element, written in place: every reference to the Buffer sees it
    let t = argTy 0
    let el = bufEl g t
    let (data, len) = dataLen g em t (arg 0)
    check g em (instr em $"icmp ult i_W {arg 1}, {len}") "index out of bounds"
    let ep = instr em $"getelementptr inbounds {llty g el}, ptr {data}, i_W {arg 1}"
    let old = instr em $"load {llty g el}, ptr {ep}"
    emit em $"store {llty g el} {arg 2}, ptr {ep}"
    dropValue g em el old
    dropValue g em t (arg 0)
    "zeroinitializer"
  | "buffer.push" ->
    // push x b: room made when there's none (Core's bufferDef says how)
    let t = argTy 1
    emit em $"call void {bufferFn g "push" (bufEl g t)}(ptr {arg 1}, {llty g (argTy 0)} {arg 0})"
    dropValue g em t (arg 1)
    "zeroinitializer"
  | "buffer.removeLast" ->
    let t = argTy 0
    let v = instr em $"call {llty g ty} {bufferFn g "removeLast" (bufEl g t)}(ptr {arg 0})"
    dropFirst ()
    v
  | "buffer.truncate" ->
    let t = argTy 1
    emit em $"call void {bufferFn g "truncate" (bufEl g t)}(ptr {arg 1}, i_W {arg 0})"
    dropValue g em t (arg 1)
    "zeroinitializer"
  | "buffer.blit" ->
    // blit src i dst j n: n elements of a span copied into a Buffer, as memmove would
    let st = argTy 0
    let dt = argTy 2
    let (sd, sl) = dataLen g em st (arg 0)
    let (dd, dl) = dataLen g em dt (arg 2)
    emit em $"call void {bufferFn g "blit" (bufEl g dt)}(ptr {sd}, i_W {sl}, i_W {arg 1}, ptr {dd}, i_W {dl}, i_W {arg 3}, i_W {arg 4})"
    dropFirst ()
    dropValue g em dt (arg 2)
    "zeroinitializer"
  | "Array.length" when isWin (argTy 0) ->
    let n = part g em (argTy 0) (arg 0) 2
    dropFirst ()
    n
  | "array.get" when isWin (argTy 0) ->
    let t = argTy 0
    let el = winEl g t
    if not unchecked then
      let len = part g em t (arg 0) 2
      check g em (instr em $"icmp ult i_W {arg 1}, {len}") "index out of bounds"
    let data = part g em t (arg 0) 1
    let ep = instr em $"getelementptr inbounds {llty g el}, ptr {data}, i_W {arg 1}"
    let v = instr em $"load {llty g el}, ptr {ep}"
    dupValue g em el v
    dropFirst ()
    v
  | "array.set" when isWin (argTy 0) ->
    // a Buffer's element, written in place: every alias of the window sees it
    let t = argTy 0
    let el = winEl g t
    let len = part g em t (arg 0) 2
    check g em (instr em $"icmp ult i_W {arg 1}, {len}") "index out of bounds"
    let data = part g em t (arg 0) 1
    let ep = instr em $"getelementptr inbounds {llty g el}, ptr {data}, i_W {arg 1}"
    let old = instr em $"load {llty g el}, ptr {ep}"
    emit em $"store {llty g el} {arg 2}, ptr {ep}"
    dropValue g em el old
    dropValue g em t (arg 0)
    "zeroinitializer"
  | "span.ofArray" ->
    // the array's reference moves into the span
    let d = arrData g em (winEl g ty) (arg 0)
    let n = arrLen g em (arg 0)
    window g em ty (arg 0) d n
  | "span.ofBuffer" ->
    // a window over what the Buffer holds now, with a reference to its storage
    let t = argTy 0
    let owner = bufGet em (arg 0) 0
    dupValue g em (TCon("array", [ bufEl g t ])) owner
    let (data, len) = dataLen g em t (arg 0)
    let w = window g em ty owner data len
    dropFirst ()
    w
  | "span.ofString" ->
    let lp = instr em $"getelementptr i8, ptr {arg 0}, i_W HDR1"
    let n = loadLen g em lp
    let d = instr em $"getelementptr i8, ptr {arg 0}, i_W HDR2"
    window g em ty (arg 0) d n
  | "span.ofPtr" ->
    // C memory: the owner is a static object (never freed), so no count is kept
    check g em (instr em $"icmp sge i_W {arg 1}, 0") "a span's length can't be negative"
    window g em ty "@zs.none" (arg 0) (arg 1)
  | "window.slice" ->
    // elements arg 1 to arg 2 (inclusive) of an array or a window: the owner moves into the
    // slice; out of range, a panic naming the range (arg 3: what is sliced)
    let t = argTy 0
    let el = if isBuf ty then bufEl g ty else winEl g ty
    let (owner, data, n) =
      if isWin t then
        let o = part g em t (arg 0) 0
        let d = part g em t (arg 0) 1
        (o, d, part g em t (arg 0) 2)
      else if isBuf t then
        // a Buffer's slice is a Buffer of its own over the same storage (with no room, so pushing
        // on it copies first): it takes a reference to the storage
        let o = bufGet em (arg 0) 0
        dupValue g em (TCon("array", [ el ])) o
        let (d, len) = dataLen g em t (arg 0)
        dropValue g em t (arg 0)
        (o, d, len)
      else
        let d = arrData g em el (arg 0)
        (arg 0, d, arrLen g em (arg 0))
    let i = arg 1
    let j = arg 2
    let j1 = instr em $"add i_W {j}, 1"
    let inRange (a: string) (b: string) = instr em $"icmp sle i_W {a}, {b}"
    let r1 = inRange "0" i
    let r2 = inRange i j1
    let ok1 = instr em $"and i1 {r1}, {r2}"
    let r3 = inRange j1 n
    let ok = instr em $"and i1 {ok1}, {r3}"
    let good = fresh em "slice"
    let bad = fresh em "badslice"
    emit em $"br i1 {ok}, label %{good}, label %{bad}"
    enter em bad
    emit em $"call void @zs_slice_fail(i_W {i}, i_W {j}, i_W {n}, i_W {arg 3})"
    emit em "unreachable"
    enter em good
    let start = instr em $"getelementptr inbounds {llty g el}, ptr {data}, i_W {i}"
    let len = instr em $"sub i_W {j1}, {i}"
    if isBuf ty then newBuffer em owner start len len else window g em ty owner start len
  | "ignore" ->
    dropValue g em (argTy 0) (arg 0)
    "zeroinitializer"
  | _ when String.startsWith "eff." op ->
    // effect handlers (Evidence): the yield state, zs_yield { state (0: not yielding, 1: the
    // continuation wanted, 2: to a clause that never resumes), the marker of the handler yielded
    // to, the clause, the continuation so far }, and the last marker made. One per thread on an
    // OS. Defined by the programs that have effects (each module that uses them, merged by the
    // linker), so the others and the runtime are as they were.
    if firstTime g "zs_yield" then
      let tls = if String.contains "-none-" g.opts.target || isWasm g then "" else "thread_local "
      helper g $"@zs_yield = linkonce_odr hidden {tls}global {{ i_W, i_W, ptr, ptr }} zeroinitializer\n"
      helper g $"@zs_yield_marker = linkonce_odr hidden {tls}global i_W 0\n"
    let field (i: int) = instr em $"getelementptr {{ i_W, i_W, ptr, ptr }}, ptr @zs_yield, i32 0, i32 {i}"
    match op with
    | "eff.state" -> instr em $"load i_W, ptr {field 0}"
    | "eff.marker" -> instr em $"load i_W, ptr {field 1}"
    | "eff.newMarker" ->
      let cur = instr em "load i_W, ptr @zs_yield_marker"
      let m = instr em $"add i_W {cur}, 1"
      emit em $"store i_W {m}, ptr @zs_yield_marker"
      m
    | "eff.start"
    | "eff.startFinal" ->
      // a yield to the handler with the marker: its clause, and the continuation so far (none
      // when the clause never resumes)
      emit em $"store i_W {arg 0}, ptr {field 1}"
      emit em $"store ptr {arg 1}, ptr {field 2}"
      emit em $"store ptr {(if op = "eff.start" then arg 2 else "null")}, ptr {field 3}"
      emit em $"store i_W {(if op = "eff.start" then 1 else 2)}, ptr {field 0}"
      "zeroinitializer"
    | "eff.takeClause" ->
      // the handler takes the clause: the yield is over
      let c = instr em $"load ptr, ptr {field 2}"
      emit em $"store ptr null, ptr {field 2}"
      emit em $"store i_W 0, ptr {field 0}"
      c
    | "eff.takeCont" ->
      let c = instr em $"load ptr, ptr {field 3}"
      emit em $"store ptr null, ptr {field 3}"
      c
    | "eff.setCont" ->
      emit em $"store ptr {arg 0}, ptr {field 3}"
      "zeroinitializer"
    | "eff.box" ->
      // the value a resumption gives, in a slot its continuation's first function reads
      let slot = "%" + fresh em "resumed"
      alloca em $"{slot} = alloca {llty g (argTy 0)}"
      emit em $"store {llty g (argTy 0)} {arg 0}, ptr {slot}"
      slot
    | "eff.unbox" -> instr em $"load {llty g ty}, ptr {arg 0}"
    | "eff.null" -> "null"
    | "eff.asClosure" -> arg 0
    // a yielding call's result: nothing, so not dropped; a yielding function's result: never read
    | "eff.forget"
    | "eff.dummy" -> "zeroinitializer"
    | _ -> panic $"unknown primitive {op}"
  | "panic" ->
    emit em $"call void @zs_panic(ptr {arg 0})"
    emit em "unreachable"
    dead em
    "poison"
  | "assert" ->
    check g em (arg 0) "assertion failed"
    "zeroinitializer"
  | _ when String.startsWith "assert:" op ->
    check g em (arg 0) ("assertion failed at " + String.sub op 7 (String.length op - 7))
    "zeroinitializer"
  | "print"
  | "println" ->
    emit em $"call void @zs_{op}(ptr {arg 0})"
    dropValue g em (argTy 0) (arg 0)
    "zeroinitializer"
  | "string" ->
    let t = argTy 0
    let lt = llty g t
    let n = tyName t
    if isVectorName n || isMaskName n then
      // <1, 2, 3, 4>: the lanes from memory, a mask's as bytes
      let (e, k, _, _) = simdShape g t
      let (lanes, v) = if isMaskName n then ($"<{k} x i8>", instr em $"zext {lt} {arg 0} to <{k} x i8>") else (lt, arg 0)
      let slot = "%" + fresh em "lanes"
      alloca em $"{slot} = alloca {lanes}"
      emit em $"store {lanes} {v}, ptr {slot}"
      let kind = List.findIndex (fun (x: string) -> x = e) [ "f32"; "f64"; "i8"; "i16"; "i32"; "i64"; "u8"; "u16"; "u32"; "u64"; "bool" ]
      instr em $"call ptr @zs_str_of_lanes(ptr {slot}, i_W {kind}, i_W {k})"
    else
      match n with
      | "string" -> arg 0
      | "bool" -> instr em $"call ptr @zs_str_of_bool(i1 zeroext {arg 0})"
      | "char" -> instr em $"call ptr @zs_str_of_char(i32 {arg 0})"
      | "f64" -> instr em $"call ptr @zs_str_of_f64(double {arg 0})"
      | "f32" -> instr em $"call ptr @zs_str_of_f32(float {arg 0})"
      | _ ->
        if isUnsigned t then
          let v = if lt = "i64" then arg 0 else instr em $"zext {lt} {arg 0} to i64"
          instr em $"call ptr @zs_str_of_u64(i64 {v})"
        else
          let v = if lt = "i64" then arg 0 else instr em $"sext {lt} {arg 0} to i64"
          instr em $"call ptr @zs_str_of_i64(i64 {v})"
  | "compare" ->
    let t = argTy 0
    let lt = llty g t
    if tyName t = "string" then
      let c = instr em $"call i_W @zs_str_cmp(ptr {arg 0}, ptr {arg 1})"
      dropValue g em t (arg 0)
      dropValue g em t (arg 1)
      c
    else
      let (gt, less) =
        if isFloat t then
          let a = instr em $"fcmp ogt {lt} {arg 0}, {arg 1}"
          (a, instr em $"fcmp olt {lt} {arg 0}, {arg 1}")
        else
          let u = if isUnsigned t then "u" else "s"
          let a = instr em $"icmp {u}gt {lt} {arg 0}, {arg 1}"
          (a, instr em $"icmp {u}lt {lt} {arg 0}, {arg 1}")
      let a = instr em $"zext i1 {gt} to i_W"
      let b = instr em $"zext i1 {less} to i_W"
      instr em $"sub i_W {a}, {b}"
  | "hash" ->
    let t = argTy 0
    let lt = llty g t
    match tyName t with
    | "string" ->
      let h = instr em $"call i_W @zs_str_hash(ptr {arg 0})"
      dropValue g em t (arg 0)
      h
    | "f64" -> foldWord g em (instr em $"bitcast double {arg 0} to i64")
    | "f32" ->
      let b = instr em $"bitcast float {arg 0} to i32"
      instr em $"zext i32 {b} to i_W"
    | _ ->
      // an i64 or u64 on a 32-bit chip: its halves folded
      if lt = wordTy g then arg 0
      else if lt = "i64" then foldWord g em (arg 0)
      else instr em $"{(if isUnsigned t || lt = "i1" then "zext" else "sext")} {lt} {arg 0} to i_W"
  | "Process.exit" ->
    emit em $"call void @zs_exit(i_W {arg 0})"
    emit em "unreachable"
    dead em
    "poison"
  | "String.ofCStr" -> instr em $"call ptr @zs_str_from_c(ptr {arg 0})"
  | _ when Map.containsKey op runtimePrims ->
    let (fn, ret, pts) = Map.find op runtimePrims
    // work for another thread: moved there (decision 75)
    if op = "Loop.blocking" || op = "Loop.spawn" then
      moveValue g em (argTy 0) (arg 0)
    let real = List.filter (fun (av: CExpr * string) -> not (isUnitTy (fst av).ty)) (List.zip args vs)
    let pass (pt: string) (av: CExpr * string) : string =
      let (a, v) = av
      if pt = "bytes" then
        if isWin a.ty || isBuf a.ty then
          let (data, len) = dataLen g em a.ty v
          $"ptr {data}, i_W {len}"
        else
          let lp = instr em $"getelementptr i8, ptr {v}, i_W HDR1"
          let n = loadLen g em lp
          let d = instr em $"getelementptr i8, ptr {v}, i_W HDR2"
          $"ptr {d}, i_W {n}"
      else
        let p = if String.endsWith "!" pt then String.sub pt 0 (String.length pt - 1) else pt
        p + " " + v
    let argv = String.join ", " (List.map2 pass pts real)
    let call = $"call {ret} @{fn}({argv})"
    let r =
      if ret = "void" then
        emit em call
        "zeroinitializer"
      else
        instr em call
    let release (k: int) (av: CExpr * string) =
      let (a, v) = av
      if not (borrowed0 && k = 0) && not (String.endsWith "!" (List.item k pts)) then
        dropValue g em a.ty v
    List.iteri release real
    r
  | "String.length" ->
    let lp = instr em $"getelementptr i8, ptr {arg 0}, i_W HDR1"
    let n = loadLen g em lp
    dropFirst ()
    n
  | "ref" ->
    let cell = $"{{ i_W, {llty g (argTy 0)} }}"
    let r = instr em $"call ptr @zs_alloc(i_W {sizeOf em cell})"
    emit em $"store i32 1, ptr {r}"
    let vp = instr em $"getelementptr {cell}, ptr {r}, i32 0, i32 1"
    emit em $"store {llty g (argTy 0)} {arg 0}, ptr {vp}"
    r
  | "ref.get" ->
    let vp = instr em $"getelementptr {{ i_W, {llty g ty} }}, ptr {arg 0}, i32 0, i32 1"
    let v = instr em $"load {llty g ty}, ptr {vp}"
    dupValue g em ty v
    dropValue g em (argTy 0) (arg 0)
    v
  | "ref.set" ->
    let vt = argTy 1
    let vp = instr em $"getelementptr {{ i_W, {llty g vt} }}, ptr {arg 0}, i32 0, i32 1"
    let old = instr em $"load {llty g vt}, ptr {vp}"
    emit em $"store {llty g vt} {arg 1}, ptr {vp}"
    dropValue g em vt old
    dropValue g em (argTy 0) (arg 0)
    "zeroinitializer"
  | "Array.length" ->
    let lp = instr em $"getelementptr {{ i_W, i_W }}, ptr {arg 0}, i32 0, i32 1"
    let n = loadLen g em lp
    dropFirst ()
    n
  | "Array.create" ->
    let el = argTy 1
    let n = arg 0
    check g em (instr em $"icmp sge i_W {n}, 0") "negative array size"
    let a = newArray g em el n
    let at = $"{{ i_W, i_W, [0 x {llty g el}] }}"
    let slot = "%" + fresh em "fill"
    alloca em $"{slot} = alloca i_W"
    emit em $"store i_W 0, ptr {slot}"
    let lc = fresh em "acond"
    let lb = fresh em "abody"
    let lend = fresh em "aend"
    emit em $"br label %{lc}"
    enter em lc
    let i = instr em $"load i_W, ptr {slot}"
    let c = instr em $"icmp slt i_W {i}, {n}"
    emit em $"br i1 {c}, label %{lb}, label %{lend}"
    enter em lb
    let ep = instr em $"getelementptr {at}, ptr {a}, i32 0, i32 2, i_W {i}"
    emit em $"store {llty g el} {arg 1}, ptr {ep}"
    dupValue g em el (arg 1)
    let i1 = instr em $"add i_W {i}, 1"
    emit em $"store i_W {i1}, ptr {slot}"
    emit em $"br label %{lc}"
    enter em lend
    // each slot took its own reference
    dropValue g em el (arg 1)
    // Buffer.create: a Buffer over all of it
    if isBuf ty then newBuffer em a (arrData g em el a) n n else a
  | "array.lit" ->
    let el =
      match ty with
      | TCon("array", [ el ]) -> el
      | _ -> panic "array literal type"
    let a = if List.isEmpty vs then "@zs.noelems" else newArray g em el $"{List.length vs}"
    let store (i: int) (v: string) =
      let ep = instr em $"getelementptr {{ i_W, i_W, [0 x {llty g el}] }}, ptr {a}, i32 0, i32 2, i_W {i}"
      emit em $"store {llty g el} {v}, ptr {ep}"
    List.iteri store vs
    a
  | "array.get" ->
    if not unchecked then
      bounds g em (arg 0) (arg 1)
    let (el, ep) = elemPtr g em (argTy 0) (arg 0) (arg 1)
    let v = instr em $"load {llty g el}, ptr {ep}"
    dupValue g em el v
    dropFirst ()
    v
  | "array.update" ->
    // Array.set a i x: a changed array (the same one when `a` was unique)
    let u = instr em $"call ptr {uniqueFn g (argTy 0) false}(ptr {arg 0})"
    bounds g em u (arg 1)
    let (el, ep) = elemPtr g em (argTy 0) u (arg 1)
    let old = instr em $"load {llty g el}, ptr {ep}"
    emit em $"store {llty g el} {arg 2}, ptr {ep}"
    dropValue g em el old
    u
  | "array.copy" ->
    match (isWin (argTy 0) || isBuf (argTy 0), isBuf ty) with
    | (false, false) -> instr em $"call ptr {uniqueFn g (argTy 0) true}(ptr {arg 0})"
    | (false, true) ->
      // Buffer.ofArray: a copy, and a Buffer over all of it
      let c = instr em $"call ptr {uniqueFn g (argTy 0) true}(ptr {arg 0})"
      let n = arrLen g em c
      newBuffer em c (arrData g em (bufEl g ty) c) n n
    | (true, _) ->
      // a window's (or a Buffer's) elements in an array of their own (a Buffer over it, for
      // Buffer.ofSpan)
      let t = argTy 0
      let el = if isBuf t then bufEl g t else winEl g t
      let (data, n) = dataLen g em t (arg 0)
      let a = newArray g em el n
      let dst = arrData g em el a
      let bytes = instr em $"mul i_W {n}, {sizeOf em (llty g el)}"
      emit em $"call void @llvm.memcpy.p0.p0.i_W(ptr {dst}, ptr {data}, i_W {bytes}, i1 false)"
      if heap g el then
        let dupAt (i: string) =
          let ep = instr em $"getelementptr inbounds {llty g el}, ptr {dst}, i_W {i}"
          dupValue g em el (instr em $"load {llty g el}, ptr {ep}")
        forEachIndex em n dupAt
      dropFirst ()
      if isBuf ty then newBuffer em a dst n n else a
  | "wrap+"
  | "wrap-"
  | "wrap*" -> instr em $"{Map.find (String.sub op 4 1) arith} {llty g ty} {arg 0}, {arg 1}"
  | "slot.take" -> arg 0
  | "mmio.read.u32"
  | "mmio.read.u8" ->
    // a hardware register: a volatile load the optimizer keeps exactly as written
    let w = if String.endsWith "u32" op then "i32" else "i8"
    let p = instr em $"inttoptr i_W {arg 0} to ptr"
    instr em $"load volatile {w}, ptr {p}"
  | "mmio.write.u32"
  | "mmio.write.u8" ->
    let w = if String.endsWith "u32" op then "i32" else "i8"
    let p = instr em $"inttoptr i_W {arg 0} to ptr"
    emit em $"store volatile {w} {arg 1}, ptr {p}"
    "zeroinitializer"
  | "Runtime.ticks" -> instr em "call i64 @zs_ticks()"
  | "Runtime.mallocs" -> instr em "call i_W @zs_mallocs()"
  | "Env.windows" -> if isWindows g then "true" else "false"
  | "Runtime.marks" -> instr em "call i_W @zs_marks()"
  | "par.fork" ->
    // a job for the thread pool: the closure's objects shared, its reference moved into the job,
    // whose runner stores its result for par.join
    let rt =
      match argTy 0 with
      | TFun(_, r, _) -> r
      | t -> panic $"par.fork of {showT g t}"
    moveValue g em (argTy 0) (arg 0)
    instr em $"call ptr @zs_par_fork(ptr {arg 0}, ptr {parRunner g rt}, i_W {sizeOf em (llty g rt)})"
  | "par.join" ->
    // the job's result (moved out), once it has run: here, or on the thread that stole it
    let rp = instr em $"call ptr @zs_par_join(ptr {arg 0})"
    let r = instr em $"load {llty g ty}, ptr {rp}"
    emit em $"call void @zs_par_free(ptr {arg 0})"
    r
  | "par.workers" -> instr em "call i_W @zs_par_workers()"
  | "atomic.make" ->
    let (st, toStore, _) = atomicRep g em (argTy 0)
    let cell = $"{{ i_W, {st} }}"
    let r = instr em $"call ptr @zs_alloc(i_W {sizeOf em cell})"
    emit em $"store i32 1, ptr {r}"
    let sv = toStore (arg 0)
    let vp = instr em $"getelementptr {cell}, ptr {r}, i32 0, i32 1"
    emit em $"store {st} {sv}, ptr {vp}"
    r
  | "atomic.get"
  | "atomic.set"
  | "atomic.exchange"
  | "atomic.cas"
  | "atomic.add" ->
    // sequentially consistent, on the value in the cell { count, value }
    let vt =
      match argTy 0 with
      | TCon("Atomic", [ x ]) -> x
      | t -> panic $"{op} of {showT g t}"
    let (st, toStore, ofStore) = atomicRep g em vt
    let vp = instr em $"getelementptr {{ i_W, {st} }}, ptr {arg 0}, i32 0, i32 1"
    let align =
      match st with
      | "i8" -> "1"
      | "i16" -> "2"
      | "i32"
      | "float" -> "4"
      | "i_W" -> "HDR1"
      | _ -> "8"
    let r =
      match op with
      | "atomic.get" -> ofStore (instr em $"load atomic {st}, ptr {vp} seq_cst, align {align}")
      | "atomic.set" ->
        let sv = toStore (arg 1)
        emit em $"store atomic {st} {sv}, ptr {vp} seq_cst, align {align}"
        "zeroinitializer"
      | "atomic.exchange" ->
        let sv = toStore (arg 1)
        ofStore (instr em $"atomicrmw xchg ptr {vp}, {st} {sv} seq_cst")
      | "atomic.cas" ->
        // compared as bits (cmpxchg takes integers): the value it held
        let (it, toBits, ofBits) =
          match st with
          | "double" -> ("i64", (fun (v: string) -> instr em $"bitcast double {v} to i64"), (fun (v: string) -> instr em $"bitcast i64 {v} to double"))
          | "float" -> ("i32", (fun (v: string) -> instr em $"bitcast float {v} to i32"), (fun (v: string) -> instr em $"bitcast i32 {v} to float"))
          | other -> (other, (fun (v: string) -> v), (fun (v: string) -> v))
        let expected = toBits (toStore (arg 1))
        let desired = toBits (toStore (arg 2))
        let pair = instr em $"cmpxchg ptr {vp}, {it} {expected}, {it} {desired} seq_cst seq_cst"
        ofStore (ofBits (instr em $"extractvalue {{ {it}, i1 }} {pair}, 0"))
      | _ ->
        // add: the new value (wrapping, as atomic arithmetic does)
        if isFloat vt then
          let old = instr em $"atomicrmw fadd ptr {vp}, {st} {arg 1} seq_cst"
          instr em $"fadd {st} {old}, {arg 1}"
        else
          let old = instr em $"atomicrmw add ptr {vp}, {st} {arg 1} seq_cst"
          instr em $"add {st} {old}, {arg 1}"
    dropValue g em (argTy 0) (arg 0)
    r
  | "mutex.make" ->
    // { count, lock, value }: what it holds is always shared
    let vt = argTy 0
    let cell = $"{{ i_W, i32, {llty g vt} }}"
    shareValue g em vt (arg 0)
    let r = instr em $"call ptr @zs_alloc(i_W {sizeOf em cell})"
    emit em $"store i32 1, ptr {r}"
    let lp = instr em $"getelementptr {cell}, ptr {r}, i32 0, i32 1"
    emit em $"store i32 0, ptr {lp}"
    let vp = instr em $"getelementptr {cell}, ptr {r}, i32 0, i32 2"
    emit em $"store {llty g vt} {arg 0}, ptr {vp}"
    r
  | "mutex.get"
  | "mutex.set"
  | "mutex.update" ->
    let vt =
      match argTy 0 with
      | TCon("Mutex", [ x ]) -> x
      | t -> panic $"{op} of {showT g t}"
    let lt = llty g vt
    let cell = $"{{ i_W, i32, {lt} }}"
    let lp = instr em $"getelementptr {cell}, ptr {arg 0}, i32 0, i32 1"
    let vp = instr em $"getelementptr {cell}, ptr {arg 0}, i32 0, i32 2"
    let r =
      match op with
      | "mutex.get" ->
        // a reference of its own, taken under the lock: a set may drop the old value
        emit em $"call void @zs_lock(ptr {lp})"
        let v = instr em $"load {lt}, ptr {vp}"
        dupValue g em vt v
        emit em $"call void @zs_unlock(ptr {lp})"
        v
      | "mutex.set" ->
        shareValue g em vt (arg 1)
        emit em $"call void @zs_lock(ptr {lp})"
        let old = instr em $"load {lt}, ptr {vp}"
        emit em $"store {lt} {arg 1}, ptr {vp}"
        emit em $"call void @zs_unlock(ptr {lp})"
        dropValue g em vt old
        "zeroinitializer"
      | _ ->
        // f's result replaces the value, under the lock (f gets the mutex's reference)
        emit em $"call void @zs_lock(ptr {lp})"
        let old = instr em $"load {lt}, ptr {vp}"
        let cp = instr em $"getelementptr {{ i_W, ptr }}, ptr {arg 1}, i32 0, i32 1"
        let code = instr em $"load ptr, ptr {cp}"
        let v = instr em $"call {lt} {code}(ptr {arg 1}, {lt} {old})"
        shareValue g em vt v
        emit em $"store {lt} {v}, ptr {vp}"
        dupValue g em vt v
        emit em $"call void @zs_unlock(ptr {lp})"
        dropValue g em (argTy 1) (arg 1)
        v
    dropValue g em (argTy 0) (arg 0)
    r
  | "chan.make" ->
    let vt =
      match ty with
      | TCon("Channel", [ x ]) -> x
      | t -> panic $"chan.make of {showT g t}"
    check g em (instr em $"icmp sge i_W {arg 0}, 0") "a channel's capacity can't be negative"
    instr em $"call ptr @zs_chan_new(i_W {arg 0}, i_W {sizeOf em (llty g vt)}, ptr {slotDrop g vt})"
  | "chan.send" ->
    // the value moves into the channel, to the one thread that receives it (the runtime copies
    // its bytes)
    let vt = argTy 1
    moveValue g em vt (arg 1)
    let slot = "%" + fresh em "sent"
    alloca em $"{slot} = alloca {llty g vt}"
    emit em $"store {llty g vt} {arg 1}, ptr {slot}"
    emit em $"call void @zs_chan_send(ptr {arg 0}, ptr {slot})"
    dropValue g em (argTy 0) (arg 0)
    "zeroinitializer"
  | "chan.receive" ->
    // Some value, or None once the channel is closed and empty
    let t =
      match ty with
      | TCon(_, [ x ]) -> x
      | _ -> panic "chan.receive"
    let slot = "%" + fresh em "received"
    alloca em $"{slot} = alloca {llty g t}"
    let ok = instr em $"call i1 @zs_chan_recv(ptr {arg 0}, ptr {slot})"
    dropValue g em (argTy 0) (arg 0)
    let (_, cases) = union g ty
    let tagOf (c: string) = List.findIndex (fun (n, _) -> n = c) cases
    let gotL = fresh em "got"
    let closedL = fresh em "closed"
    let doneL = fresh em "received"
    emit em $"br i1 {ok}, label %{gotL}, label %{closedL}"
    enter em gotL
    let x = "$recv" + fresh em ""
    let v = instr em $"load {llty g t}, ptr {slot}"
    let some = gen fx (Map.add x (Ssa v) env) false (mk (CCtor("option", tagOf "Some", [ mk (CLocal x) t ])) ty)
    let fromSome = current em
    emit em $"br label %{doneL}"
    enter em closedL
    let none = gen fx env false (mk (CCtor("option", tagOf "None", [])) ty)
    let fromNone = current em
    emit em $"br label %{doneL}"
    enter em doneL
    phi fx (llty g ty) [ (some, fromSome); (none, fromNone) ]
  | "chan.close" ->
    emit em $"call void @zs_chan_close(ptr {arg 0})"
    dropValue g em (argTy 0) (arg 0)
    "zeroinitializer"
  | _ when String.startsWith "vec." op || String.startsWith "mask." op -> simdPrim fx op args vs ty borrowed0 unchecked
  | _ when String.startsWith "llvm:" op ->
    // a target intrinsic (Simd.X86, Simd.Arm): for its architecture only
    let name = String.sub op 5 (String.length op - 5)
    let arch = if String.startsWith "llvm.x86." name then "x86_64" else "aarch64"
    let building = g.opts.arch
    let (zsName, _, _, _, need) = List.find (fun (_, i, _, _, _) -> i = name) simdIntrinsics
    if building <> arch then
      fail fx $"{zsName} is for {arch}; this build is for {building}" |> ignore
    // the CPU feature it needs: the target's baseline has it, or --cpu, or the function's
    // [<Target>] (an unknown --cpu, native say, is trusted)
    let cpuHas =
      match g.opts.cpu with
      | None -> Some [ "sse2" ]
      | Some c -> if arch = "x86_64" then Map.tryFind c x86CpuFeatures else None
    match cpuHas with
    | Some have when arch = "x86_64" && not (featuresInclude (List.append have fx.featureList) need) ->
      fail fx $"{zsName} needs the CPU feature {need}: build with --cpu (x86-64-v3, say), or mark the function [<Target \"{need}\">] (or [<Multiversion>])" |> ignore
    | _ ->
      if arch = "aarch64" && need <> "" && Option.isNone g.opts.cpu && not (List.contains need fx.featureList) then
        fail fx $"{zsName} needs the CPU feature {need}: build with --cpu, or mark the function [<Target \"{need}\">] (or [<Multiversion>])" |> ignore
    intrinsic g em name (llty g ty) (List.zip (List.map (fun (a: CExpr) -> llty g a.ty) args) vs) ""
  | "weak.new" ->
    let t = argTy 0
    if not (heap g t && llty g t = "ptr") then
      fail fx $"weak<{showT g t}> isn't possible: a weak reference is to an object (a union's cell, a ref, an array, a string, a closure or a dyn value)" |> ignore
    // the cell takes no reference to the object; the argument's is given up
    let w = instr em $"call ptr @zs_weak_new(ptr {arg 0})"
    dropValue g em t (arg 0)
    w
  | "weak.get" ->
    // Some object (with a reference of its own) while it lives, else None
    let t =
      match ty with
      | TCon(_, [ x ]) -> x
      | _ -> panic "weak.get"
    let target = instr em $"call ptr @zs_weak_target(ptr {arg 0})"
    dropValue g em (argTy 0) (arg 0)
    let (_, cases) = union g ty
    let tagOf (c: string) = List.findIndex (fun (n, _) -> n = c) cases
    let aliveL = fresh em "alive"
    let deadL = fresh em "dead"
    let gotL = fresh em "got"
    let alive = instr em $"icmp ne ptr {target}, null"
    emit em $"br i1 {alive}, label %{aliveL}, label %{deadL}"
    enter em aliveL
    let x = "$weak" + fresh em ""
    let some = gen fx (Map.add x (Ssa target) env) false (mk (CCtor("option", tagOf "Some", [ mk (CLocal x) t ])) ty)
    let fromSome = current em
    emit em $"br label %{gotL}"
    enter em deadL
    let none = gen fx env false (mk (CCtor("option", tagOf "None", [])) ty)
    let fromNone = current em
    emit em $"br label %{gotL}"
    enter em gotL
    phi fx (llty g ty) [ (some, fromSome); (none, fromNone) ]
  | "arena.with" ->
    // f () with an arena open: what it allocates comes from the arena's blocks
    emit em "call void @zs_arena_open()"
    let cp = instr em $"getelementptr {{ i_W, ptr }}, ptr {arg 0}, i32 0, i32 1"
    let code = instr em $"load ptr, ptr {cp}"
    let r = instr em $"call {llty g ty} {code}(ptr {arg 0}, {{}} zeroinitializer)"
    emit em "call void @zs_arena_close()"
    dropValue g em (argTy 0) (arg 0)
    r
  // a function named for a vtable
  | _ when String.startsWith "fn:" op -> "zeroinitializer"
  | _ when String.startsWith "dyn.box:" op ->
    // { count, vtable, value }: the value moves in; the vtable frees it, then has the trait's
    // methods for the value's type
    let t = argTy 0
    let cell = $"{{ i_W, ptr, {llty g t} }}"
    let entryOf (a: CExpr) : string =
      match a.k with
      | CPrim(f, _) -> String.sub f 3 (String.length f - 3)
      | _ -> panic "vtable entry"
    let vt = vtable g (String.sub op 8 (String.length op - 8)) t (List.map entryOf (List.tail args))
    let c = instr em $"call ptr @zs_alloc(i_W {sizeOf em cell})"
    emit em $"store i32 1, ptr {c}"
    let vp = instr em $"getelementptr {cell}, ptr {c}, i32 0, i32 1"
    emit em $"store ptr {vt}, ptr {vp}"
    let xp = instr em $"getelementptr {cell}, ptr {c}, i32 0, i32 2"
    emit em $"store {llty g t} {arg 0}, ptr {xp}"
    c
  | "dyn.unbox" ->
    // the value a dyn holds, with a reference of its own; the dyn's is given up
    let vp = instr em $"getelementptr {{ i_W, ptr, {llty g ty} }}, ptr {arg 0}, i32 0, i32 2"
    let v = instr em $"load {llty g ty}, ptr {vp}"
    dupValue g em ty v
    dropValue g em (argTy 0) (arg 0)
    v
  | _ when String.startsWith "dyn.call:" op ->
    // the method at this index of the vtable, given the dyn (whose reference it takes) and the
    // other arguments
    let i = toInt (String.sub op 9 (String.length op - 9))
    let vtp = instr em $"getelementptr {{ i_W, ptr }}, ptr {arg 0}, i32 0, i32 1"
    let vt = instr em $"load ptr, ptr {vtp}"
    let ep = instr em $"getelementptr ptr, ptr {vt}, i32 {i + 1}"
    let entry = instr em $"load ptr, ptr {ep}"
    let argv = String.join ", " (List.map (typed g) (List.zip args vs))
    instr em $"call {llty g ty} {entry}({argv})"
  // raw pointers (ptr<T>): T is C data (the type checker allows nothing else), so nothing is
  // counted
  | "ptr.read" ->
    if heap g ty then
      fail fx $"Ptr.read: a ptr<{showT g ty}> can't be read, since {showT g ty} is reference counted" |> ignore
    if llty g ty = "{}" then "zeroinitializer" else instr em $"load {llty g ty}, ptr {arg 0}"
  | "ptr.write" ->
    let vt = argTy 1
    if heap g vt then
      fail fx $"Ptr.write: a ptr<{showT g vt}> can't be written, since {showT g vt} is reference counted" |> ignore
    if llty g vt <> "{}" then
      emit em $"store {llty g vt} {arg 1}, ptr {arg 0}"
    "zeroinitializer"
  | "ptr.add" ->
    let el =
      match argTy 0 with
      | TCon("ptr", [ x ]) -> x
      | _ -> panic "ptr.add"
    if llty g el = "{}" then arg 0 else instr em $"getelementptr {llty g el}, ptr {arg 0}, i_W {arg 1}"
  | "ptr.null" -> "null"
  | "layout.sizeof"
  | "layout.alignof"
  | "layout.offsetof" ->
    // a layout fact in a generic function (0004), its type settled now: the type of the null
    // ptr<T> it carries; the field's index after it
    let t =
      match argTy 0 with
      | TCon("ptr", [ x ]) -> x
      | x -> panic $"{op} of {showT g x}"
    let index =
      match (List.item 1 args).k with
      | CInt i -> int i
      | _ -> 0
    let word = pointerBytes g
    let n =
      match op with
      | "layout.sizeof" -> Option.map fst (Types.Repr.layout g.v g.types word t)
      | "layout.alignof" -> Option.map snd (Types.Repr.layout g.v g.types word t)
      | _ -> Types.Repr.offsetOf g.v g.types word t index
    match n with
    | Some k -> $"{k}"
    | None -> panic $"{op} of {showT g t}: its layout isn't known"
  | "ptr.isNull" -> instr em $"icmp eq ptr {arg 0}, null"
  | "ptr.cast" -> arg 0
  | "ptr.alloc" ->
    let el =
      match ty with
      | TCon("ptr", [ x ]) -> x
      | _ -> panic "ptr.alloc"
    instr em $"call ptr @zs_ptr_alloc(i_W {arg 0}, i_W {sizeOf em (llty g el)})"
  | "ptr.free" ->
    emit em $"call void @zs_ptr_free(ptr {arg 0})"
    "zeroinitializer"
  | "fnptr.call" ->
    // a C function pointer called with C's conventions, as an extern is
    let pars =
      match argTy 0 with
      | TCon("fnptr", [ fn ]) -> List.filter (fun p -> not (isUnitTy p)) (fst (splitFun fn))
      | _ -> panic "fnptr.call"
    let s : ExternSig = { pars = pars; ret = ty; variadic = false }
    cCall fx (arg 0) s (List.tail args) (List.tail vs)
  | "Runtime.allocations" -> instr em "call i_W @zs_allocations()"
  // no cell to build in (a jump to a join point)
  | "token.null" -> "null"
  | "Math.sqrt" ->
    // one instruction where the hardware has it (x86-64, aarch64, the M4's FPU)
    let lt = llty g (argTy 0)
    instr em $"call {lt} @llvm.sqrt.{(if lt = "double" then "f64" else "f32")}({lt} {arg 0})"
  | "array.set" ->
    bounds g em (arg 0) (arg 1)
    let (el, ep) = elemPtr g em (argTy 0) (arg 0) (arg 1)
    let old = instr em $"load {llty g el}, ptr {ep}"
    emit em $"store {llty g el} {arg 2}, ptr {ep}"
    dropValue g em el old
    dropValue g em (argTy 0) (arg 0)
    "zeroinitializer"
  | "format" ->
    // Format.format of a number: the runtime's, at the number's width
    let t = argTy 0
    let lt = llty g t
    let r =
      if isFloat t then
        let x = if lt = "float" then instr em $"fpext float {arg 0} to double" else arg 0
        instr em $"call ptr @zs_format_float(double {x}, ptr {arg 1})"
      else
        let bits = bitsOf lt
        let v = if bits < 64 then instr em $"{(if isUnsigned t then "zext" else "sext")} {lt} {arg 0} to i64" else arg 0
        instr em $"call ptr @zs_format_int(i64 {v}, i64 {bits}, i1 zeroext {(if isUnsigned t then "true" else "false")}, ptr {arg 1})"
    dropValue g em (argTy 1) (arg 1)
    r
  | "int.parse" ->
    // Int.parseRadix's: whether the text is a number of the type, and the number
    let el =
      match ty with
      | TTuple [ _; x ] -> x
      | t -> panic $"int.parse of {showT g t}"
    let lt = llty g el
    let bits = bitsOf lt
    let slot = "%" + fresh em "parsed"
    alloca em $"{slot} = alloca i64"
    let radix = if llty g (argTy 0) = "i64" then arg 0 else instr em $"sext {llty g (argTy 0)} {arg 0} to i64"
    let ok = instr em $"call zeroext i1 @zs_parse_int(ptr {arg 1}, i64 {radix}, i1 zeroext {(if isUnsigned el then "true" else "false")}, i64 {bits}, ptr {slot})"
    let v0 = instr em $"load i64, ptr {slot}"
    let v = if bits < 64 then instr em $"trunc i64 {v0} to {lt}" else v0
    dropValue g em (argTy 1) (arg 1)
    let pair = instr em $"insertvalue {llty g ty} poison, i1 {ok}, 0"
    instr em $"insertvalue {llty g ty} {pair}, {lt} {v}, 1"
  | "float.toBits" -> instr em $"bitcast double {arg 0} to i64"
  | "float.ofBits" -> instr em $"bitcast i64 {arg 0} to double"
  | "float.parse" ->
    // Float.parse's: whether the text is a number, and the number
    let el =
      match ty with
      | TTuple [ _; x ] -> x
      | t -> panic $"float.parse of {showT g t}"
    let slot = "%" + fresh em "parsed"
    alloca em $"{slot} = alloca double"
    let ok = instr em $"call zeroext i1 @zs_parse_float(ptr {arg 0}, ptr {slot})"
    let v0 = instr em $"load double, ptr {slot}"
    let v = if llty g el = "float" then instr em $"fptrunc double {v0} to float" else v0
    dropValue g em (argTy 0) (arg 0)
    let pair = instr em $"insertvalue {llty g ty} poison, i1 {ok}, 0"
    instr em $"insertvalue {llty g ty} {pair}, {llty g el} {v}, 1"
  | "conv" ->
    let src = argTy 0
    let ls = llty g src
    let ld = llty g ty
    let v = arg 0
    if ls = ld && isFloat src = isFloat ty then v
    else if isFloat src && isFloat ty then instr em $"{(if ls = "float" then "fpext" else "fptrunc")} {ls} {v} to {ld}"
    else if isFloat src then instr em $"{(if isUnsigned ty then "fptoui" else "fptosi")} {ls} {v} to {ld}"
    else if isFloat ty then instr em $"{(if isUnsigned src then "uitofp" else "sitofp")} {ls} {v} to {ld}"
    else if bitsOf ls > bitsOf ld then instr em $"trunc {ls} {v} to {ld}"
    else if bitsOf ls < bitsOf ld then instr em $"{(if isUnsigned src then "zext" else "sext")} {ls} {v} to {ld}"
    else v
  | _ -> panic $"unknown primitive {op}"

// ------------------------------------------------------------ functions

// the types a wait gives, each once, in order
let private distinctTypes (g: G) (ts: list<Ty>) : list<Ty> =
  let keep (acc: list<string * Ty>) (t: Ty) =
    let key = showF g t
    if List.exists (fun (k, _) -> k = key) acc then acc else List.append acc [ (key, t) ]
  List.map snd (List.fold keep [] ts)

/// f's definition, named name, compiled for the CPU features (LLVM's target-features: avx2,fma
/// becomes +avx2,+fma; "" for the baseline).
let genFunAs (g: G) (f: MFun) (name: string) (features: string) =
  let em = emitter ()
  // a task's state machine: f waits (task.suspend, task.abandon), so it's a coroutine
  let waitTypes = waitsIn f.body
  let coro = not (List.isEmpty waitTypes)
  // a task's work, which gives its result to what waits for it: its wrapper returns unit
  if coro && llty g f.ret <> "{}" then
    panic $"Codegen: {f.name} waits but returns {showT g f.ret}"
  let featureList = if features = "" then [] else List.map String.trim (String.split "," features)
  // this function's debug scope
  let sp =
    if g.opts.debugInfo then
      let file = diFile g f.file
      meta g $"distinct !DISubprogram(name: \"{f.name}\", scope: {file}, file: {file}, line: {f.line}, type: {noTypes g}, scopeLine: {f.line}, spFlags: DISPFlagDefinition, unit: {compileUnit g})"
    else
      ""
  if g.opts.debugInfo then
    setDbg em (diLoc g (max 1 f.line) sp)
  let data : FData =
    { g = g
      em = em
      f = f
      sp = sp
      line = ref f.line
      lastLine = ref f.line
      at = ref f.line
      featureList = featureList
      selfProto = proto g f
      joinBlocks = ref Map.empty
      uniqueSlots = ref Set.empty }
  let fx = F data
  let env = List.fold (fun (m: Map<string, Binding>) (x, _) -> Map.add x (Ssa("%p." + x)) m) Map.empty f.pars
  List.iteri (fun i (x, t) -> declareVar fx x t ("%p." + x) None (i + 1)) f.pars
  if coro then
    // the face (closure header, the coroutine's handle, the largest result slot) rounded to 64
    // bytes, then the coroutine's frame; the ramp's own reference, which the wrapper below gives
    // up
    faceCommon g
    emit em "%coro.id = call token @llvm.coro.id(i32 16, ptr null, ptr null, ptr null)"
    let sizes = List.map (fun (t: Ty) -> sizeOf em $"{{ i_W, ptr, ptr, ptr, {llty g t} }}") (distinctTypes g waitTypes)
    let larger (a: string) (b: string) =
      let gt = instr em $"icmp ugt i_W {a}, {b}"
      instr em $"select i1 {gt}, i_W {a}, i_W {b}"
    let largest = List.reduce larger sizes
    let rounded = instr em $"add i_W {largest}, 63"
    let head = instr em $"and i_W {rounded}, -64"
    let size = instr em "call i_W @llvm.coro.size.i_W()"
    let total = instr em $"add i_W {size}, {head}"
    emit em $"%face = call ptr @zs_coro_alloc(i_W {total})"
    emit em "store i32 1, ptr %face"
    let cp = instr em "getelementptr { i_W, ptr, ptr }, ptr %face, i32 0, i32 1"
    emit em $"store ptr null, ptr {cp}"
    let ip = instr em "getelementptr { i_W, ptr, ptr }, ptr %face, i32 0, i32 2"
    emit em $"store ptr @zs.faceinfo.none, ptr {ip}"
    let mem = instr em $"getelementptr i8, ptr %face, i_W {head}"
    emit em $"%coro.hdl = call ptr @llvm.coro.begin(token %coro.id, ptr {mem})"
    let hp = instr em "getelementptr { i_W, ptr, ptr, ptr }, ptr %face, i32 0, i32 3"
    emit em $"store ptr %coro.hdl, ptr {hp}"
  let v = gen fx env (not coro) f.body
  let rt = llty g f.ret
  if g.opts.debugInfo then
    // returning belongs to the last statement, not the header
    setDbg em (diLoc g (max 1 fx.lastLine.Value) sp)
  if coro then
    // the work has given its result to what waits for it: the final suspension, where the face's
    // last reference destroys the coroutine
    let fin = instr em "call i8 @llvm.coro.suspend(token none, i1 true)"
    emit em $"switch i8 {fin}, label %coro.exit [ i8 0, label %coro.never i8 1, label %coro.destroy ]"
    enter em "coro.never"
    emit em "unreachable"
    enter em "coro.destroy"
    emit em "%coro.freed = call ptr @llvm.coro.free(token %coro.id, ptr %coro.hdl)"
    emit em "br label %coro.exit"
    enter em "coro.exit"
    emit em "call void @llvm.coro.end(ptr %coro.hdl, i1 false, token none)"
    emit em "ret ptr %face"
  else
    emit em $"ret {rt} {v}"
  let ps = String.join ", " (List.map (fun (x, t) -> $"{llty g t} %p.{x}") f.pars)
  let dbg = if g.opts.debugInfo then " !dbg " + sp else ""
  // a function taking a function (List.map, a lifted loop over a closure): inlining it lets the
  // closure call become direct, and the closure's allocation disappear
  let takesFunction (pt: string * Ty) =
    match snd pt with
    | TFun _ -> true
    | _ -> false
  let hint = if List.exists takesFunction f.pars then " inlinehint" else ""
  // called from another part: external (hidden in the program); a copy: one of the same; a
  // version: only its dispatcher calls it
  let linkage =
    if name <> f.name then
      "internal"
    else
      match g.part with
      | Some p -> if p.copies then "weak_odr hidden" else if Set.contains f.name p.called then "hidden" else "internal"
      | None -> "internal"
  let feats = if features = "" then "" else " \"target-features\"=\"" + String.join "," (List.map (fun (x: string) -> "+" + String.trim x) (String.split "," features)) + "\""
  if coro then
    // the coroutine, and the function as callers know it: it starts the coroutine and gives up
    // the ramp's reference to the face
    let coroSym = "@\"zs." + name + ".coro\""
    Buffer.push $"define internal ptr {coroSym}({ps}) presplitcoroutine{feats}{dbg} {{\n{bodyOf em}}}\n\n" g.funcs
    let argv = String.join ", " (List.map (fun (x, t) -> $"{llty g t} %p.{x}") f.pars)
    Buffer.push $"define {linkage} {rt} {sym g name}({ps}){feats} {{\nentry:\n  %face = call ptr {coroSym}({argv})\n  call void @zs.drop.clo(ptr %face)\n  ret {rt} zeroinitializer\n}}\n\n" g.funcs
  else
    Buffer.push $"define {linkage} {rt} {sym g name}({ps}){hint}{feats}{dbg} {{\n{bodyOf em}}}\n\n" g.funcs

/// A [<Multiversion>] function: a version for each set of features, and one for the baseline; its
/// own name is a dispatcher that picks one the first time (the first the CPU has, in order) and
/// calls it.
let multiversion (g: G) (f: MFun) (versions: list<string>) =
  for ver in versions do
    genFunAs g f (f.name + "." + ver) ver
  genFunAs g f (f.name + ".default") ""
  let rt = llty g f.ret
  let ps = String.join ", " (List.map (fun (x, t) -> $"{llty g t} %p.{x}") f.pars)
  let slot = $"@\"mv.{f.name}\""
  topLine g $"{slot} = internal global ptr null"
  let em = emitter ()
  let cached = instr em $"load atomic ptr, ptr {slot} monotonic, align HDR1"
  let none = instr em $"icmp eq ptr {cached}, null"
  emit em $"br i1 {none}, label %pick, label %go"
  enter em "pick"
  let choose (rest: string) (ver: string) : string =
    let name = $"@\"cpu.{ver}\""
    if firstTime g name then
      topLine g $"{name} = private unnamed_addr constant [{String.length ver + 1} x i8] c\"{ver}\\00\""
    let ok = instr em $"call i1 @zs_cpu_supports(ptr {name})"
    instr em $"select i1 {ok}, ptr {sym g (f.name + "." + ver)}, ptr {rest}"
  let chosen = List.fold choose (sym g (f.name + ".default")) (List.rev versions)
  emit em $"store atomic ptr {chosen}, ptr {slot} monotonic, align HDR1"
  emit em "br label %go"
  enter em "go"
  let p = instr em $"phi ptr [ {cached}, %entry ], [ {chosen}, %pick ]"
  let argv = String.join ", " (List.map (fun (x, t) -> $"{llty g t} %p.{x}") f.pars)
  let r = instr em $"musttail call {rt} {p}({argv})"
  emit em $"ret {rt} {r}"
  let linkage =
    match g.part with
    | Some pt -> if pt.copies then "weak_odr hidden" else if Set.contains f.name pt.called then "hidden" else "internal"
    | None -> "internal"
  Buffer.push $"define {linkage} {rt} {sym g f.name}({ps}) {{\n{bodyOf em}}}\n\n" g.funcs

/// A function's code: as it is, for its [<Target>] features, or its [<Multiversion>] versions.
let genFun (g: G) (f: MFun) =
  match Map.tryFind (baseFunName f.name) g.opts.targets with
  | Some("multiversion" :: versions) when not (String.contains "$" f.name) -> multiversion g f versions
  | Some [ "target"; features ] -> genFunAs g f f.name features
  | _ -> genFunAs g f f.name ""
