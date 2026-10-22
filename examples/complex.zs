// A bank ledger: parses commands from text, applies them to accounts, and reports.
// Shows records, unions, active patterns, result with ?, Map, a custom operator and modules.
// Run with: zs run examples/complex.zs

type Command =
  | Open of name: string
  | Deposit of name: string * amount: int
  | Withdraw of name: string * amount: int
  | Transfer of from: string * dest: string * amount: int

type Account = { name: string; balance: int = 0; history: list<string> = [] }

// ---- parsing

let (|Amount|_|) (s: string) =
  match String.parseInt s with
  | Some n when n > 0 -> Some n
  | _ -> None

let amount (s: string) =
  match s with
  | Amount n -> Ok n
  | _ -> Error $"not a positive amount: {s}"

let parse (line: string) =
  match String.split " " line |> List.filter (fun w -> w <> "") with
  | [ verb; name ] when verb = "open" -> Ok (Open name)
  | [ verb; name; n ] when verb = "deposit" ->
    let n = amount n?
    Ok (Deposit (name, n))
  | [ verb; name; n ] when verb = "withdraw" ->
    let n = amount n?
    Ok (Withdraw (name, n))
  | [ verb; a; arrow; b; n ] when verb = "transfer" && arrow = "->" ->
    let n = amount n?
    Ok (Transfer (a, b, n))
  | _ -> Error $"cannot parse: {line}"

// ---- the ledger

module Ledger =
  let private find name accounts =
    Map.tryFind name accounts |> Option.toResult $"no account: {name}"

  // record a change to an account: new balance plus a history line
  let (<+) (acc: Account) (delta, note) =
    { acc with balance = acc.balance + delta; history = note :: acc.history }

  let apply accounts cmd =
    match cmd with
    | Open name when Map.containsKey name accounts -> Error $"already open: {name}"
    | Open name -> Ok (Map.add name { name = name } accounts)
    | Deposit (name, n) ->
      let acc = find name accounts?
      Ok (Map.add name (acc <+ (n, $"+{n}")) accounts)
    | Withdraw (name, n) ->
      let acc = find name accounts?
      if acc.balance < n then Error $"{name} has {acc.balance}, cannot withdraw {n}"
      else Ok (Map.add name (acc <+ (-n, $"-{n}")) accounts)
    | Transfer (a, b, n) ->
      let src = find a accounts?
      let dst = find b accounts?
      if src.balance < n then Error $"{a} has {src.balance}, cannot send {n}"
      else
        accounts
        |> Map.add a (src <+ (-n, $"-{n} to {b}"))
        |> Map.add b (dst <+ (n, $"+{n} from {a}"))
        |> Ok

// parse then apply; any failure is reported and the accounts stay as they were
let run accounts line =
  let step =
    match parse line with
    | Ok cmd -> Ledger.apply accounts cmd
    | Error e -> Error e
  match step with
  | Ok next -> (next, None)
  | Error e -> (accounts, Some e)

let script =
  [ "open ada"
    "open alan"
    "deposit ada 500"
    "deposit alan 120"
    "transfer ada -> alan 200"
    "withdraw alan 1000"
    "open ada"
    "deposit bob 10"
    "withdraw ada 50"
    "deposit alan -5"
    "fly to mars" ]

let main () =
  let mutable accounts = Map.empty
  let mutable errors = []
  for line in script do
    let (next, err) = run accounts line
    accounts <- next
    match err with
    | Some e -> errors <- e :: errors
    | None -> ()
  for (_, acc) in Map.toList accounts do
    println $"{acc.name}: {acc.balance}  {List.rev acc.history}"
  let total = Map.toList accounts |> List.sumBy (fun (_, a) -> a.balance)
  println $"total {total}, {List.length errors} rejected:"
  for e in List.rev errors do
    println $"  {e}"
  0
