// Phase 3 exit test, over Core's Json (0023): a record, a union and Tree<int> round-trip through
// [<Derive(Json)>]
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

let roundTrip x =
  let j = toJson x
  match fromJson j with
  | Ok y -> println $"{j}  ->  same: {y = x}"
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
