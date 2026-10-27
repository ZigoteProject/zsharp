// Loop versioning proves an index in bounds from the loop's variable and the variables bound
// outside the loop: a name bound inside it that shadows one outside is another variable, so the
// access stays checked (n is 0 outside, 100000 at the second step)
let main () =
  let a = [| 10; 20; 30 |]
  let n = 0
  let mutable s = n
  for i in 0 .. 2 do
    let n = i * 100000
    s <- s + a.[n]
  println $"{s}"
  0
