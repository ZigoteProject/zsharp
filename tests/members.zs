// Phase 3: members, static members, named/optional/default arguments, type extensions
type Vec =
  { x: f64; y: f64 }
  member v.Length = v.x * v.x + v.y * v.y
  member v.Add(o: Vec) = { x = v.x + o.x; y = v.y + o.y }
  member v.Scale(k) = { x = v.x * k; y = v.y * k }
  static member Zero = { x = 0.0; y = 0.0 }
  static member Of(x, ?y = x) = { x = x; y = y }

type Shape =
  | Circle of radius: f64
  | Square of side: f64
  member s.Area =
    match s with
    | Circle r -> 3.0 * r * r
    | Square a -> a * a
  member s.Grow(?by: f64 = 1.0) =
    match s with
    | Circle r -> Circle (r + by)
    | Square a -> Square (a + by)

type Http =
  static member Get(url: string, ?timeout: int = 30, ?retries = timeout / 10, ?tag: string) =
    let t = Option.defaultValue "none" tag
    $"GET {url} timeout={timeout} retries={retries} tag={t}"

type Stack<'a> =
  { items: list<'a> }
  member s.Push(x) = { items = x :: s.items }
  member s.Peek = List.head s.items
  member s.Size = s.items.Length

let main () =
  let v = Vec.Of(3.0, y = 4.0)
  println $"length {v.Length} add {(v.Add(Vec.Of 1.0)).x} zero {Vec.Zero.Length} scaled {(v.Scale 2.0).y}"
  let shapes = [ Circle 1.0; Square 2.0 ]
  println $"areas {List.fold (fun acc (s: Shape) -> acc + s.Area) 0.0 shapes} grown {(Square(side = 2.0)).Grow().Area} {(Circle 0.0).Grow(by = 2.0).Area}"
  println (Http.Get("a.org"))
  println (Http.Get("b.org", 50, tag = "x"))
  println (Http.Get("c.org", retries = 7))
  let s = { items = [] }.Push(1).Push(2)
  let words = { items = [ "a" ] }.Push("b")
  println $"stack {s.Peek} size {s.Size} {words.Peek}"
  let greeting = "hello"
  println $"lengths {greeting.Length} {[1; 2; 3].Length} {[| 1 |].Length} {(Some 1).IsSome}"
  0
