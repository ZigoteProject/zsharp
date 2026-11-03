// JSON, as a web service handles it: a generated document of n user records is parsed, decoded
// into typed records ([<Derive(Json)>]), summarised, and the active users encoded back to JSON.
// Parsing bytes, small strings and floats, allocating a document tree, and building text.
[<Derive(Json)>]
type Address = { city: string; zip: string }

[<Derive(Json)>]
type User =
  { id: int
    name: string
    email: string
    age: int
    score: f64
    active: bool
    tags: list<string>
    address: Address
    note: string }

let next (seed: int) = (seed * 1103515245 + 12345) % 2147483648

let notes = [| "ok"; "said \"hi\""; "line one\nline two"; "" |]

let record (i: int) (r: int) (out: Bytes.Writer) =
  let score = float (r % 4000) + 0.25 * float (1 + r % 3)
  let tags = [ for t in 0 .. r % 4 -> $"\"t{(r / 7 + t * 3) % 10}\"" ]
  out
  |> Bytes.appendUtf8 $"  {{\"id\": {i}, \"name\": \"user{i}\", \"email\": \"user{i}@example.com\", "
  |> Bytes.appendUtf8 $"\"age\": {18 + r % 60}, \"score\": {score}, \"active\": {r % 3 <> 0}, "
  |> Bytes.appendUtf8 $"\"tags\": [{String.join ", " tags}], "
  |> Bytes.appendUtf8 $"\"address\": {{\"city\": \"city{r % 100}\", \"zip\": \"{10000 + r % 90000}\"}}, \"note\": "
  |> Bytes.appendJsonString notes.[r % 4]
  |> Bytes.appendUtf8 "}"

let generate (n: int) =
  let mutable out = Bytes.writerOf Buffer.empty |> Bytes.appendUtf8 "[\n"
  let mutable seed = 7
  for i in 0 .. n - 1 do
    seed <- next seed
    out <- record i seed out |> Bytes.appendUtf8 (if i < n - 1 then ",\n" else "\n")
  String.ofBytes (Bytes.written (Bytes.appendUtf8 "]\n" out))

let decode (text: string) : result<list<User>, string> =
  result {
    let! doc = Json.parse text
    let! users = fromJson doc
    return users
  }

let main () =
  let n =
    match Environment.args () with
    | a :: _ -> Option.defaultValue 200000 (String.parseInt a)
    | [] -> 200000
  let text = generate n
  match decode text with
  | Error e ->
    println $"error: {e}"
    1
  | Ok users ->
    let active = List.filter (fun u -> u.active) users
    let ages = List.sumBy (fun u -> u.age) active
    let score = List.sumBy (fun u -> u.score) users
    let tagged = users |> List.filter (fun u -> List.contains "t3" u.tags) |> List.length
    let out = Json.print (toJson active)
    println $"{String.length text} bytes in, {List.length users} users, {List.length active} active"
    println $"ages {ages}, score {score:F2}, tagged t3 {tagged}"
    println $"{String.length out} bytes out"
    0
