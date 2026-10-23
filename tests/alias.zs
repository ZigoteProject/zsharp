// Type aliases, as F#'s abbreviations: another name for a type, the same type wherever it's
// written; a literal with a unit takes its number type from where it goes
[<Measure>]
type ms

type Millis = i64<ms>

type Pair<'a> = 'a * 'a

type Names = list<string>

type Handler = int -> int

let twice (d: Millis) : Millis = d * i64 2

let swap (p: Pair<int>) : Pair<int> = (snd p, fst p)

let apply (h: Handler) x = h x

type Timing = { name: string; took: Millis }

let main () =
  let d: Millis = 5<ms>
  let total = twice d + 3<ms>
  let names: Names = [ "a"; "b" ]
  let t = { name = "build"; took = -1<ms> }
  println $"{total} {swap (1, 2)} {List.length names} {apply (fun x -> x + 1) 41} {t.took + 250<ms>}"
  0
