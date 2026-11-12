// Json.print and Json.pretty write into one growing Buffer: an escape at every place in a string
// around the 16 bytes scanned at a time, every control character, integers of every length,
// documents past the Buffer's first size, and each text read back as the document it came from
let controls = String.concat [ for c in 0 .. 31 -> string (char c) ]

let times (n: int) (s: string) = String.concat [ for _ in 1 .. n -> s ]

// strings of `n` bytes and more with `mark` at each place, and at two places
let markedOf (mark: string) (n: int) : list<Json> =
  let both (at: int) =
    let one = JString (times at "a" + mark + times (n - at) "b")
    [ one; JString (mark + times at "é" + mark + times (n - at) "b") ]
  List.collect both [ for at in 0 .. n -> at ]

let marked (mark: string) : list<Json> = List.collect (markedOf mark) [ for n in 0 .. 40 -> n ]

let integers : list<Json> =
  let lowest = JInt (i64 -9223372036854775807 - i64 1)
  let highest = JUInt (u64 9223372036854775807 * u64 2 + u64 1)
  let mutable all = [ JInt (i64 0); lowest; highest ]
  let mutable p = i64 1
  for _ in 1 .. 18 do
    all <- JInt p :: JInt (-p) :: JInt (p * i64 10 - i64 1) :: all
    p <- p * i64 10
  all

let rec nested (depth: int) : Json =
  if depth = 0 then
    JArray []
  else
    JObject [ ("k", JArray [ nested (depth - 1); JObject [] ]); ("n", JNull) ]

let main () =
  println (Json.print (JString controls))
  let notFinite = [ JNumber (0.0 / 0.0); JNumber (1.0 / 0.0) ]
  println (Json.print (JArray (JNumber 0.1 :: JNumber -2.5e3 :: JBool true :: JBool false :: notFinite)))
  println (Json.print (JArray integers))
  println (Json.pretty (nested 3))
  let inner = JObject [ ("x", JString "\n") ]
  println (Json.pretty (JObject [ ("a\"b", JArray [ JInt (i64 1) ]); ("", inner) ]))

  // many documents, compared as a whole by their hash; each reads back as itself
  let marks = [ "\""; "\\"; "\n"; "\u{1}"; "\u{1f}"; " " ]
  let doc = JArray (List.append (List.collect marked marks) integers)
  let compact = Json.print doc
  let pretty = Json.pretty doc
  println $"{String.length compact} bytes {Hex.encode (Sha256.hash (String.bytes compact))}"
  println $"{String.length pretty} bytes {Hex.encode (Sha256.hash (String.bytes pretty))}"
  println $"{Json.parse compact = Ok doc} {Json.parse pretty = Ok doc}"
  0
