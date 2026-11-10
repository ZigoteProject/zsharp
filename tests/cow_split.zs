// The other shapes of a mutable passed to a call that reads it elsewhere (tests/cow_args.zs has
// x <- f … x …): let r = f … x … with x reassigned after, which moves x the same way; and an
// argument that writes x, by assignment or in place, which must not move it: the call gets the
// value x held before. A reassignment the move can't mark (past a join point, on some paths
// only) keeps the variable from moving.
let main () =
  // let r = f (read of a) a, then a <- r: a stays unique, so the writes are in place
  let mutable a = Array.create 50 0
  let mark = Runtime.allocations ()
  for i in 0 .. 499 do
    let r = Array.set a (i % 50) (a.[i % 50] + i)
    a <- r
  println $"split: {Array.sum a}, allocations {Runtime.allocations () - mark}"
  // an argument that assigns the mutable: no move, and the call sets the value from before
  let mutable b = [| 1; 2; 3 |]
  b <- Array.set b 0 (if Array.length b > 0 then
    b <- [| 9 |]
    7
  else 0)
  println $"assigned inside: {Array.toList b}"
  let mutable m = HashMap.add 1 "one" HashMap.empty
  m <- HashMap.add 2 (match HashMap.count m with
    | 1 ->
      m <- HashMap.empty
      "two"
    | _ -> "other") m
  println $"map assigned inside: {List.sort (HashMap.toList m)}"
  // an argument that writes the array in place: through a moved reference it would write the
  // same cell the call then updates
  let mutable c = [| 0; 0 |]
  c <- Array.set c 0 (if Array.length c > 0 then
    c.[1] <- 7
    1
  else 0)
  println $"written inside: {Array.toList c}"
  // a read, then a write in place, then the reassignment: the read can't take the array, which
  // the write still needs
  let mutable d = Array.create 4 0
  let n = Array.length d
  d.[0] <- 1
  d <- Array.create n 7
  println $"written before reassigned: {d.[0]} {n}"
  // moved into a call, then a let mutable, then reassigned: the reassignment drops nothing, as
  // with nothing between
  let mutable e = Array.create 4 1
  let len = Array.length e
  let mutable total = 0
  e <- Array.create len 2
  for i in 0 .. len - 1 do
    total <- total + e.[i]
  println $"let mutable between: {total} {len}"
  // moved into a tuple, then a let mutable: the tuple keeps the value the reassignment replaces
  let mutable names = [| "a"; "b" |]
  let saved = (names, 1)
  let mutable count = 0
  names <- [| "c" |]
  count <- count + Array.length names
  println $"tuple: {Array.toList (fst saved)} {snd saved} {Array.toList names} {count}"
  // a call, then a match whose shared arm (a join point) reassigns the mutable and whose other
  // arm doesn't: no move, so the other path still has the array
  let mutable f = Array.create 4 1
  let flen = Array.length f
  let k = Option.defaultValue 0 (String.parseInt "3")
  match String.parseInt "5" with
  | Some 0 | Some 1 -> f <- Array.create (k * 3 + flen / 2 + 1) (k * 7 - flen % 3 + 2)
  | _ -> ()
  println $"join point: {Array.length f} {flen}"
  0
