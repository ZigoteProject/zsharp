/// Exhaustiveness and redundancy checking for match expressions.
/// Maranget, "Warnings for pattern matching" (2007): usefulness, returning a witness.
module Match

open Syntax
open Core

type private Con =
    { name: string
      arity: int
      all: (string * int) list option } // every constructor of the type; None = infinite (ints)

type private Space =
    | SWild
    | SCon of Con * Space list

let rec private cart xss =
    match xss with
    | [] -> [ [] ]
    | xs :: rest ->
        [ for x in xs do
              for r in cart rest do
                  yield x :: r ]

/// A pattern as the list of spaces it covers (or-patterns expand).
let rec private spaces (cases: string -> (string * int) list) p =
    let con c ps = [ for args in cart (List.map (spaces cases) ps) -> SCon(c, args) ]

    match p with
    | CPWild
    | CPVar _ -> [ SWild ]
    | CPAs(p, _, _) -> spaces cases p
    | CPInt n -> [ SCon({ name = string n; arity = 0; all = None }, []) ]
    | CPBool b ->
        let all = Some [ "true", 0; "false", 0 ]
        [ SCon({ name = (if b then "true" else "false"); arity = 0; all = all }, []) ]
    | CPTuple ps -> con { name = ","; arity = ps.Length; all = Some [ ",", ps.Length ] } ps
    | CPRecord(_, fs) ->
        // a record is one constructor; its name carries the field names, for messages
        let name = "{" + (fs |> List.map fst |> String.concat ";") + "}"
        con { name = name; arity = fs.Length; all = Some [ name, fs.Length ] } (List.map snd fs)
    | CPCtor(u, tag, ps) ->
        let all = cases u
        con { name = fst all[tag]; arity = ps.Length; all = Some all } ps
    | CPOr(a, b) -> spaces cases a @ spaces cases b

let rec private render (bare: string -> bool) s =
    let render = render bare

    let atomic s =
        match s with
        | SCon(c, _ :: _) when c.name <> "," && not (c.name.StartsWith "{") && not (bare c.name) -> "(" + render s + ")"
        | _ -> render s

    match s with
    | SCon(c, [ SWild ]) when bare c.name -> c.name
    | SWild -> "_"
    | SCon({ name = "," }, args) -> "(" + (args |> List.map render |> String.concat ", ") + ")"
    | SCon(c, args) when c.name.StartsWith "{" ->
        // { kind = C }: only the fields that matter
        let names = c.name.Trim('{', '}').Split ';'

        match List.zip (List.ofArray names) args |> List.filter (fun (_, a) -> a <> SWild) with
        | [] -> "_"
        | shown -> "{ " + (shown |> List.map (fun (n, a) -> n + " = " + render a) |> String.concat "; ") + " }"
    | SCon({ name = "::" }, [ h; t ]) -> atomic h + " :: " + render t
    | SCon(c, []) -> c.name
    | SCon(c, [ a ]) -> c.name + " " + atomic a
    | SCon(c, args) -> c.name + " (" + (args |> List.map render |> String.concat ", ") + ")"

let private wilds n = List.replicate n SWild

let private specialize (c: Con) rows =
    rows
    |> List.choose (fun row ->
        match row with
        | SCon(c2, args) :: rest when c2.name = c.name -> Some(args @ rest)
        | SWild :: rest -> Some(wilds c.arity @ rest)
        | _ -> None)

let private defaults rows =
    rows
    |> List.choose (fun row ->
        match row with
        | SWild :: rest -> Some rest
        | _ -> None)

let private rebuild (c: Con) w =
    SCon(c, List.take c.arity w) :: List.skip c.arity w

/// A value vector matched by q but by no row, if any.
let rec private useful (rows: Space list list) (q: Space list) : Space list option =
    match q with
    | [] -> if rows.IsEmpty then Some [] else None
    | SCon(c, args) :: rest -> useful (specialize c rows) (args @ rest) |> Option.map (rebuild c)
    | SWild :: rest ->
        let sigma =
            rows
            |> List.choose (fun row ->
                match row with
                | SCon(c, _) :: _ -> Some c
                | _ -> None)
            |> List.distinctBy (fun c -> c.name)

        let all = sigma |> List.tryHead |> Option.bind (fun c -> c.all)
        let seen n = sigma |> List.exists (fun c -> c.name = n)

        match all with
        | Some cs when List.forall (fst >> seen) cs ->
            cs
            |> List.tryPick (fun (n, a) ->
                let c = { name = n; arity = a; all = all }
                useful (specialize c rows) (wilds a @ rest) |> Option.map (rebuild c))
        | _ ->
            useful (defaults rows) rest
            |> Option.map (fun w ->
                let missing =
                    match all with
                    | Some cs ->
                        let n, a = cs |> List.find (fst >> seen >> not)
                        SCon({ name = n; arity = a; all = all }, wilds a)
                    | None -> SWild

                missing :: w)

/// Fails if a clause can never match or if some value matches no clause.
/// clauses: (pattern, has guard); guarded clauses don't count toward coverage.
/// bare: constructors whose payload is optional (active pattern cases), shown without it.
let check (cases: string -> (string * int) list) (bare: string -> bool) (clauses: (CPat * bool) list) =
    let mutable rows = []

    for p, guarded in clauses do
        let ps = spaces cases p

        if ps |> List.forall (fun s -> (useful rows [ s ]).IsNone) then
            fail 0 "this match case is never reached"

        if not guarded then
            rows <- rows @ (ps |> List.map (fun s -> [ s ]))

    match useful rows [ SWild ] with
    | Some w -> fail 0 (sprintf "match is not exhaustive; missing case: %s" (render bare w.Head))
    | None -> ()
