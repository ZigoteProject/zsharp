/// Patterns: a written pattern checked against the type of what it matches, as Core's (its
/// variables given unique names); and a match's exhaustiveness and redundancy (Maranget, "Warnings
/// for pattern matching", 2007: usefulness, returning a witness).
open Types.Ty
open Types.Vars
open Types.Norm
open Types.Fail
open Core.Ir
open Syntax.Ast
open Cx

// a pattern that's a tuple's parts, when it is one
let private tupleParts (q: Pat) : option<list<Pat>> =
  match q.pat with
  | PTuple ps -> Some ps
  | _ -> None

let private isWild (q: Pat) : bool =
  match q.pat with
  | PWild -> true
  | _ -> false

/// A pattern checked against the type of what it matches, as Core's. Its variables get unique
/// names: `names` has the ones given so far, which both sides of an or-pattern share.
let rec pattern (cx: Cx) (names: ref<Map<string, string>>) (p: Pat) (ty: Ty) : CPat / <Fails, Mismatched> =
  let name (x: string) =
    match Map.tryFind x names.Value with
    | Some u -> u
    | None ->
      let u = uniq cx x
      names.Value <- Map.add x u names.Value
      u
  let ctorPattern (c: string) (arg: option<Pat>) =
    let (u, tag) = Map.find c cx.ctors.Value
    if Option.isSome (cUnionCases cx u) then
      fail $"a C union can't be matched: read a case with unsafe v.{afterLastDot c}"
    let (uty, targs) = instType cx u
    expect cx "pattern" ty uty
    let fields = caseFields cx u tag targs
    let subs =
      match arg with
      | None when Set.contains c cx.apCtors.Value -> [ plainPat PWild ]
      | Some { pat = PArgs _ } -> fail $"constructor '{c}' takes one argument pattern"
      | Some { pat = PNamed named } ->
        let fieldNames = Map.find c cx.ctorFieldNames.Value
        for (n, _) in named do
          if not (List.contains (Some n) fieldNames) then
            fail $"constructor '{c}' has no field '{n}'"
        let byName (n: option<string>) =
          match List.tryFind (fun (m, _) -> Some m = n) named with
          | Some(_, q) -> q
          | None -> plainPat PWild
        List.map byName fieldNames
      | _ -> ctorArgs c (Option.toList arg) fields tupleParts isWild
    CPCtor(u, tag, List.map2 (pattern cx names) subs fields)
  match p.pat with
  | PWild -> CPWild
  | PUnit ->
    expect cx "pattern" ty tUnit
    CPWild
  | PInt n ->
    expect cx "pattern" ty (fresh cx.v kInt)
    literal cx ty n p.patAt false
    CPInt n
  | PNegInt n ->
    // said plainly where the type is known (the mismatch's own advice, a conversion, can't be
    // written in a pattern)
    match prune cx.v ty with
    | TCon(u, []) when Set.contains u unsigned -> fail $"a negative pattern is a signed integer; {u} has no -{u64 (Int.wrappingSub (i64 0) n)}"
    | _ -> expect cx "pattern" ty (fresh cx.v kSignedInt)
    literal cx ty n p.patAt true
    CPInt n
  | PChar c ->
    expect cx "pattern" ty tChar
    CPInt(i64 c)
  | PStr s ->
    expect cx "pattern" ty tStr
    CPStr s
  | PBool b ->
    expect cx "pattern" ty tBool
    CPBool b
  | PIdent(written, arg) ->
    match ctorName cx written with
    | Some c -> ctorPattern c arg
    | None ->
      match arg with
      | None ->
        let u = name written
        recordKey cx p.patAt written ty true u true
        CPVar(u, ty)
      | Some _ -> fail $"unknown constructor '{written}'"
  | PTuple ps ->
    let ts = List.map (fun _ -> fresh cx.v kAny) ps
    expect cx "pattern" ty (TTuple ts)
    CPTuple(List.map2 (pattern cx names) ps ts)
  | POr(a, b) ->
    let ca = pattern cx names a ty
    let cb = pattern cx names b ty
    let va = patVars ca
    let vb = patVars cb
    if List.sort (List.map fst va) <> List.sort (List.map fst vb) then
      fail "both sides of '|' must bind the same variables"
    for (x, t) in va do
      expect cx "or-pattern variable" t (snd (List.find (fun (y, _) -> y = x) vb))
    CPOr(ca, cb)
  | PAs(q, x) ->
    let cq = pattern cx names q ty
    CPAs(cq, name x, ty)
  | PRecord fields ->
    let given = List.map (fun (f, _, _) -> f) fields
    match List.tryFind (fun f -> List.length (List.filter (fun g -> g = f) given) > 1) given with
    | Some f -> fail $"field '{f}' appears twice in the pattern"
    | None -> ()
    // the record: the matched value's type when known, else the latest declared record in scope
    // with all these fields (as for record literals)
    let rname =
      match prune cx.v ty with
      | TCon(n, _) when isRecord cx n -> n
      | _ ->
        match inScope cx (recordsWith cx given) with
        | [] ->
          let s = if List.length given > 1 then "s" else ""
          noRecord cx $"no record has the field{s} {quoted given}" given
        | candidates -> List.last candidates
    let declared = fieldsOf cx rname
    match List.tryFind (fun f -> not (List.exists (fun (g, _) -> g = f) declared)) given with
    | Some f -> fail $"record '{rname}' has no field '{f}'"
    | None -> ()
    let (rty, targs) = instType cx rname
    expect cx "pattern" ty rty
    fieldUses cx rname (List.map (fun (f, tok, _) -> (f, tok)) fields) false
    let sub (fd: string * Ty) =
      let (f, ft) = fd
      match List.tryFind (fun (g, _, _) -> g = f) fields with
      | Some(_, _, q) -> (f, pattern cx names q (substGen cx.v targs ft))
      | None -> (f, CPWild)
    CPRecord(rname, List.map sub declared)
  | PNamed _ -> fail "named field patterns need a constructor: C(field = p)"
  | PArgs _ -> fail "only constructors and active patterns take arguments"

// ------------------------------------------------------------ exhaustiveness

// a constructor: its name, how many fields it has, and every constructor of its type (None:
// infinitely many, as ints)
type private Con = { con: string; arity: int; all: option<list<string * int>> }

// the values a pattern covers. An or-pattern stays one, its alternatives in order (none of them
// one itself), until it's at the head of a row: Maranget's algorithm splits it there, in the
// column being specialized, never into the product of every column's alternatives up front
// ((true | false) in 26 columns was 2^26 rows)
type private Space =
  | SWild
  | SCon of Con * list<Space>
  | SOr of list<Space>

// an or-pattern's alternatives, the ones of an or-pattern among them in its place
let private alternatives (s: Space) : list<Space> =
  match s with
  | SOr alts -> alts
  | _ -> [ s ]

// a pattern as the space it covers
let rec private space (cases: string -> list<string * int> / <>) (p: CPat) : Space =
  let con (c: Con) (ps: list<CPat>) = SCon(c, List.map (space cases) ps)
  match p with
  | CPWild
  | CPVar _ -> SWild
  | CPAs(q, _, _) -> space cases q
  | CPInt n -> SCon({ con = $"{n}"; arity = 0; all = None }, [])
  | CPStr s -> SCon({ con = "\"" + s + "\""; arity = 0; all = None }, [])
  | CPBool b ->
    let all = Some [ ("true", 0); ("false", 0) ]
    SCon({ con = (if b then "true" else "false"); arity = 0; all = all }, [])
  | CPTuple ps -> con { con = ","; arity = List.length ps; all = Some [ (",", List.length ps) ] } ps
  | CPRecord(_, fs) ->
    // a record is one constructor; its name carries the field names, for messages
    let n = "{" + String.join ";" (List.map fst fs) + "}"
    con { con = n; arity = List.length fs; all = Some [ (n, List.length fs) ] } (List.map snd fs)
  | CPCtor(u, tag, ps) ->
    let all = cases u
    con { con = fst (List.item tag all); arity = List.length ps; all = Some all } ps
  | CPOr(a, b) -> SOr(List.append (alternatives (space cases a)) (alternatives (space cases b)))

let private isWildSpace (s: Space) : bool =
  match s with
  | SWild -> true
  | _ -> false

// a missing value as a pattern; bare: constructors whose payload is optional (active pattern
// cases), shown without it
let rec private render (bare: string -> bool / <>) (s: Space) : string =
  let atomic (x: Space) =
    match x with
    | SCon(c, _ :: _) when c.con <> "," && not (String.startsWith "{" c.con) && not (bare c.con) -> "(" + render bare x + ")"
    | _ -> render bare x
  match s with
  | SCon(c, [ SWild ]) when bare c.con -> c.con
  | SWild -> "_"
  | SOr alts -> String.join " | " (List.map (render bare) alts)
  | SCon(c, args) when c.con = "," -> "(" + String.join ", " (List.map (render bare) args) + ")"
  | SCon(c, args) when String.startsWith "{" c.con ->
    // { kind = C }: only the fields that matter
    let names = String.split ";" (String.sub c.con 1 (String.length c.con - 2))
    match List.filter (fun (_, a) -> not (isWildSpace a)) (List.zip names args) with
    | [] -> "_"
    | shown -> "{ " + String.join "; " (List.map (fun (n, a) -> n + " = " + render bare a) shown) + " }"
  | SCon(c, [ h; t ]) when c.con = "::" -> atomic h + " :: " + render bare t
  | SCon(c, []) -> c.con
  | SCon(c, [ a ]) -> c.con + " " + atomic a
  | SCon(c, args) -> c.con + " (" + String.join ", " (List.map (render bare) args) + ")"

let private wilds (n: int) : list<Space> = List.replicate n SWild

// the rows with an or-pattern at the head split, one for each alternative, in order: what the
// head column holds, as if every or-pattern had been expanded (the same rows in the same order);
// the rows themselves when none is
let private split (rows: list<list<Space>>) : list<list<Space>> =
  let orHead (row: list<Space>) =
    match row with
    | SOr _ :: _ -> true
    | _ -> false
  if not (List.exists orHead rows) then
    rows
  else
    let push (acc: list<list<Space>>) (row: list<Space>) =
      match row with
      | SOr alts :: rest -> List.fold (fun (a: list<list<Space>>) alt -> (alt :: rest) :: a) acc alts
      | _ -> row :: acc
    List.rev (List.fold push [] rows)

let private specialize (c: Con) (rows: list<list<Space>>) : list<list<Space>> =
  let one (row: list<Space>) =
    match row with
    | SCon(c2, args) :: rest when c2.con = c.con -> Some(List.append args rest)
    | SWild :: rest -> Some(List.append (wilds c.arity) rest)
    | _ -> None
  List.choose one (split rows)

let private defaults (rows: list<list<Space>>) : list<list<Space>> =
  let one (row: list<Space>) =
    match row with
    | SWild :: rest -> Some rest
    | _ -> None
  List.choose one (split rows)

let private rebuild (c: Con) (w: list<Space>) : list<Space> = SCon(c, List.take c.arity w) :: List.skip c.arity w

// the work one match's check may do, in calls and the rows they look at. Exhaustiveness with
// or-patterns is NP-hard, (true | false) in n columns 2^n paths however they're expanded, so past
// this the match is an error, not seconds of an editor's time (or minutes) on every change
let private budget = 5000000

// a value vector matched by q but by no row, if any; None too once steps passes the budget
let rec private useful (steps: ref<int>) (rows: list<list<Space>>) (q: list<Space>) : option<list<Space>> =
  steps.Value <- steps.Value + 1 + List.length rows
  match q with
  | _ when steps.Value > budget -> None
  | [] -> if List.isEmpty rows then Some [] else None
  // q's alternatives (a clause's, checked for being reachable): any one that's useful
  | SOr alts :: rest -> List.tryPick (fun a -> useful steps rows (a :: rest)) alts
  | SCon(c, args) :: rest -> Option.map (rebuild c) (useful steps (specialize c rows) (List.append args rest))
  | SWild :: rest ->
    let heads (row: list<Space>) =
      match row with
      | SCon(c, _) :: _ -> Some c
      | _ -> None
    let sigma = List.fold (fun (acc: list<Con>) c -> if List.exists (fun (d: Con) -> d.con = c.con) acc then acc else List.append acc [ c ]) [] (List.choose heads (split rows))
    let all =
      match List.tryHead sigma with
      | Some c -> c.all
      | None -> None
    let seen (n: string) = List.exists (fun (c: Con) -> c.con = n) sigma
    let complete =
      match all with
      | Some cs -> List.forall (fun (n, _) -> seen n) cs
      | None -> false
    match all with
    | Some cs when complete ->
      let tryCon (p: string * int) =
        let (n, a) = p
        let c = { con = n; arity = a; all = all }
        Option.map (rebuild c) (useful steps (specialize c rows) (List.append (wilds a) rest))
      List.tryPick tryCon cs
    | _ ->
      let missing =
        match all with
        | Some cs ->
          let (n, a) = List.find (fun (m, _) -> not (seen m)) cs
          SCon({ con = n; arity = a; all = all }, wilds a)
        | None -> SWild
      Option.map (fun w -> missing :: w) (useful steps (defaults rows) rest)

/// A match's error for a value no clause matches, shown as `missing`.
let matchMissing (missing: string) = $"match is not exhaustive; missing case: {missing}"

/// A let's error for a value its pattern doesn't match.
let letMissing (missing: string) = $"a let's pattern must match every value, and this one misses {missing}: write a match with a case for it"

/// Fails if a clause can never match or if some value matches no clause, worded by `missing`.
/// clauses: each pattern, and whether it has a guard (guarded clauses don't count toward
/// coverage). cases: a union's cases and their field counts. bare: constructors whose payload is
/// optional (active pattern cases), shown without it.
let checkWith (missing: string -> string) (cases: string -> list<string * int> / <>) (bare: string -> bool / <>) (clauses: list<CPat * bool>) : unit / Fails =
  let rows = ref []
  let steps = ref 0
  let tooComplex () =
    fail $"this match is too complex to check that it covers every value (past {budget} steps: its or-patterns multiply): split it into matches on fewer values at once"
  for (p, guarded) in clauses do
    let s = space cases p
    // reached when one of its alternatives is
    let reached = Option.isSome (useful steps rows.Value [ s ])
    if steps.Value > budget then
      tooComplex ()
    if not reached then
      fail "this match case is never reached"
    if not guarded then
      rows.Value <- List.append rows.Value [ [ s ] ]
  let w = useful steps rows.Value [ SWild ]
  if steps.Value > budget then
    tooComplex ()
  match w with
  | Some w -> fail (missing (render bare (List.head w)))
  | None -> ()

/// checkWith, worded for a match.
let check (cases: string -> list<string * int> / <>) (bare: string -> bool / <>) (clauses: list<CPat * bool>) : unit / Fails =
  checkWith matchMissing cases bare clauses
