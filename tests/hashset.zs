// HashSet (0024): a set by hashing, a value updated in place when nothing else refers to it
let main () =
  let s = HashSet.ofList [ 3; 1; 4; 1; 5 ]
  println $"{HashSet.count s} {HashSet.contains 4 s} {HashSet.contains 9 s} {List.sort (HashSet.toList (HashSet.remove 1 s))}"
  let a = HashSet.ofList [ "a"; "b"; "c" ]
  let b = HashSet.ofList [ "b"; "c"; "d" ]
  println $"{List.sort (HashSet.toList (HashSet.union a b))} {List.sort (HashSet.toList (HashSet.intersect a b))} {List.sort (HashSet.toList (HashSet.difference a b))}"
  let mutable big = HashSet.empty
  for i in 1 .. 1000 do
    big <- HashSet.add (i % 300) big
  println $"{HashSet.count big} {HashSet.count (HashSet.add 5 big)}"
  0
