// Blocks inside brackets: a line ending in -> (or then, else, do) and deeper lines after it
// form a block, as at the top level. It ends at the bracket's closer, or at a line left of it.
type Parser<'a> = Parser of (list<char> -> option<'a * list<char>>)

let (<|>) p q =
  match (p, q) with
  | (Parser f, Parser g) ->
    Parser (fun cs ->
      match f cs with
      | Some r -> Some r
      | None -> g cs)

let (.>>.) p q =
  match (p, q) with
  | (Parser f, Parser g) ->
    Parser (fun cs ->
      match f cs with
      | Some (a, rest) ->
        match g rest with
        | Some (b, rest2) -> Some ((a, b), rest2)
        | None -> None
      | None -> None)

let run p (s: string) =
  match p with
  | Parser f -> f (String.chars s)

let item c =
  Parser (fun cs ->
    match cs with
    | x :: rest when x = c -> Some (x, rest)
    | _ -> None)

type Handler = { name: string; handle: int -> string }

let main () =
  let doubled =
    [ 1; 2; 3 ]
    |> List.map (fun x ->
      let y = x * 2
      y + 1)
  println $"{doubled}"
  let total = List.fold (fun acc x ->
    if x % 2 = 0 then acc + x
    else acc) 0 [ 1; 2; 3; 4 ]
  println $"{total}"
  let h =
    { name = "sign"
      handle = fun n ->
        if n < 0 then "negative"
        else "non-negative" }
  println $"{h.name}: {h.handle -3} {h.handle 4}"
  let parser = item 'a' .>>. (item 'b' <|> item 'c')
  println $"{run parser "ab"} {run parser "ac"} {run parser "ad"}"
  let fs =
    [ (fun x ->
        x + 1)
      (fun x -> x * 10) ]
  println $"{List.map (fun f -> f 5) fs}"
  List.iter (fun x ->
    print $"{x} "
  ) [ 1; 2 ]
  println ""
  0
