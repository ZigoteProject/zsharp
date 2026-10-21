// Phase 3 exit test: a Json derive written in Z#, round-tripping a record, a union and Tree<int>
type JsonValue =
  | JNull
  | JBool of bool
  | JNumber of f64
  | JString of string
  | JArray of list<JsonValue>
  | JObject of list<string * JsonValue>

trait Json<'a> =
  abstract toJson : 'a -> JsonValue
  abstract fromJson : JsonValue -> result<'a, string>

let Json.field name j =
  match j with
  | JObject kvs ->
      match List.tryFind (fun (k, _) -> k = name) kvs with
      | Some (_, v) -> Ok v
      | None -> Error $"missing key {name}"
  | _ -> Error "expected an object"

let Json.string j =
  match j with
  | JString s -> Ok s
  | _ -> Error "expected a string"

let Json.array j =
  match j with
  | JArray xs -> Ok xs
  | _ -> Error "expected an array"

let rec Json.at i xs =
  match xs with
  | [] -> Error "missing element"
  | x :: rest -> if i = 0 then Ok x else Json.at (i - 1) rest

impl Json<int> =
  let toJson n = JNumber (float n)
  let fromJson j =
    match j with
    | JNumber x -> Ok (int x)
    | _ -> Error "expected a number"

impl Json<f64> =
  let toJson x = JNumber x
  let fromJson j =
    match j with
    | JNumber x -> Ok x
    | _ -> Error "expected a number"

impl Json<string> =
  let toJson s = JString s
  let fromJson j = Json.string j

impl Json<option<'a>> =
  let toJson o =
    match o with
    | Some x -> toJson x
    | None -> JNull
  let fromJson j =
    match j with
    | JNull -> Ok None
    | _ -> Result.map Some (fromJson j)

derive Json =
  let toJson (x: 'self) =
    match Shape.of x with
    | Record r ->
        let mutable fields = []
        for f in r.fields do
          fields <- (f.name, toJson f.value) :: fields
        JObject (List.rev fields)
    | Union c ->
        let mutable args = []
        for f in c.fields do
          args <- toJson f.value :: args
        JObject [ ("case", JString c.name); ("fields", JArray (List.rev args)) ]

  let fromJson (j: JsonValue) : result<'self, string> =
    match Shape.kind with
    | RecordKind -> Shape.build (fun f -> Json.field f.name j |> Result.bind fromJson)
    | UnionKind ->
        let name = (Json.field "case" j |> Result.bind Json.string)?
        let args = (Json.field "fields" j |> Result.bind Json.array)?
        match Shape.buildCase name (fun f -> Json.at f.index args |> Result.bind fromJson) with
        | Some built -> built
        | None -> Error $"unknown case {name}"

[<Derive(Json)>]
type User = { name: string; age: int; email: option<string> }

[<Derive(Json)>]
type Shape =
  | Circle of radius: f64
  | Rect of w: f64 * h: f64
  | Dot

[<Derive(Json)>]
type Tree<'a> =
  | Leaf
  | Node of Tree<'a> * 'a * Tree<'a>

let join xs = List.fold (fun acc s -> if acc = "" then s else acc + ", " + s) "" xs

let rec render j =
  match j with
  | JNull -> "null"
  | JBool b -> string b
  | JNumber x -> string x
  | JString s -> "\"" + s + "\""
  | JArray xs -> "[" + join (List.map render xs) + "]"
  | JObject kvs -> "{" + join (List.map (fun (k, v) -> "\"" + k + "\": " + render v) kvs) + "}"

let roundTrip x =
  let j = toJson x
  match fromJson j with
  | Ok y -> println $"{render j}  ->  same: {y = x}"
  | Error e -> println $"error: {e}"

let main () =
  roundTrip { name = "ada"; age = 36; email = None }
  roundTrip { name = "bob"; age = 7; email = Some "b@x.org" }
  roundTrip (Rect (2.0, 3.5))
  roundTrip Dot
  roundTrip (Node (Node (Leaf, 1, Leaf), 2, Leaf))
  let bad: result<User, string> = fromJson (JObject [ ("name", JString "eve") ])
  match bad with
  | Ok _ -> println "unexpected"
  | Error e -> println $"error: {e}"
  0
