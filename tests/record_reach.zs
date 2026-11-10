// A record of a module that isn't opened, used without saying its type: the one record anywhere
// with the fields is meant (a field read, a literal, a pattern), a literal's first field may name
// its module or type as in F#, and a field may be named as a keyword in backticks, which is its
// JSON key
[<Derive(Json)>]
type Reaction = { ``type``: string; emoji: string }

let main () =
  let texts = ReachDb.lines () |> List.map (fun l -> l.text)
  let first l = l.who + "!"
  let made = { id = 3; text = "made"; who = "c" }
  let named = { ReachDb.id = 4; text = "named"; who = "d" }
  let typed = { Line.id = 5; text = "typed"; who = "e" }
  let ({ who = w }) = made
  println $"{texts} {first made} {named.id} {typed.text} {w}"
  let r = { ``type`` = "emoji"; emoji = "+1" }
  println $"{Json.print (toJson r)} {r.``type``}"
  let back: result<Reaction, string> = fromJson (toJson r)
  println $"{Result.isOk back}"
