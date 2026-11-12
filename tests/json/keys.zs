// A derived fromJson finds a record's keys in any order: the first of a repeated key, with keys
// it doesn't know between them, a default or None for an absent one, and each error at its key
[<Derive(Json)>]
type Point = { x: int; y: int; label: option<string>; scale: f64 = 1.0 }

[<Derive(Json)>]
type Line = { from: Point; ``to``: Point; tags: list<string> }

let show (text: string) =
  match (Json.parse text |> Result.bind fromJson : result<Point, string>) with
  | Ok p -> println $"{p.x} {p.y} {p.label} {p.scale}"
  | Error e -> println $"error {e}"

let main () =
  show "{\"x\": 1, \"y\": 2, \"label\": \"a\", \"scale\": 2.5}"
  show "{\"scale\": 2.5, \"label\": \"a\", \"y\": 2, \"x\": 1}"
  show "{\"x\": 1, \"y\": 2}"
  show "{\"y\": 2, \"x\": 1}"
  show "{\"x\": 1, \"x\": 9, \"y\": 2, \"y\": 8}"
  show "{\"y\": 2, \"x\": 1, \"y\": 8, \"x\": 9}"
  show "{\"x\": 1, \"other\": [1, {\"x\": 5}], \"y\": 2, \"label\": null, \"more\": 0, \"scale\": 3}"
  show "{\"other\": 0, \"x\": 1, \"y\": 2, \"label\": \"last\"}"
  show "{\"x\": 1, \"label\": \"no y\"}"
  show "{\"x\": 1, \"y\": \"two\"}"
  show "{\"y\": 2, \"x\": 1, \"label\": 3}"
  show "{}"
  show "[1, 2]"
  let line =
    "{\"tags\": [\"a\", \"b\"], \"to\": {\"y\": 4, \"x\": 3}, \"from\": {\"x\": 1, \"y\": 2}}"
  match (Json.parse line |> Result.bind fromJson : result<Line, string>) with
  | Ok l -> println $"{l.from.x} {l.from.y} {l.``to``.x} {l.``to``.y} {l.tags}"
  | Error e -> println $"error {e}"
  let bad =
    "{\"from\": {\"x\": 1, \"y\": 2}, \"to\": {\"x\": 3, \"y\": 4}, \"tags\": [\"a\", 7, \"c\"]}"
  match (Json.parse bad |> Result.bind fromJson : result<Line, string>) with
  | Ok _ -> println "read"
  | Error e -> println $"error {e}"
  0
