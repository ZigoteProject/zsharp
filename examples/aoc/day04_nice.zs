// Doesn't He Have Intern-Elves For This? (2015, day 5): a nice string has three vowels, a
// letter twice in a row, and none of ab, cd, pq, xy; by the new rules, a pair of letters that
// appears twice without overlapping, and a letter that repeats with one letter between
let input =
  "ugknbfddgicrmopn\naaa\njchzalrnumimnmhp\nhaegwjzuvuyypxyu\ndvszwmarrgswjxmb\nqjhvhtzxzqqjkmpb\nxxyxx\nuurcxstgmygtbstg\nieodomkazucvgmuy"

let pairs (cs: list<char>) = List.zip cs (List.tail cs)

let nice (s: string) =
  let cs = String.chars s
  let vowels = List.length (List.filter (fun c -> String.contains (string c) "aeiou") cs)
  let doubled = List.exists (fun (a, b) -> a = b) (pairs cs)
  let banned = List.exists (fun bad -> String.contains bad s) [ "ab"; "cd"; "pq"; "xy" ]
  vowels >= 3 && doubled && not banned

let nicer (s: string) =
  let cs = String.chars s
  let n = List.length cs
  let pairTwice =
    List.exists (fun i -> String.contains (String.sub s i 2) (String.sub s (i + 2) (n - i - 2))) (List.init (max 0 (n - 3)) (fun i ->
        i))
  let repeat =
    List.exists (fun i -> List.item i cs = List.item (i + 2) cs) (List.init (max 0 (n - 2)) (fun i ->
        i))
  pairTwice && repeat

let main () =
  let strings = String.splitLines input
  println $"part 1: {List.length (List.filter nice strings)}"
  println $"part 2: {List.length (List.filter nicer strings)}"
  0
