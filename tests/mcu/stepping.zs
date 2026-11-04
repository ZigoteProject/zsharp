// -g alone on a chip is a build for stepping (test.sh checks the IR): -O0 with the code as
// written, so the call to sq stays a call
let sq (x: int) = x * x

let main () =
  let a = sq 3
  println $"{a}"
  0
