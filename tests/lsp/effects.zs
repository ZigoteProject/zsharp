effect Log =
  abstract log : string -> unit

let greet name =
  Log.log $"hello {name}"

let main () =
  handle greet "you" with
  | Log.log s, k ->
    println s
    k ()
  0
