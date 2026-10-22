// C: braces, semicolons and return; Z# uses indentation, and the last expression is the result
let sign (x: int) = {
  if (x < 0) { return -1; }
  return 1;
}

let main () = sign 3
