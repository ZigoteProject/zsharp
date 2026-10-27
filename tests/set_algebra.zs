// Set's union, intersect and difference (the smaller set walked, a result built balanced from its
// sorted elements, an empty or unchanged side given back as it is) and List.collect (linear),
// against plain list versions: random sets of every overlap, then adds and removes on the results
let seed = ref 12345

let next (bound: int) : int =
  seed.Value <- (seed.Value * 1103515245 + 12345) % 2147483648
  seed.Value / 65536 % bound

let randomList () : list<int> = List.init (next 40) (fun _ -> next 60)

let sorted (xs: list<int>) : list<int> = List.sort (List.distinct xs)

let main () =
  let bad = ref 0
  for _ in 1 .. 2000 do
    let xs = randomList ()
    // b is a's subset, its superset, disjoint from it, equal to it, or random
    let ys =
      match next 5 with
      | 0 -> List.filter (fun x -> x % 2 = 0) xs
      | 1 -> List.append xs (randomList ())
      | 2 -> List.map (fun x -> x + 100) (randomList ())
      | 3 -> xs
      | _ -> randomList ()
    let a = Set.ofList xs
    let b = Set.ofList ys
    let check (what: string) (s: Set<int>) (expected: list<int>) =
      // the set is a working one: its elements, then one added and one removed
      let ok =
        Set.toList s = expected && Set.toList (Set.remove 7 (Set.add 1000 s)) = List.filter (fun x ->
          x <> 7) (List.append expected [ 1000 ])
      if not ok then
        bad.Value <- bad.Value + 1
        println $"{what}: {Set.toList s}, expected {expected}"
    check "union" (Set.union a b) (sorted (List.append xs ys))
    check "intersect" (Set.intersect a b) (sorted (List.filter (fun x -> List.contains x ys) xs))
    check "difference" (Set.difference a b) (sorted (List.filter (fun x -> not (List.contains x ys)) xs))
  // collect: the lists in order, f called once each, in order
  let calls = ref []
  let parts = List.init 50 (fun i -> List.init (i % 4) (fun j -> i * 10 + j))
  let part (p: list<int>) : list<int> =
    calls.Value <- List.length calls.Value :: calls.Value
    p
  let all = List.collect part parts
  let flat = List.fold (fun (acc: list<int>) (p: list<int>) -> List.append acc p) [] parts
  if all <> flat || List.rev calls.Value <> List.init 50 id || List.concat parts <> flat then
    bad.Value <- bad.Value + 1
    println "collect differs"
  println $"6000 set operations and a collect, {bad.Value} wrong"
