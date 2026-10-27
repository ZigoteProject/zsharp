// A for loop's bounds are evaluated once, before it runs. Loop versioning tests the accesses'
// ranges against them, and evaluated them again for the loop it chose: a bound with an effect
// ran twice, and the copy without bounds checks ran over the second values, past the range the
// test proved (here 2 for the test and 100000 for the loop, over an array of 3).
let main () =
  let calls = ref 0
  let upper () =
    calls.Value <- calls.Value + 1
    if calls.Value = 1 then 2 else 100000
  let a = [| 1; 2; 3 |]
  let mutable s = 0
  for i in 0 .. upper () do
    s <- s + a.[i]
  println $"{s} {calls.Value}"
  let starts = ref 0
  let lower () =
    starts.Value <- starts.Value + 1
    if starts.Value = 1 then 0 else -100000
  let mutable b = Array.create 3 0
  for i in lower () .. 2 do
    b.[i] <- i + 1
  println $"{Array.toList b} {starts.Value}"
  0
