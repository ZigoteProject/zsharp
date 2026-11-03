// Word frequencies: a generated text of n words (capitals, punctuation, line breaks), split into
// lowercase words, counted in a hash table and sorted by count, then word. What a log or text
// tool does: scanning bytes, small strings, hashing, sorting.
let syllables = [| "ka"; "lo"; "mi"; "ne"; "ru"; "sa"; "to"; "vi"; "an"; "el"; "or"; "us"; "be"; "di"; "fu"; "go" |]

let vocabulary = 50000

let next (seed: int) = (seed * 1103515245 + 12345) % 2147483648

// word v: v's base-16 digits as syllables, so every index has its own word
let word (v: int) =
  let mutable s = syllables.[v % 16]
  let mutable rest = v / 16
  while rest > 0 do
    s <- s + syllables.[rest % 16]
    rest <- rest / 16
  s

let generate (n: int) =
  let words = Array.init vocabulary word
  let mutable out = Bytes.writerOf Buffer.empty
  let mutable seed = 42
  let mutable capital = true
  for _ in 1 .. n do
    seed <- next seed
    let x = seed % vocabulary
    let w = words.[x * x / vocabulary] // small indexes are common, as words are in text
    if capital then
      let b = String.bytes w
      out <- out |> Bytes.put (b.[0] - u8 32) |> Bytes.append b.[1..]
    else out <- Bytes.appendUtf8 w out
    seed <- next seed
    capital <- seed % 20 = 0
    let sep =
      match seed % 20 with
      | 0 -> ". "
      | 1 -> ", "
      | 2 -> "\n"
      | _ -> " "
    out <- Bytes.appendUtf8 sep out
  String.ofBytes (Bytes.written out)

let isLetter (b: u8) = (b >= u8 'a' && b <= u8 'z') || (b >= u8 'A' && b <= u8 'Z')

let count (text: string) =
  let bytes = String.bytes text
  let n = Span.length bytes
  let mutable counts = HashMap.empty
  let mutable total = 0
  let mutable i = 0
  while i < n do
    if isLetter bytes.[i] then
      let start = i
      while i < n && isLetter bytes.[i] do
        i <- i + 1
      let w = String.toLower (String.sub text start (i - start))
      let seen = Option.defaultValue 0 (HashMap.tryFind w counts)
      counts <- HashMap.add w (seen + 1) counts
      total <- total + 1
    else i <- i + 1
  (total, counts)

let main () =
  let n =
    match Environment.args () with
    | a :: _ -> Option.defaultValue 1000000 (String.parseInt a)
    | [] -> 1000000
  let (total, counts) = count (generate n)
  let sorted = HashMap.toList counts |> List.sortWith (fun (w1, c1) (w2, c2) -> if c1 <> c2 then compare c2 c1 else compare w1 w2)
  println $"{total} words, {HashMap.count counts} distinct"
  for (w, c) in List.take (min 10 (List.length sorted)) sorted do
    println $"{w} {c}"
  0
