/// A module whose functions perform effects: its callers in other modules handle them.
module Tokens

/// The tokens of a line: words, yielded one at a time.
let words (line: string) =
  let mutable word = ""
  for c in line do
    if c = ' ' then
      if word <> "" then Yield.yield word
      word <- ""
    else word <- word + string c
  if word <> "" then Yield.yield word

/// A token that must be a number.
let number (w: string) : int / Throw<string> =
  match String.parseInt w with
  | Some n -> n
  | None -> Throw.throw $"not a number: {w}"

/// The sum of a line's numbers, failing at the first token that isn't one.
let sum (line: string) =
  let mutable total = 0
  for w in Seq(fun () -> words line) do total <- total + number w
  total

/// Each element through f: generic in f's effects only, so this module has the code of its
/// pure instance, and a module using it with effects makes its own.
let each (f: string -> unit) (xs: list<string>) = List.iter f xs
