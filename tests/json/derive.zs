// The ToJson and FromJson derives and Core's impls (0023): keys by field name, defaults for
// absent keys, unions by case, and errors that say where
[<Derive(Json)>]
type User = { name: string; age: int = 18; email: option<string> = None; ``first-name``: string = "" }

[<Derive(FromJson)>]
type Reply = { users: list<User>; next: option<string> = None }

[<Derive(Json)>]
type Shape =
  | Circle of f64
  | Rect of f64 * f64
  | Dot

let read (text: string) : result<Reply, string> =
  result {
    let! doc = Json.parse text
    let! reply = fromJson doc
    return reply
  }

let shape (j: Json) =
  let s: result<Shape, string> = fromJson j
  match s with
  | Ok s -> println $"{toJson s}"
  | Error e -> println e

let main () =
  println (Json.print (toJson { name = "ada"; age = 36; ``first-name`` = "Ada" }))
  match read "{\"users\": [{\"name\": \"ada\"}, {\"name\": \"bob\", \"age\": 7, \"extra\": true}]}" with
  | Ok r ->
    println $"{List.length r.users} users, aged {(List.head r.users).age} and {(List.item 1 r.users).age}"
  | Error e -> println e
  // errors, at their places
  for text in [ "{\"users\": [{\"name\": \"ada\"}, {\"name\": \"bob\", \"email\": 42}]}"
    "{\"users\": [{\"age\": 3}]}"
    "{\"users\": 7}"
    "[1, 2" ] do
    match read text with
    | Ok _ -> println "unexpected"
    | Error e -> println e
  // unions: a case without fields as its name, and both spellings read back
  shape (toJson Dot)
  shape (toJson (Rect (2.0, 3.5)))
  shape (JObject [ ("case", JString "Dot") ])
  shape (JObject [ ("case", JString "Circle"); ("fields", JArray [ JInt 2 ]) ])
  shape (JString "Triangle")
  shape (JObject [ ("case", JString "Rect"); ("fields", JArray [ JInt 1 ]) ])
  shape (JObject [ ("case", JInt 1) ])
  // Core's impls: numbers in range, characters, collections
  let small: result<u8, string> = fromJson (JInt (i64 300))
  let wide: result<i32, string> = fromJson (JNumber 3000000000.0)
  let whole: result<int, string> = fromJson (JNumber 7.0)
  let half: result<int, string> = fromJson (JNumber 7.5)
  let letter: result<char, string> = fromJson (JString "é")
  println $"{small} {wide} {whole} {half} {letter}"
  let counts = Map.ofList [ ("b", 2); ("a", 1) ]
  println (Json.print (toJson counts))
  let back: result<Map<string, int>, string> = fromJson (toJson counts)
  println $"{Result.map Map.toList back = Ok (Map.toList counts)}"
  let bad: result<Map<string, int>, string> =
    fromJson (JObject [ ("a", JInt 1); ("b", JString "two") ])
  println $"{bad}"
  let xs: result<array<list<option<bool>>>, string> =
    fromJson (JArray [ JArray [ JBool true; JNull ]; JArray [] ])
  println $"{xs |> Result.map (fun a -> Array.length a)}"
  let ys: result<list<f64>, string> = fromJson (JArray [ JInt 1; JNumber 2.5; JString "3" ])
  println $"{ys}"
  println (Json.print (toJson (u64 0xFFFF_FFFF_FFFF_FFFF)))
  0
