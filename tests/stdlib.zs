// Phase 3: stdlib core
let main () =
  let xs = [ 5; 3; 8; 1; 3 ]
  let empty: list<int> = []
  println $"{List.sort xs} {List.sortBy (fun x -> -x) xs} {List.distinct xs} {List.max xs} {List.min xs}"
  println $"{List.take 2 xs} {List.skip 3 xs} {List.item 2 xs} {List.last xs} {List.tryHead empty}"
  let letters = [ "a"; "b" ]
  println $"{List.zip [ 1; 2 ] letters} {List.partition (fun x -> x > 3) xs} {List.choose (fun x -> if x > 4 then Some (x * 10) else None) xs}"
  println $"{List.collect (fun x -> [ x; x ]) [ 1; 2 ]} {List.indexed letters} {List.sumBy (fun x -> x * 2) xs} {List.reduce (fun a b -> a * b) [ 1; 2; 3; 4 ]}"
  let a = [| 4; 2; 9 |]
  println $"{Array.toList (Array.sort a)} {Array.toList (Array.rev a)} {Array.contains 9 a} {Array.toList (Array.sub a 1 2)} {Array.toList (Array.filter (fun x -> x > 3) a)}"
  let s = "  Hello, World  "
  let t = s.Trim()
  let (world, hell, x, o, comma, dash, l, bigL, ab) = ("World", "Hell", "x", "o", ", ", "-", "l", "L", "ab")
  println $"[{t}] {t.ToUpper()} {t.ToLower()} {t.Contains(world)} {t.StartsWith(hell)} {t.EndsWith(x)} {t.IndexOf(o)}"
  println $"{String.split comma t} {String.join dash [ x; o; l ]} {t.Replace(l, bigL)} {t.Substring(7, 5)} {String.repeat 3 ab}"
  let (n1, n2, n3, f1, f2) = ("123", "-45", "12x", "2.5", "nope")
  println $"{String.parseInt n1} {String.parseInt n2} {String.parseInt n3} {String.parseFloat f1} {String.parseFloat f2}"
  let none = "none"
  let oops: result<int, string> = Error "oops"
  println $"{Option.toResult none (Some 1)} {Result.mapError String.length oops} {Result.toOption (Ok 3)} {Option.orElse (Some 2) None}"
  let (p, q) = ((1, "a"), (1, "b"))
  println $"{p = p} {p = q} {compare p q} {p < q} {hash p = hash p}"
  match Console.readLine () with
  | Some line -> Console.println $"read: {line}"
  | None -> Console.println "no input"
  0
