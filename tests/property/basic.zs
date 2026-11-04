// properties (0010, track D item 5): generators over a stream of bytes, sampled from a seed (the
// same values on every run), Arbitrary for Core's types and derived for records and unions, the
// gen { } builder, and testProperty: cases drawn at the parameter's type, growing in size; a
// failing case shrunk to a smallest one (shorter bytes, then smaller) and shown with its seed
open Testing

[<Derive(Arbitrary, Binary)>]
type Shape =
  | Dot
  | Circle of int
  | Rect of int * int

[<Derive(Arbitrary, Binary)>]
type Packet = { id: u16; flags: list<bool>; body: Shape }

let area (s: Shape) =
  match s with
  | Dot -> 0
  | Circle r -> 3 * r * r
  | Rect(w, h) -> w * h

let main () =
  println $"{Gen.sample (u64 7) 6 Gen.int}"
  println $"{Gen.sample (u64 7) 4 (Gen.range 10 20)}"
  println $"{Gen.sample (u64 7) 3 (Gen.list Gen.bool)}"
  println $"{Gen.sample (u64 7) 3 Gen.string}"
  println $"{Gen.sample (u64 7) 3 (arbitrary () : Gen<Packet>)}"
  let email =
    gen {
      let! user = Gen.elements [ "ann"; "bob"; "cy" ]
      let! n = Gen.range 0 99
      return $"{user}{n}@example.com"
    }
  println $"{Gen.sample (u64 1) 3 email}"
  Testing.runAll [
    testList "props" [
      testProperty "reverse twice" (fun (xs: list<int>) -> List.rev (List.rev xs) = xs)
      testProperty "append length" (fun (xs: list<int>, ys: list<int>) ->
        List.length (List.append xs ys) = List.length xs + List.length ys)
      testProperty "area of a circle" (fun (r: int) -> area (Circle r) >= 0)
      testPropertyWith { runs = 200; seed = Some (u64 42) } "a packet round-trips through Binary" (fun (p: Packet) ->
        Binary.ofBytes (Binary.toBytes p) = Ok p)
      testProperty "a filtered generator" (fun (n: int) ->
        Gen.sample (u64 3) 1 (Gen.filter (fun k -> k % 2 = 0) Gen.int)
        |> List.forall (fun k -> k % 2 = 0))
      testPropertyWith { seed = Some (u64 42) } "sums stay small" (fun (xs: list<int>) ->
        List.sum xs < 10)
    ]
  ]
