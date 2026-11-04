// -1 * i64's least isn't folded (the folder used to overflow on it): it overflows at run time
let main () =
  println $"{i64 -1 * (i64 -9223372036854775807 - i64 1)}"
  0
