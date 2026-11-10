/// break, continue and return (proposal 0029), lowered before a function's body is checked to
/// what the language already has, so no pass after the checker knows them:
/// - a loop that's left early has a `$stop` flag in its condition, and a body that's left early
///   a `$skip` flag: what follows a statement that may leave runs only when the flag isn't set;
/// - a `return e` where the function's value is wanted is `e`; anywhere else it stores `e` in
///   `$ret`, sets `$done` and every enclosing loop's flags, and the function's value is read
///   from `$ret` where its body ends;
/// - a `let` whose value may leave binds an option of it, None when it left.
/// A lambda or a local function is its own function, lowered when it's checked. The flags are
/// locals of one function, which LLVM's jump threading turns back into branches.
open Types.Fail
open Syntax.Ast

// what e may do to leave: return from its function, break or continue a loop around it (its
// own loops' breaks aren't its leaving). tries: e is a statement of a loop's body, where a `?`
// returns from the function (elsewhere it gives its block the failure, as it always did).
let rec private scan (inLoop: bool) (tries: bool) (ret: ref<bool>) (brk: ref<bool>) (cont: ref<bool>) (e: Expr) : unit =
  let go (t: bool) (x: Expr) = scan inLoop t ret brk cont x
  match e.e with
  | Return v ->
    ret.Value <- true
    go false v
  | Break ->
    if not inLoop then
      brk.Value <- true
  | Continue ->
    if not inLoop then
      cont.Value <- true
  | Lambda _ -> ()
  | LetFun(_, _, _, _, _, rest) -> go tries rest
  | LetRecGroup(_, rest) -> go tries rest
  | While(c, b) ->
    go false c
    scan true true ret brk cont b
  | For(_, a, _, b, body) ->
    go false a
    go false b
    scan true true ret brk cont body
  | ForIn(_, xs, b) ->
    go false xs
    scan true true ret brk cont b
  | TryBind(_, x, rest) ->
    if tries then
      ret.Value <- true
    go false x
    go tries rest
  | At a -> go tries a
  | AtLine a -> go tries a
  | Seq(a, b) ->
    go tries a
    go tries b
  | If(c, t, f) ->
    go false c
    go tries t
    match f with
    | Some x -> go tries x
    | None -> ()
  | Match(s, cls) ->
    go false s
    for cl in cls do
      match cl.guard with
      | Some g -> go false g
      | None -> ()
      go tries cl.body
  | Let(_, _, { e = Call(f, [ a ]) }, rest) when f = libraryName "Native.useScope" ->
    go tries a
    go false rest
  | Let(_, _, v, rest) ->
    go false v
    go tries rest
  | LetMut(_, _, v, rest) ->
    go false v
    go tries rest
  | _ ->
    let visit (c: Expr) : Expr =
      go false c
      c
    mapExpr visit e |> ignore

// whether e may return, and whether it may leave at all; tries: as scan's
let private leaves (tries: bool) (e: Expr) : bool * bool =
  let ret = ref false
  let brk = ref false
  let cont = ref false
  scan false tries ret brk cont e
  (ret.Value, ret.Value || brk.Value || cont.Value)

/// Where an expression is: the innermost loop's flags ("" outside a loop), every flag a return
/// sets on its way out, what its value is for (0: nothing, it's a statement; 1: the function's
/// result; 2: a let's value, made an option), whether the function needs `$ret`, a counter for
/// names, and the function's written result type, which a returned value is checked against
/// where it's written.
type private Ctx = { skip: string; stop: string; flags: list<string>; kind: int; slot: ref<bool>; counter: ref<int>; ret: option<SType> }

let private var (x: string) : Expr = plain (Var x)

let private set (x: string) (v: Expr) : Expr = plain (Assign(var x, v))

let private yes () : Expr = plain (BoolLit true)

let private no () : Expr = plain (BoolLit false)

let private some (v: Expr) : Expr = plain (Call("Some", [ v ]))

let private none () : Expr = plain (Var "None")

let private seqs (xs: list<Expr>) (last: Expr) : Expr = List.fold (fun acc a -> plain (Seq(a, acc))) last (List.rev xs)

let private fresh (c: Ctx) (name: string) : string =
  c.counter.Value <- c.counter.Value + 1
  $"{name}{c.counter.Value}"

// the value where the function or the loop's round has been left: never used, but of the type
let private bottom (c: Ctx) : Expr =
  if c.kind = 0 then plain UnitLit
  else if c.kind = 2 then none ()
  else plain (Call(libraryName "Option.get", [ var "$ret" ]))

// whether it has been left
let private left (c: Ctx) : Expr = if c.skip <> "" then var c.skip else var "$done"

let rec private strip (e: Expr) : Expr =
  match e.e with
  | At a -> strip a
  | AtLine a -> strip a
  | _ -> e

let private misplaced (what: string) : string =
  $"'{what}' can't be used inside this expression: write it as a statement, as a branch of an if or a match, or as a let's value"

// e, which may leave, as its context's value
let rec private tr (c: Ctx) (e: Expr) : Expr / Fails =
  // a statement of a loop's body, where a `?` returns
  let stmt = c.skip <> ""
  if not (snd (leaves (stmt && c.kind = 0) e)) then
    let w = walk c e
    if c.kind = 2 then some w else w
  else
    match e.e with
    | At a -> { e with e = At(tr c a) }
    | AtLine a -> { e with e = AtLine(tr c a) }
    | Unsafe a -> { e with e = Unsafe(tr c a) }
    | Typed(a, t) when c.kind <> 2 -> { e with e = Typed(tr c a, t) }
    | Return v ->
      let w =
        match c.ret with
        | Some t -> plain (Typed(walk c v, t))
        | None -> walk c v
      if c.kind = 1 then
        w
      else
        c.slot.Value <- true
        seqs (set "$ret" (some w) :: set "$done" (yes ()) :: List.map (fun f -> set f (yes ())) c.flags) (bottom c)
    | Break ->
      if c.skip = "" then
        failLine e.at "'break' is outside a loop (a lambda is a function of its own)"
      seqs [ set c.skip (yes ()); set c.stop (yes ()) ] (bottom c)
    | Continue ->
      if c.skip = "" then
        failLine e.at "'continue' is outside a loop (a lambda is a function of its own)"
      seqs [ set c.skip (yes ()) ] (bottom c)
    | Seq(a, rest) ->
      if snd (leaves stmt a) then
        match (strip a).e with
        | Return _
        | Break
        | Continue -> failLine (strip rest).at "this is never reached: the statement before it leaves"
        | _ -> ()
        let a2 = tr { c with kind = 0 } a
        let rest2 = tr c rest
        if c.kind = 0 then
          { e with e = Seq(a2, plain (If(plain (Not(left c)), rest2, None))) }
        else
          { e with e = Seq(a2, plain (If(left c, bottom c, Some rest2))) }
      else
        { e with e = Seq(walk c a, tr c rest) }
    // use x = v and the rest: the rest is the scope's value, in the form its context wants, and
    // x is disposed after it however it ended
    | Let(p, ann, { e = Call(f, [ a ]); at = va }, rest) when f = libraryName "Native.useScope" ->
      { e with e = Let(p, ann, expr (Call(f, [ tr c a ])) va, walk c rest) }
    | Let(p, ann, v, rest) ->
      if snd (leaves false v) then
        bound c v (fun x -> plain (Let(p, ann, x, tr c rest)))
      else
        { e with e = Let(p, ann, walk c v, tr c rest) }
    | LetMut(x, ann, v, rest) ->
      if snd (leaves false v) then
        bound c v (fun y -> plain (LetMut(x, ann, y, tr c rest)))
      else
        { e with e = LetMut(x, ann, walk c v, tr c rest) }
    | LetFun(n, r, ps, t, body, rest) -> { e with e = LetFun(n, r, ps, t, body, tr c rest) }
    | LetRecGroup(ms, rest) -> { e with e = LetRecGroup(ms, tr c rest) }
    | TryBind(p, x, rest) ->
      // in a loop's body a failure returns it from the function; elsewhere it's its block's value
      if c.kind = 0 && c.skip <> "" then
        { e with e = TryLeave(p, walk c x, tr c rest, "$fail", tr c (plain (Return(var "$fail")))) }
      else
        { e with e = TryBind(p, walk c x, tr c rest) }
    | If(cnd, t, f) ->
      let f2 =
        match f with
        | Some x -> Some(tr c x)
        | None -> if c.kind = 0 then None else Some(tr c (plain UnitLit))
      { e with e = If(walk c cnd, tr c t, f2) }
    | Match(s, cls) ->
      let clause (cl: Clause) : Clause / Fails =
        let g =
          match cl.guard with
          | Some x -> Some(walk c x)
          | None -> None
        { cl with guard = g; body = tr c cl.body }
      { e with e = Match(walk c s, List.map clause cls) }
    | While _
    | For _
    | ForIn _ ->
      let l = loop c e
      // a let's value: unit, unless the loop was left for good
      if c.kind = 2 then plain (Seq(l, plain (If(left c, none (), Some(some (plain UnitLit)))))) else l
    | _ -> walk c e

// let p = v and the rest, v leaving maybe: its option bound, the rest where it's Some
and private bound (c: Ctx) (v: Expr) (rest: Expr -> Expr / Fails) : Expr / Fails =
  let o = fresh c "$val"
  let t = fresh c "$bound"
  let v2 = tr { c with kind = 2 } v
  let ok : Clause = { pattern = plainPat (PIdent("Some", Some(plainPat (PIdent(t, None))))); guard = None; body = rest (var t) }
  let gone : Clause = { pattern = plainPat (PIdent("None", None)); guard = None; body = bottom c }
  plain (Let(plainPat (PIdent(o, None)), None, v2, plain (Match(var o, [ ok; gone ]))))

// e, which must not leave: its loops that are left early lowered, its functions left to their
// own checks
and private walk (c: Ctx) (e: Expr) : Expr / Fails =
  match e.e with
  | Lambda _ -> e
  | LetFun(n, r, ps, t, body, rest) -> { e with e = LetFun(n, r, ps, t, body, walk c rest) }
  | LetRecGroup(ms, rest) -> { e with e = LetRecGroup(ms, walk c rest) }
  | Return _ -> failLine e.at (misplaced "return")
  | Break -> failLine e.at (misplaced "break")
  | Continue -> failLine e.at (misplaced "continue")
  | While(_, b)
  | For(_, _, _, _, b)
  | ForIn(_, _, b) ->
    let ret = ref false
    let brk = ref false
    let cont = ref false
    scan false true ret brk cont b
    if ret.Value then
      failLine e.at (misplaced "return")
    if brk.Value || cont.Value then loop c e else mapExpr (walk c) e
  | _ -> mapExpr (walk c) e

// a loop whose body leaves: unit
and private loop (c: Ctx) (e: Expr) : Expr / Fails =
  let body =
    match e.e with
    | While(_, b) -> b
    | For(_, _, _, _, b) -> b
    | ForIn(_, _, b) -> b
    | _ -> e
  let ret = ref false
  let brk = ref false
  let cont = ref false
  scan false true ret brk cont body
  let skip = fresh c "$skip"
  let stop = fresh c "$stop"
  let stops = ret.Value || brk.Value
  if ret.Value then
    c.slot.Value <- true
  let cb = { c with skip = skip; stop = stop; flags = (if stops then skip :: stop :: c.flags else skip :: c.flags); kind = 0 }
  let body2 = plain (LetMut(skip, None, no (), tr cb body))
  let running () = plain (Not(var stop))
  let lowered =
    match e.e with
    | While(cnd, _) ->
      let cnd2 = walk c cnd
      { e with e = While((if stops then plain (If(running (), cnd2, Some(no ()))) else cnd2), body2) }
    | ForIn(x, xs, _) -> { e with e = (if stops then ForInUntil(x, walk c xs, body2, stop) else ForIn(x, walk c xs, body2)) }
    | For(x, a, step, b, _) ->
      if not stops then
        let step2 =
          match step with
          | Some s -> Some(walk c s)
          | None -> None
        { e with e = For(x, walk c a, step2, walk c b, body2) }
      else
        // a range loop has no early end: a while over the same integers. Whether there's a next
        // one is asked of the current one, before the step, so nothing overflows at a type's
        // end and the step is the only thing the next round waits for
        let (down, by) =
          match step with
          | None -> (false, i64 1)
          | Some s ->
            match s.e with
            | Lit n when n > i64 0 -> (false, n)
            | Neg { e = Lit n } when n > i64 0 -> (true, n)
            | _ -> failLine e.at "a range loop left early needs a step that's a literal, not 0: write it as a while loop"
        let i = fresh c "$i"
        let hi = fresh c "$hi"
        let more = fresh c "$more"
        let gap = if down then plain (Bin("-", var i, var hi)) else plain (Bin("-", var hi, var i))
        // ponytail: a step other than 1 over more than half its type's span panics in the
        // subtraction; compare without it if such a loop is ever written
        let hasNext =
          if by = i64 1 then plain (Bin((if down then ">" else "<"), var i, var hi))
          else plain (Bin(">=", gap, plain (Lit by)))
        let next = plain (Call(libraryName (if down then "Int.wrappingSub" else "Int.wrappingAdd"), [ var i; plain (Lit by) ]))
        let advance = plain (Seq(set more hasNext, set i next))
        let round = plain (Let(plainPat (PIdent(x, None)), None, var i, plain (Seq(body2, advance))))
        let w = { e with e = While(plain (If(running (), var more, Some(no ()))), round) }
        let first = plain (Bin((if down then ">=" else "<="), var i, var hi))
        plain (LetMut(i, None, walk c a, plain (Let(plainPat (PIdent(hi, None)), None, walk c b, plain (LetMut(more, None, first, w))))))
    | _ -> e
  if stops then plain (LetMut(stop, None, no (), lowered)) else lowered

/// A function's body with its breaks, continues and returns lowered.
let fn (ret: option<SType>) (body: Expr) : Expr / Fails =
  let c = { skip = ""; stop = ""; flags = []; kind = 1; slot = ref false; counter = ref 0; ret = ret }
  let b = tr c body
  if c.slot.Value then plain (LetMut("$ret", None, none (), plain (LetMut("$done", None, no (), b)))) else b
