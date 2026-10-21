type JsonValue =
  | JNull
  | JNumber of f64

trait Json<'a> =
  abstract toJson : 'a -> JsonValue

impl Json<int> =
  let toJson n = JNumber (float n)

derive Json =
  let toJson (x: 'self) =
    match Shape.of x with
    | Record r ->
        let mutable last = JNull
        for f in r.fields do
          last <- toJson f.value
        last
    | Union c -> JNull

[<Derive(Json)>]
type Callback = { id: int; run: int -> int }

let main () = 0
