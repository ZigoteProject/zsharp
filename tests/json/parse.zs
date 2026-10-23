// Json.parse, print and pretty (0023): documents round-trip, numbers keep their kind, strings
// their escapes, and every malformed document says where
let show (text: string) =
  match Json.parse text with
  | Ok j -> println (Json.print j)
  | Error e -> println $"error {e}"

let main () =
  show "{\"a\": 1, \"b\": [true, false, null], \"c\": {\"d\": -2.5e3}}"
  show "  [ 0, -0, 9223372036854775807, -9223372036854775808, 9223372036854775808, 1.0, 0.1 ]  "
  show "\"tab\\there, a \\\"quote\\\", \\u00e9 and \\ud83d\\ude00\""
  show "\"é and 😀 as written\""
  show "[]"
  show "{}"
  // the problems, each at its line and column
  show "{\"a\": 1,}"
  show "[1, 2"
  show "{\"a\" 1}"
  show "01"
  show "1."
  show "-"
  show "\"\\x\""
  show "\"\\ud800\""
  show "[1]\n  x"
  show "tru"
  show ""
  show (String.repeat 1001 "[" + String.repeat 1001 "]")
  match Json.parseWith { depth = 2000 } (String.repeat 1001 "[" + String.repeat 1001 "]") with
  | Ok _ -> println "1,001 levels under a limit of 2,000"
  | Error e -> println e
  // printing: compact, pretty, escapes, numbers that aren't finite
  let doc =
    JObject [ ("name", JString "ada \"the\" first\n")
      ("tags", JArray [ JInt 1; JNumber 2.0; JBool true ])
      ("none", JObject []) ]
  println (Json.print doc)
  println (Json.pretty doc)
  println (Json.print (JArray [ JNumber (0.0 / 0.0); JNumber (1.0 / 0.0) ]))
  println $"{doc}"
  0
