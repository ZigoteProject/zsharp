// fixed's length is a positive number up to 2147483647, so no size made of it overflows: one
// nested past any memory has a size that stops there, not the checker's overflow (a case each,
// as a declaration's check stops at its first failed statement)
let main () =
  let f: fixed<int, 0> = Fixed.create 1
  0

let tooLong () =
  let g: fixed<u64, 2305843009213693952> = Fixed.create 1
  0

let nested () = sizeof<fixed<fixed<fixed<u64, 2147483647>, 2147483647>, 2147483647>>
