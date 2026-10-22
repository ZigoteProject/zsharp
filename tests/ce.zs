// Computation expressions: option { } and result { } (builders in Option.Builder and
// Result.Builder), and `use`, which disposes what it binds at the end of its scope
type Resource = Resource of string

impl Dispose<Resource> =
  let dispose (Resource name) = println $"  {name} closed"

let parse (s: string) =
  match String.parseInt s with
  | Some n -> Ok n
  | None -> Error $"'{s}' isn't a number"

let positive (n: int) = if n > 0 then Ok n else Error $"{n} isn't positive"

// the first error stops the rest
let ratio (a: string) (b: string) =
  result {
    let! x = parse a
    let! y = parse b
    let! d = positive y
    return x / d
  }

let lookup (key: string) = if key = "a" then Some 1 else if key = "b" then Some 2 else None

// a for loop that stops at the first key missing
let count (keys: list<string>) =
  option {
    for k in keys do
      let! v = lookup k
      if v > 1 then
        println $"  {k} is big"
    return List.length keys
  }

let opened (name: string) =
  result {
    use r = Resource name
    let! n = parse name
    return n * 2
  }

let main () =
  println $"{ratio "84" "2"} {ratio "84" "x"} {ratio "84" "0"}"
  println $"{option { return 1 }}"
  println $"{count [ "a"; "b" ]} {count [ "a"; "z" ]}"
  println "opened:"
  println $"{opened "21"}"
  println $"{opened "file"}"
  // use in plain code: disposed after the rest of the block
  let shown =
    use r = Resource "plain"
    println "  using it"
    5
  println $"shown {shown}"
  0
