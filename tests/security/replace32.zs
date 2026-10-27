// A string longer than a 32-bit word can count panics: String.replace's length (65,536 times
// 65,537 bytes) wrapped to 64 KB, which it then wrote 4 GB into. test.sh builds it for wasm32
// and runs it under node (no .out: on a 64-bit machine it's a 4 GB string).
let main () =
  let s = String.ofBytes (Array.create 65536 (u8 97))
  let w = String.ofBytes (Array.create 65537 (u8 98))
  println "before"
  let r = String.replace s "a" w
  println $"{String.length r}"
  0
