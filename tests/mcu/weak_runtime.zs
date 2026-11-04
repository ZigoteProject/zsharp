// weak references to objects the runtime frees itself (a weak cell, an Spsc): they see them die,
// and a later object at the same address isn't mistaken for them
let main () =
  let outer = Weak.create (Weak.create (ref 5))
  let keep = ref 9
  let other = Weak.create keep
  match Weak.get outer with
  | Some _ -> println "a weak cell nothing holds is alive"
  | None -> println "a weak cell nothing holds is gone"
  println $"{(Weak.get other).IsSome} {keep.Value}"
  let w = Weak.create (Spsc.create 4 : Spsc<int>)
  let q : Spsc<int> = Spsc.create 4
  Spsc.push q 7 |> ignore
  match Weak.get w with
  | Some _ -> println "a dropped Spsc is alive"
  | None -> println "a dropped Spsc is gone"
  println $"the other queue keeps its value: {(Spsc.pop q).IsSome}"
  0
