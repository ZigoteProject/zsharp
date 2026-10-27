// An array too big for the address space: its size in bytes overflows the word, and wrapped it
// was a small object whose length ran past its end (Array.create's fill writing over the heap).
// It panics, as an allocation that fails does (2^61 ints here; on a 32-bit target, 2^29).
let main () =
  let n = Option.defaultValue 536870912 (Int.parse "2305843009213693952")
  println "before"
  let a = Array.create n 7
  println $"{Array.length a}"
  0
