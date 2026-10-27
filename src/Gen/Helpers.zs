/// The helper functions code generation makes once per type and uses everywhere (the F# compiler's
/// Codegen, its second part): dup, drop, share and move for each type, a Buffer's growth, arrays'
/// copy on write, closures' code and descriptions, vtables, a task's face, and C's callbacks and
/// handles.
open Types.Ty
open Types.Repr
open Core.Ir
open Core.Program
open Emit
open Layout

// ------------------------------------------------------------ reference counting

/// A dup of the value, when it holds a count.
let rec dupValue (g: G) (em: Emitter) (t: Ty) (v: string) =
  if heap g t then
    match llty g t with
    | "ptr" -> emit em $"call void @zs.dup(ptr {v})"
    | lt -> emit em $"call void {structHelper g "dup" t}({lt} {v})"

/// A drop of the value, when it holds a count.
and dropValue (g: G) (em: Emitter) (t: Ty) (v: string) =
  if heap g t then
    emit em $"call void {dropFn g t}({llty g t} {v})"

// a struct value's fields: a tuple's, a fixed array's elements, a record's
and private structFields (g: G) (t: Ty) : list<Ty> =
  match t with
  | TTuple ts -> ts
  | TCon("fixed", [ el; TCon(n, []) ]) -> List.replicate (toInt n) el
  | TCon(n, args) ->
    match (Map.find n g.types).def with
    | RecordDef fs -> List.map (fun (_, ft) -> substGen g args ft) fs
    | UnionDef _
    | CUnionDef _ -> []
  | _ -> []

/// dup or drop for a struct value: applied to each field that holds a count.
and structHelper (g: G) (kind: string) (t: Ty) : string =
  let name = $"@\"{kind}.{showF g t}\""
  if firstTime g name then
    let em = emitter ()
    let one (i: int) (ft: Ty) =
      if heap g ft then
        let f = instr em $"extractvalue {llty g t} %v, {i}"
        if kind = "dup" then dupValue g em ft f else dropValue g em ft f
    List.iteri one (structFields g t)
    emit em "ret void"
    helper g $"define private void {name}({llty g t} %v) {{\n{bodyOf em}}}\n\n"
  name

// walk.T for a struct value: each field that holds a count walked, sharing or moving (%move)
and private structWalk (g: G) (t: Ty) : string =
  let name = $"@\"walk.{showF g t}\""
  if firstTime g name then
    let em = emitter ()
    let one (i: int) (ft: Ty) =
      if heap g ft then
        walkIn g em ft (instr em $"extractvalue {llty g t} %v, {i}") "%move"
    List.iteri one (structFields g t)
    emit em "ret void"
    helper g $"define private void {name}({llty g t} %v, i1 %move) {{\n{bodyOf em}}}\n\n"
  name

/// Marks a value's objects shared before it crosses to another thread (DESIGN §7.1): a
/// thread-local count n becomes -n, which every thread then changes atomically. The walk stops at
/// static objects and at shared ones, whose objects are shared already.
and shareValue (g: G) (em: Emitter) (t: Ty) (v: string) = walkIn g em t v "false"

/// Moves a value to another thread (decision 75): an object the moved value holds the only
/// reference to (a count of 1) stays thread-local, the receiver's now, and what it holds moves in
/// turn; an object another reference reaches (a count above 1) is marked shared with everything
/// under it, as shareValue does. The crossing has consumed the value, so a count of 1 means the
/// sender holds nothing of it.
and moveValue (g: G) (em: Emitter) (t: Ty) (v: string) = walkIn g em t v "true"

// a value's walk, sharing it or moving it as `move` (an i1: true, false, or a walk's own %move)
// says
and walkIn (g: G) (em: Emitter) (t: Ty) (v: string) (move: string) =
  if heap g t then
    match llty g t with
    | "ptr" -> emit em $"call void {walkFn g t}(ptr {v}, i1 {move})"
    | lt -> emit em $"call void {structWalk g t}({lt} {v}, i1 {move})"

/// walk.T: the walk at one object, sharing it or moving it (%move), then into what it holds the
/// same way. One function for both, so a type's walk is made once.
and walkFn (g: G) (t: Ty) : string =
  let name = $"@\"walk.{showF g t}\""
  if firstTime g name then
    let em = emitter ()
    let inner (ft: Ty) (fv: string) = walkIn g em ft fv "%move"
    match repOfUnion g t with
    | Some(Niche(_, payload)) ->
      // the payload itself, or the static @zs.none
      emit em $"musttail call void {walkFn g payload}(ptr %p, i1 %move)"
      emit em "ret void"
    | _ ->
      let rc = instr em "load atomic i32, ptr %p monotonic, align 4"
      emit em "br i1 %move, label %moving, label %sharing"
      // shared: a thread-local count n becomes -n; a static or shared object stops the walk
      enter em "sharing"
      let local = instr em $"icmp sgt i32 {rc}, 0"
      emit em $"br i1 {local}, label %mark, label %done"
      enter em "mark"
      let neg = instr em $"sub i32 0, {rc}"
      emit em $"store i32 {neg}, ptr %p"
      // ZS_STATS's count
      instr em "atomicrmw add ptr @zs_marked, i_W 1 monotonic" |> ignore
      emit em "br label %fields"
      // moved: only the moved value's, it stays local and what it holds moves; another
      // reference's, it's shared with all it holds
      enter em "moving"
      let only = instr em $"icmp eq i32 {rc}, 1"
      emit em $"br i1 {only}, label %fields, label %other"
      enter em "other"
      let more = instr em $"icmp sgt i32 {rc}, 1"
      emit em $"br i1 {more}, label %shared, label %done"
      enter em "shared"
      emit em $"musttail call void {name}(ptr %p, i1 false)"
      emit em "ret void"
      enter em "fields"
      match t with
      | TFun _ ->
        // what the closure captured: its description's walk
        let ip = instr em "getelementptr { i_W, ptr, ptr }, ptr %p, i32 0, i32 2"
        let inf = instr em $"load ptr, ptr {ip}"
        let fp = instr em $"getelementptr {{ ptr, i32, ptr, ptr, ptr }}, ptr {inf}, i32 0, i32 3"
        let f = instr em $"load ptr, ptr {fp}"
        emit em $"musttail call void {f}(ptr %p, i1 %move)"
        emit em "ret void"
      | TCon("array", [ el ]) when heap g el ->
        let lp = instr em "getelementptr { i_W, i_W }, ptr %p, i32 0, i32 1"
        let len = instr em $"load i_W, ptr {lp}"
        emit em "br label %loop"
        enter em "loop"
        let i = tmp em
        emit em $"{i} = phi i_W [ 0, %fields ], [ %next, %body ]"
        let c = instr em $"icmp slt i_W {i}, {len}"
        emit em $"br i1 {c}, label %body, label %done"
        enter em "body"
        let ep = instr em $"getelementptr {{ i_W, i_W, [0 x {llty g el}] }}, ptr %p, i32 0, i32 2, i_W {i}"
        inner el (instr em $"load {llty g el}, ptr {ep}")
        emit em $"%next = add i_W {i}, 1"
        emit em "br label %loop"
      | TCon(n, _) when isUnionType g n ->
        // the case's fields; the last pointer field by a tail call, so a long list is walked in a
        // loop
        let (_, cases) = union g t
        let withRefs = List.filter (fun (_, (_, fs)) -> List.exists (heap g) fs) (List.indexed cases)
        if tagged g t then
          let tag = loadTag g em "%p" None
          let targets = String.join " " (List.map (fun (i, _) -> $"i32 {i}, label %case{i}") withRefs)
          emit em $"switch i32 {tag}, label %done [ {targets} ]"
        else
          match withRefs with
          | (i, _) :: _ -> emit em $"br label %case{i}"
          | [] -> emit em "br label %done"
        for (i, (_, fs)) in withRefs do
          enter em $"case{i}"
          let cell = cellTy g t i
          let load (jf: int * Ty) =
            let (j, ft) = jf
            let fp = instr em $"getelementptr {cell}, ptr %p, i32 0, i32 {cellField g t j}"
            (ft, instr em $"load {llty g ft}, ptr {fp}")
          let refs = List.map load (List.filter (fun (_, ft) -> heap g ft) (List.indexed fs))
          let (lt, lv) = List.last refs
          for (ft, fv) in List.take (List.length refs - 1) refs do
            inner ft fv
          if llty g lt = "ptr" then
            emit em $"musttail call void {walkFn g lt}(ptr {lv}, i1 %move)"
            emit em "ret void"
          else
            inner lt lv
            emit em "br label %done"
      // a string; an Atomic, a Mutex or a Channel, whose contents are shared already
      | _ -> emit em "br label %done"
    enter em "done"
    emit em "ret void"
    helper g $"define private void {name}(ptr %p, i1 %move) {{\n{bodyOf em}}}\n\n"
  name

/// A Buffer's functions that change its length, per element type (Core's bufferDef): push,
/// removeLast, truncate, and blit (a memmove that keeps the counts right). The storage's own
/// length counts its slots holding a value: a slot past the Buffer's length may still hold one
/// (left by removeLast while the storage was shared), dropped when it's written again or when the
/// storage is freed.
and bufferFn (g: G) (kind: string) (el: Ty) : string =
  let name = $"@\"zs.buffer.{kind}.{showF g el}\""
  if firstTime g name then
    let em = emitter ()
    let elt = llty g el
    let at = $"{{ i_W, i_W, [0 x {elt}] }}"
    let field (k: int) = instr em $"getelementptr {{ i_W, {{ ptr, ptr, i_W, i_W }} }}, ptr %c, i32 0, i32 1, i32 {k}"
    let load (t: string) (p: string) = instr em $"load {t}, ptr {p}"
    let lenOf (a: string) = instr em $"getelementptr {{ i_W, i_W }}, ptr {a}, i32 0, i32 1"
    let startOf (a: string) = instr em $"getelementptr {at}, ptr {a}, i32 0, i32 2, i_W 0"
    let slot (data: string) (i: string) = instr em $"getelementptr {elt}, ptr {data}, i_W {i}"
    let arr = TCon("array", [ el ])
    // whether the Buffer's storage is its alone and it windows it from the start: then its values
    // move, else they're copied
    let alone (owner: string) (data: string) =
      let rc = instr em (if g.opts.threaded then $"load atomic i32, ptr {owner} monotonic, align 4" else $"load i32, ptr {owner}")
      let only = instr em $"icmp eq i32 {rc}, 1"
      let s = startOf owner
      let atStart = instr em $"icmp eq ptr {s}, {data}"
      instr em $"and i1 {only}, {atStart}"
    // drops the values in slots from to until - 1 (a loop; nothing for plain values)
    let dropSlots (data: string) (from: string) (until: string) (tag: string) =
      if heap g el then
        let i = "%" + fresh em "di"
        alloca em $"{i} = alloca i_W"
        emit em $"store i_W {from}, ptr {i}"
        emit em $"br label %{tag}.cond"
        enter em (tag + ".cond")
        let k = load "i_W" i
        let c = instr em $"icmp slt i_W {k}, {until}"
        emit em $"br i1 {c}, label %{tag}.body, label %{tag}.end"
        enter em (tag + ".body")
        dropValue g em el (load elt (slot data k))
        let k1 = instr em $"add i_W {k}, 1"
        emit em $"store i_W {k1}, ptr {i}"
        emit em $"br label %{tag}.cond"
        enter em (tag + ".end")
    match kind with
    | "push" ->
      let lenp = field 2
      let capp = field 3
      let len = load "i_W" lenp
      let cap = load "i_W" capp
      let full = instr em $"icmp eq i_W {len}, {cap}"
      emit em $"br i1 {full}, label %grow, label %put"
      // no room: storage twice as large (4 at least), the values moved or copied into it
      enter em "grow"
      let twice = instr em $"shl i_W {cap}, 1"
      let small = instr em $"icmp ult i_W {twice}, 4"
      let ncap = instr em $"select i1 {small}, i_W 4, i_W {twice}"
      let size = instr em $"mul i_W {ncap}, {sizeOf em elt}"
      let bytes = instr em $"add i_W HDR2, {size}"
      let made = instr em $"call ptr @zs_alloc(i_W {bytes})"
      emit em $"store i32 1, ptr {made}"
      emit em $"store i_W {len}, ptr {lenOf made}"
      let ownerp = field 0
      let datap = field 1
      let old = load "ptr" ownerp
      let data = load "ptr" datap
      let into = startOf made
      let n = instr em $"mul i_W {len}, {sizeOf em elt}"
      emit em $"call void @llvm.memcpy.p0.p0.i_W(ptr {into}, ptr {data}, i_W {n}, i1 false)"
      if heap g el then
        let al = alone old data
        emit em $"br i1 {al}, label %move, label %copy"
        // the old storage gives its values up: its length 0, so freeing it drops none
        enter em "move"
        emit em $"store i_W 0, ptr {lenOf old}"
        emit em "br label %release"
        enter em "copy"
        let i = "%" + fresh em "ci"
        alloca em $"{i} = alloca i_W"
        emit em $"store i_W 0, ptr {i}"
        emit em "br label %copy.cond"
        enter em "copy.cond"
        let k = load "i_W" i
        let c = instr em $"icmp slt i_W {k}, {len}"
        emit em $"br i1 {c}, label %copy.body, label %release"
        enter em "copy.body"
        dupValue g em el (load elt (slot into k))
        let k1 = instr em $"add i_W {k}, 1"
        emit em $"store i_W {k1}, ptr {i}"
        emit em "br label %copy.cond"
        enter em "release"
      else
        emit em "br label %release"
        enter em "release"
      dropValue g em arr old
      emit em $"store ptr {made}, ptr {ownerp}"
      emit em $"store ptr {into}, ptr {datap}"
      emit em $"store i_W {ncap}, ptr {capp}"
      emit em "br label %put"
      // room: the value in the next slot (a value left there dropped first)
      enter em "put"
      let owner = load "ptr" (field 0)
      let data2 = load "ptr" (field 1)
      let hwp = lenOf owner
      let hw = load "i_W" hwp
      let sp = slot data2 len
      if heap g el then
        let stale = instr em $"icmp ult i_W {len}, {hw}"
        emit em $"br i1 {stale}, label %stale, label %store"
        enter em "stale"
        dropValue g em el (load elt sp)
        emit em "br label %store"
        enter em "store"
      emit em $"store {elt} %v, ptr {sp}"
      let next = instr em $"add i_W {len}, 1"
      emit em $"store i_W {next}, ptr {lenp}"
      let grew = instr em $"icmp ult i_W {hw}, {next}"
      let hw2 = instr em $"select i1 {grew}, i_W {next}, i_W {hw}"
      emit em $"store i_W {hw2}, ptr {hwp}"
      emit em "ret void"
      helper g $"define private void {name}(ptr %c, {elt} %v) {{\n{bodyOf em}}}\n\n"
    | "removeLast" ->
      let lenp = field 2
      let len = load "i_W" lenp
      let empty = instr em $"icmp eq i_W {len}, 0"
      emit em $"br i1 {empty}, label %empty, label %take"
      enter em "empty"
      panicWith g em "Buffer.removeLast of an empty Buffer"
      enter em "take"
      let n = instr em $"sub i_W {len}, 1"
      emit em $"store i_W {n}, ptr {lenp}"
      let owner = load "ptr" (field 0)
      let data = load "ptr" (field 1)
      let v = load elt (slot data n)
      let s = startOf owner
      let atStart = instr em $"icmp eq ptr {s}, {data}"
      if heap g el then
        let al = alone owner data
        emit em $"br i1 {al}, label %move, label %keep"
        // the value leaves the storage, and so do the values left past it
        enter em "move"
        let hwp = lenOf owner
        dropSlots data len (load "i_W" hwp) "past"
        emit em $"store i_W {n}, ptr {hwp}"
        emit em "br label %done"
        // shared: the slot keeps its reference, the result has one of its own
        enter em "keep"
        dupValue g em el v
        emit em "br label %done"
        enter em "done"
      // a Buffer not at its storage's start keeps no room (pushing on it copies)
      let capp = field 3
      let capv = load "i_W" capp
      let sel = instr em $"select i1 {atStart}, i_W {capv}, i_W {n}"
      emit em $"store i_W {sel}, ptr {capp}"
      emit em $"ret {elt} {v}"
      helper g $"define private {elt} {name}(ptr %c) {{\n{bodyOf em}}}\n\n"
    | "truncate" ->
      let lenp = field 2
      let len = load "i_W" lenp
      let neg = instr em "icmp slt i_W %n, 0"
      emit em $"br i1 {neg}, label %bad, label %check"
      enter em "bad"
      panicWith g em "Buffer.truncate to a negative length"
      enter em "check"
      let shorter = instr em $"icmp slt i_W %n, {len}"
      emit em $"br i1 {shorter}, label %cut, label %same"
      enter em "same"
      emit em "ret void"
      enter em "cut"
      emit em $"store i_W %n, ptr {lenp}"
      let owner = load "ptr" (field 0)
      let data = load "ptr" (field 1)
      let s = startOf owner
      let atStart = instr em $"icmp eq ptr {s}, {data}"
      if heap g el then
        let al = alone owner data
        emit em $"br i1 {al}, label %drop, label %done"
        enter em "drop"
        let hwp = lenOf owner
        dropSlots data "%n" (load "i_W" hwp) "past"
        emit em $"store i_W %n, ptr {hwp}"
        emit em "br label %done"
        enter em "done"
      let capp = field 3
      let capv = load "i_W" capp
      let sel = instr em $"select i1 {atStart}, i_W {capv}, i_W %n"
      emit em $"store i_W {sel}, ptr {capp}"
      emit em "ret void"
      helper g $"define private void {name}(ptr %c, i_W %n) {{\n{bodyOf em}}}\n\n"
    | _ ->
      // blit: n elements from src[i] to dst[j], both in range
      let inRange (len: string) (at0: string) =
        let ok1 = instr em $"icmp sle i_W 0, {at0}"
        let ok2 = instr em "icmp sle i_W 0, %n"
        let sum = instr em $"add i_W {at0}, %n"
        let ok3 = instr em $"icmp sle i_W {sum}, {len}"
        let ok12 = instr em $"and i1 {ok1}, {ok2}"
        instr em $"and i1 {ok12}, {ok3}"
      let r1 = inRange "%sl" "%i"
      let r2 = inRange "%dl" "%j"
      let ok = instr em $"and i1 {r1}, {r2}"
      emit em $"br i1 {ok}, label %go, label %bad"
      enter em "bad"
      panicWith g em "Buffer.blit out of range"
      enter em "go"
      let src = slot "%sd" "%i"
      let dst = slot "%dd" "%j"
      if heap g el then
        // each value: a reference taken for its new slot, the slot's old one dropped (through a
        // copy of the values, so overlapping windows work as memmove)
        let bytes = instr em $"mul i_W %n, {sizeOf em elt}"
        // (after the allocation's header word, which zs_free checks)
        let total = instr em $"add i_W {bytes}, HDR1"
        let block = instr em $"call ptr @zs_alloc(i_W {total})"
        let copied = instr em $"getelementptr i8, ptr {block}, i_W HDR1"
        emit em $"call void @llvm.memcpy.p0.p0.i_W(ptr {copied}, ptr {src}, i_W {bytes}, i1 false)"
        let i = "%" + fresh em "bi"
        alloca em $"{i} = alloca i_W"
        emit em $"store i_W 0, ptr {i}"
        emit em "br label %each.cond"
        enter em "each.cond"
        let k = load "i_W" i
        let c = instr em $"icmp slt i_W {k}, %n"
        emit em $"br i1 {c}, label %each.body, label %each.end"
        enter em "each.body"
        let v = load elt (slot copied k)
        dupValue g em el v
        let dp = slot dst k
        let old = load elt dp
        emit em $"store {elt} {v}, ptr {dp}"
        dropValue g em el old
        let k1 = instr em $"add i_W {k}, 1"
        emit em $"store i_W {k1}, ptr {i}"
        emit em "br label %each.cond"
        enter em "each.end"
        emit em $"call void @zs_free(ptr {block})"
      else
        let n = instr em $"mul i_W %n, {sizeOf em elt}"
        emit em $"call void @llvm.memmove.p0.p0.i_W(ptr {dst}, ptr {src}, i_W {n}, i1 false)"
      emit em "ret void"
      helper g $"define private void {name}(ptr %sd, i_W %sl, i_W %i, ptr %dd, i_W %dl, i_W %j, i_W %n) {{\n{bodyOf em}}}\n\n"
  name

/// @"unique.array<T>"(a): `a` when it holds the only reference, else a copy of it (with `a`'s
/// reference given up): copy-on-write for arrays; @"copy.array<T>", the copy.
and uniqueFn (g: G) (t: Ty) (always: bool) : string =
  let el =
    match t with
    | TCon("array", [ e ]) -> e
    | _ -> panic "not an array"
  let name = $"@\"{(if always then "copy" else "unique")}.{showF g t}\""
  if not always && firstTime g name then
    // inlined at every write: a count test, and the copy (out of line, cold) only if shared
    let copy = uniqueFn g t true
    let em = emitter ()
    let rc = instr em (if g.opts.threaded then "load atomic i32, ptr %p monotonic, align 4" else "load i32, ptr %p")
    let only = instr em $"icmp eq i32 {rc}, 1"
    emit em $"br i1 {only}, label %same, label %copy, !prof !{{!\"branch_weights\", i32 2000, i32 1}}"
    enter em "same"
    emit em "ret ptr %p"
    enter em "copy"
    emit em $"%c = call ptr {copy}(ptr %p)"
    emit em "ret ptr %c"
    helper g $"define private ptr {name}(ptr %p) alwaysinline {{\n{bodyOf em}}}\n\n"
  else if always && firstTime g name then
    let em = emitter ()
    let at = $"{{ i_W, i_W, [0 x {llty g el}] }}"
    let lp = instr em "getelementptr { i_W, i_W }, ptr %p, i32 0, i32 1"
    let len = instr em $"load i_W, ptr {lp}"
    let es = sizeOf em (llty g el)
    let size = instr em $"mul i_W {len}, {es}"
    let bytes = instr em $"add i_W HDR2, {size}"
    let b = instr em $"call ptr @zs_alloc(i_W {bytes})"
    // the length and elements: the count is the copy's own (and another thread may be changing
    // the original's)
    let dst = instr em $"getelementptr i8, ptr {b}, i_W HDR1"
    let src = instr em "getelementptr i8, ptr %p, i_W HDR1"
    let n = instr em $"sub i_W {bytes}, HDR1"
    emit em $"call void @llvm.memcpy.p0.p0.i_W(ptr {dst}, ptr {src}, i_W {n}, i1 false)"
    emit em $"store i32 1, ptr {b}"
    if heap g el then
      // the copy holds its own reference to every element
      emit em "br label %loop"
      enter em "loop"
      let i = tmp em
      emit em $"{i} = phi i_W [ 0, %entry ], [ %next, %body ]"
      let c = instr em $"icmp slt i_W {i}, {len}"
      emit em $"br i1 {c}, label %body, label %end"
      enter em "body"
      let ep = instr em $"getelementptr {at}, ptr {b}, i32 0, i32 2, i_W {i}"
      dupValue g em el (instr em $"load {llty g el}, ptr {ep}")
      emit em $"%next = add i_W {i}, 1"
      emit em "br label %loop"
      enter em "end"
    dropValue g em t "%p"
    emit em $"ret ptr {b}"
    helper g $"define private ptr {name}(ptr %p) noinline cold {{\n{bodyOf em}}}\n\n"
  name

/// The function dropping a value of the type.
and dropFn (g: G) (t: Ty) : string =
  match t with
  | TFun _ -> "@zs.drop.clo"
  | TCon(n, _) when isDynName n -> "@zs.drop.dyn"
  | TCon("weak", _) ->
    // a weak reference's cell: the runtime frees it (and forgets its object)
    if firstTime g "@zs.drop.weak" then
      helper g "define private void @zs.drop.weak(ptr %p) {\nentry:\n  %last = call i1 @zs.release(ptr %p)\n  br i1 %last, label %free, label %done\nfree:\n  call void @zs_weak_free(ptr %p)\n  ret void\ndone:\n  ret void\n}\n\n"
    "@zs.drop.weak"
  | TCon("string", _) -> "@zs.drop.str"
  | TTuple _
  | TCon("fixed", _) -> structHelper g "drop" t
  | TCon(n, _) when isRecordType g n -> structHelper g "drop" t
  | pt ->
    let name = $"@\"drop.{showF g pt}\""
    if firstTime g name then
      let em = emitter ()
      match repOfUnion g pt with
      | Some(Niche(_, payload)) ->
        // the payload itself, or @zs.none (static: its count is never changed)
        emit em $"musttail call void {dropFn g payload}(ptr %p)"
        emit em "ret void"
      | _ ->
        let last = instr em "call i1 @zs.release(ptr %p)"
        emit em $"br i1 {last}, label %free, label %done"
        enter em "free"
        match pt with
        | TCon("array", [ el ]) ->
          if heap g el then
            let lenp = instr em "getelementptr { i_W, i_W }, ptr %p, i32 0, i32 1"
            let len = instr em $"load i_W, ptr {lenp}"
            emit em "br label %loop"
            enter em "loop"
            let i = tmp em
            let next = tmp em
            let back = fresh em "next"
            emit em $"{i} = phi i_W [ 0, %free ], [ {next}, %{back} ]"
            let c = instr em $"icmp slt i_W {i}, {len}"
            emit em $"br i1 {c}, label %body, label %end"
            enter em "body"
            let ep = instr em $"getelementptr {{ i_W, i_W, [0 x {llty g el}] }}, ptr %p, i32 0, i32 2, i_W {i}"
            dropValue g em el (instr em $"load {llty g el}, ptr {ep}")
            emit em $"br label %{back}"
            enter em back
            emit em $"{next} = add i_W {i}, 1"
            emit em "br label %loop"
            enter em "end"
          emit em "call void @zs_free(ptr %p)"
          emit em "ret void"
        | TCon("ref", [ x ]) ->
          let vp = instr em $"getelementptr {{ i_W, {llty g x} }}, ptr %p, i32 0, i32 1"
          let xv = instr em $"load {llty g x}, ptr {vp}"
          emit em "call void @zs_free(ptr %p)"
          dropValue g em x xv
          emit em "ret void"
        | TCon("Atomic", _) ->
          emit em "call void @zs_free(ptr %p)"
          emit em "ret void"
        | TCon("Mutex", [ x ]) ->
          let vp = instr em $"getelementptr {{ i_W, i32, {llty g x} }}, ptr %p, i32 0, i32 2"
          let xv = instr em $"load {llty g x}, ptr {vp}"
          emit em "call void @zs_free(ptr %p)"
          dropValue g em x xv
          emit em "ret void"
        | TCon("Channel", _) ->
          // the runtime's: what's still in it goes with the drop function it was made with
          emit em "call void @zs_chan_free(ptr %p)"
          emit em "ret void"
        | TCon("Spsc", _) ->
          emit em "call void @zs_spsc_free(ptr %p)"
          emit em "ret void"
        | _ ->
          let (_, cases) = union g pt
          let withRefs = List.filter (fun (_, (_, fs)) -> List.exists (heap g) fs) (List.indexed cases)
          if tagged g pt then
            let tag = loadTag g em "%p" None
            let targets = String.join " " (List.map (fun (i, _) -> $"i32 {i}, label %case{i}") withRefs)
            emit em $"switch i32 {tag}, label %plain [ {targets} ]"
          else
            // the one case with fields
            match withRefs with
            | (i, _) :: _ -> emit em $"br label %case{i}"
            | [] -> emit em "br label %plain"
          for (i, (_, fs)) in withRefs do
            enter em $"case{i}"
            let cell = cellTy g pt i
            let load (jf: int * Ty) =
              let (j, ft) = jf
              let fp = instr em $"getelementptr {cell}, ptr %p, i32 0, i32 {cellField g pt j}"
              (ft, instr em $"load {llty g ft}, ptr {fp}")
            let refs = List.map load (List.filter (fun (_, ft) -> heap g ft) (List.indexed fs))
            emit em "call void @zs_free(ptr %p)"
            let (lt, lv) = List.last refs
            for (ft, fv) in List.take (List.length refs - 1) refs do
              dropValue g em ft fv
            // the last field is dropped by a tail call, so long lists free iteratively
            if llty g lt = "ptr" then emit em $"musttail call void {dropFn g lt}(ptr {lv})" else dropValue g em lt lv
            emit em "ret void"
          enter em "plain"
          emit em "call void @zs_free(ptr %p)"
          emit em "ret void"
      enter em "done"
      emit em "ret void"
      helper g $"define private void {name}(ptr %p) {{\n{bodyOf em}}}\n\n"
    name

// ------------------------------------------------------------ closures

/// Allocates a closure for stage k of f holding the given environment values (moved in).
let rec allocClosure (g: G) (em: Emitter) (f: string) (env: list<Ty * string>) : string =
  let k = List.length env
  let cell = cloTy g (List.map fst env)
  let c = instr em $"call ptr @zs_alloc(i_W {sizeOf em cell})"
  emit em $"store i32 1, ptr {c}"
  let cp = instr em $"getelementptr {cell}, ptr {c}, i32 0, i32 1"
  emit em $"store ptr {stub g f k}, ptr {cp}"
  let ip = instr em $"getelementptr {cell}, ptr {c}, i32 0, i32 2"
  emit em $"store ptr {info g f k}, ptr {ip}"
  let field (i: int) (tv: Ty * string) =
    let (t, x) = tv
    let fp = instr em $"getelementptr {cell}, ptr {c}, i32 0, i32 {i + 3}"
    emit em $"store {llty g t} {x}, ptr {fp}"
  List.iteri field env
  c

/// Loads a closure's environment (borrowed).
and loadEnv (g: G) (em: Emitter) (tys: list<Ty>) : list<Ty * string> =
  let cell = cloTy g tys
  let one (i: int) (t: Ty) =
    let fp = instr em $"getelementptr {cell}, ptr %clo, i32 0, i32 {i + 3}"
    (t, instr em $"load {llty g t}, ptr {fp}")
  List.mapi one tys

/// Code for a closure of f that already holds its first k parameters: takes parameter k.
and stub (g: G) (f: string) (k: int) : string =
  let name = $"@\"clo.{f}.{k}\""
  if firstTime g name then
    let fd = Map.find f g.fnTable
    let ps = List.map snd fd.pars
    let argTy = List.item k ps
    let last = k + 1 = List.length ps
    let retTy = if last then llty g fd.ret else "ptr"
    let em = emitter ()
    let env = loadEnv g em (List.take k ps)
    for (t, x) in env do
      dupValue g em t x
    let args = List.append env [ (argTy, "%arg") ]
    if last then
      let argv = String.join ", " (List.map (fun (t, x) -> llty g t + " " + x) args)
      let r = instr em $"tail call {retTy} {sym g f}({argv})"
      emit em $"ret {retTy} {r}"
    else
      emit em $"ret ptr {allocClosure g em f args}"
    helper g $"define private {retTy} {name}(ptr %clo, {llty g argTy} %arg) {{\n{bodyOf em}}}\n\n"
  name

/// What a closure of f holding k parameters is, for its users: its drop function, the number of
/// parameters it still takes, code taking all of them at once, and (with threads) the walk of
/// what it captured; the last slot is unused.
and info (g: G) (f: string) (k: int) : string =
  let name = $"@\"cloinfo.{f}.{k}\""
  if firstTime g name then
    let n = List.length (Map.find f g.fnTable).pars
    let env = List.take k (List.map snd (Map.find f g.fnTable).pars)
    let walk = if g.opts.threaded then captureWalk g env else "null"
    let drop = dropStub g env
    let all = full g f k
    topLine g $"{name} = private unnamed_addr constant {{ ptr, i32, ptr, ptr, ptr }} {{ ptr {drop}, i32 {n - k}, ptr {all}, ptr {walk}, ptr null }}"
  name

// a closure environment's types, as its helpers are named: a helper of one serves every closure
// that captured values of those types
and private envName (g: G) (env: list<Ty>) : string = String.join ", " (List.map (showF g) env)

/// The objects a closure captured, shared or moved (%move) after the closure itself was
/// (walkFn): one function for every closure whose captures have these types.
and captureWalk (g: G) (env: list<Ty>) : string =
  let name = $"@\"clowalk.{envName g env}\""
  if firstTime g name then
    let em = emitter ()
    for (t, x) in loadEnv g em env do
      walkIn g em t x "%move"
    emit em "ret void"
    helper g $"define private void {name}(ptr %clo, i1 %move) {{\n{bodyOf em}}}\n\n"
  name

/// Code for a closure of f holding its first k parameters that takes all the others at once.
and full (g: G) (f: string) (k: int) : string =
  let fd = Map.find f g.fnTable
  if k + 1 = List.length fd.pars then
    stub g f k
  else
    let name = $"@\"cloN.{f}.{k}\""
    if firstTime g name then
      let ps = List.map snd fd.pars
      let em = emitter ()
      let env = loadEnv g em (List.take k ps)
      for (t, x) in env do
        dupValue g em t x
      let rest = List.mapi (fun i t -> (t, $"%a{i}")) (List.skip k ps)
      let argv = String.join ", " (List.map (fun (t, x) -> llty g t + " " + x) (List.append env rest))
      let rt = llty g fd.ret
      let r = instr em $"tail call {rt} {sym g f}({argv})"
      emit em $"ret {rt} {r}"
      let pars = String.join ", " (List.map (fun (t, x) -> llty g t + " " + x) rest)
      helper g $"define private {rt} {name}(ptr %clo, {pars}) {{\n{bodyOf em}}}\n\n"
    name

// a closure's drop: the closure freed, what it captured dropped; one function for every closure
// whose captures have these types
and dropStub (g: G) (env0: list<Ty>) : string =
  let name = $"@\"clodrop.{envName g env0}\""
  if firstTime g name then
    let em = emitter ()
    let env = loadEnv g em env0
    emit em "call void @zs_free(ptr %clo)"
    for (t, x) in env do
      dropValue g em t x
    emit em "ret void"
    helper g $"define private void {name}(ptr %clo) {{\n{bodyOf em}}}\n\n"
  name

/// The vtable of a dyn Trait over type t: a function freeing the dyn (and dropping the value it
/// holds), then the trait's methods for t.
let vtable (g: G) (tr: string) (t: Ty) (entries: list<string>) : string =
  let name = $"@\"vt.{tr}.{showF g t}\""
  if firstTime g name then
    let drop = $"@\"dyndrop.{showF g t}\""
    if firstTime g drop then
      let em = emitter ()
      let p = instr em $"getelementptr {{ i_W, ptr, {llty g t} }}, ptr %p, i32 0, i32 2"
      let x = instr em $"load {llty g t}, ptr {p}"
      emit em "call void @zs_free(ptr %p)"
      dropValue g em t x
      emit em "ret void"
      helper g $"define private void {drop}(ptr %p) {{\n{bodyOf em}}}\n\n"
    let slots = ("ptr " + drop) :: List.map (fun f -> "ptr " + sym g f) entries
    let types = String.join ", " (List.map (fun _ -> "ptr") slots)
    topLine g $"{name} = private unnamed_addr constant {{ {types} }} {{ {String.join ", " slots} }}"
  name

/// The thread pool's runner for a job whose closure gives a T (runtime/rt.c, zs_par_fork): calls
/// it, stores its result where the job keeps it, and gives up the closure.
let parRunner (g: G) (rt: Ty) : string =
  let name = $"@\"parrun.{showF g rt}\""
  if firstTime g name then
    let em = emitter ()
    let cp = instr em "getelementptr { i_W, ptr }, ptr %clo, i32 0, i32 1"
    let code = instr em $"load ptr, ptr {cp}"
    let r = instr em $"call {llty g rt} {code}(ptr %clo, {{}} zeroinitializer)"
    emit em $"store {llty g rt} {r}, ptr %out"
    emit em "call void @zs.drop.clo(ptr %clo)"
    emit em "ret void"
    helper g $"define private void {name}(ptr %clo, ptr %out) {{\n{bodyOf em}}}\n\n"
  name

/// A function dropping the T a channel's slot holds (what's left in one when it's freed), or null
/// when a T holds no reference counts.
let slotDrop (g: G) (t: Ty) : string =
  if not (heap g t) then
    "null"
  else
    let name = $"@\"slotdrop.{showF g t}\""
    if firstTime g name then
      let em = emitter ()
      dropValue g em t (instr em $"load {llty g t}, ptr %slot")
      emit em "ret void"
      helper g $"define private void {name}(ptr %slot) {{\n{bodyOf em}}}\n\n"
    name

/// A closure of f holding nothing: a static one.
let staticClosure (g: G) (f: string) : string =
  let name = $"@\"cloS.{f}\""
  if firstTime g name then
    let s = stub g f 0
    let i = info g f 0
    topLine g $"{name} = private unnamed_addr constant {{ i_W, ptr, ptr }} {{ i_W 0, ptr {s}, ptr {i} }}"
  name

/// A handle of value v (its reference goes into it) for C: a Share value's (in a program with
/// threads) has its objects marked shared and may be used on any thread; any other's belongs to
/// this thread, and a use on another panics, naming its type.
let handleOf (g: G) (em: Emitter) (t: Ty) (v: string) : string =
  let shared = g.opts.threaded && Option.isNone (shareBlocker g.v (fun _ -> ()) g.types Set.empty t)
  if shared then
    shareValue g em t v
  let drop = dropFn g t
  instr em $"call ptr @zs_handle_new(ptr {v}, ptr {drop}, i1 {(if shared then "true" else "false")}, ptr {cstrConst g (showT g t)})"

/// C's entry point for a callback<A -> R>: R thunk(void* user, A) calls the closure. Shared
/// (callback<share<A -> R>>), user is the closure, which may be called from any thread; else user
/// is { the closure, the thread that passed it }, and a call on another thread panics.
let thunk (g: G) (f: Ty) (shared: bool) : string =
  let (a, r) =
    match f with
    | TFun(a, r, _) -> (a, r)
    | _ -> panic "callback type"
  let name = $"@\"cb{(if shared then ".shared" else "")}.{showF g f}\""
  if firstTime g name then
    let em = emitter ()
    let unitArg =
      match a with
      | TCon("unit", []) -> true
      | _ -> false
    let clo =
      if shared then
        "%user"
      else
        let owner = instr em "getelementptr { ptr, i64 }, ptr %user, i32 0, i32 1"
        emit em $"call void @zs_callback_thread(ptr {owner}, ptr {cstrConst g (showT g f)})"
        instr em "load ptr, ptr %user"
    let cp = instr em $"getelementptr {{ i_W, ptr }}, ptr {clo}, i32 0, i32 1"
    let code = instr em $"load ptr, ptr {cp}"
    let av = if unitArg then "zeroinitializer" else "%x"
    let res = instr em $"call {llty g r} {code}(ptr {clo}, {llty g a} {av})"
    let (rt, _) = cRet g r
    emit em (if rt = "void" then "ret void" else $"ret {llty g r} {res}")
    let ps = "ptr %user" + (if unitArg then "" else $", {cParam g a} %x")
    helper g $"define private {rt} {name}({ps}) {{\n{bodyOf em}}}\n\n"
  name

// ------------------------------------------------------------ top-level values and tasks

/// A top-level value's global.
let valueSym (v: string) : string = $"@\"zsv.{v}\""

// A task's state machine (task { }): its work is an LLVM coroutine, whose frame follows a closure
// header in one object, the face: { count, code, description, the coroutine's handle, the result
// slot }. Each wait passes the face as the continuation of the task it waits for, its code and
// description set for that task's result type: calling it stores the result and resumes the
// coroutine. So a wait allocates nothing; the frame is allocated once, when the work starts, and
// the face's last reference going destroys the coroutine (dropping what a cancelled task held
// there, task.held).

/// The face's shared parts: its drop function, its share function (a task waits on the thread it
/// runs on: what it holds isn't the face's to mark), and the description it starts with.
let faceCommon (g: G) =
  if firstTime g "@zs.face.drop" then
    helper g "define private void @zs.face.drop(ptr %face) {\nentry:\n  %hp = getelementptr { i_W, ptr, ptr, ptr }, ptr %face, i32 0, i32 3\n  %hdl = load ptr, ptr %hp\n  call void @llvm.coro.destroy(ptr %hdl)\n  call void @zs_free(ptr %face)\n  ret void\n}\n\n"
    let msg = "a waiting task's continuation can't cross threads"
    topLine g $"@zs.face.crossing = private unnamed_addr constant [{String.length msg + 1} x i8] c\"{msg}\\00\""
    helper g "define private void @zs.face.share(ptr %face) {\nentry:\n  call void @zs_panic_c(ptr @zs.face.crossing)\n  unreachable\n}\n\n"
    topLine g "@zs.faceinfo.none = private unnamed_addr constant { ptr, i32, ptr, ptr, ptr } { ptr @zs.face.drop, i32 1, ptr null, ptr @zs.face.share, ptr @zs.face.share }"

/// The face's code and description for a wait whose result is a t: the code stores the result in
/// the slot and resumes the coroutine.
let faceFor (g: G) (t: Ty) : string * string =
  faceCommon g
  let lt = llty g t
  let code = $"@\"face.{showF g t}\""
  let inf = $"@\"faceinfo.{showF g t}\""
  if firstTime g code then
    helper g $"define private {{}} {code}(ptr %face, {lt} %x) {{\nentry:\n  %slot = getelementptr {{ i_W, ptr, ptr, ptr, {lt} }}, ptr %face, i32 0, i32 4\n  store {lt} %x, ptr %slot\n  %hp = getelementptr {{ i_W, ptr, ptr, ptr }}, ptr %face, i32 0, i32 3\n  %hdl = load ptr, ptr %hp\n  call void @llvm.coro.resume(ptr %hdl)\n  ret {{}} zeroinitializer\n}}\n\n"
    topLine g $"{inf} = private unnamed_addr constant {{ ptr, i32, ptr, ptr, ptr }} {{ ptr @zs.face.drop, i32 1, ptr {code}, ptr @zs.face.share, ptr @zs.face.share }}"
  (code, inf)
