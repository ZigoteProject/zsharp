// Two modules that aren't opened have a record with the field: neither is meant without its name;
// and a private record's fields aren't reached from outside its module
let main () =
  let ids = ReachLog.entries () |> List.map (fun e -> e.id)
  let all = ReachDb.lines ()
  let pick l = l.text
  let hidden = { token = "t" }
  let wrong = { ReachLog.id = 1; text = "x"; who = "y" }
  println $"{ids} {List.length all}"
