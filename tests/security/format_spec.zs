// Format.format with a specifier made at run time (0024) is checked as the compiler checks a
// hole's: a letter the number takes and at most two ASCII digits, so a width or a precision is at
// most 99, which the runtime's buffers hold. The two bytes after the letter were taken as digits
// whatever they were: "Bzz" was a width of 814, which B wrote past a 200-byte buffer on the stack
// and D, X and F copied the stack after it into the string. test.sh runs it on wasm32 too, against
// the same output (rt-embedded.c's 120-byte buffer holds F99 of u64's greatest exactly).
let main () =
  let big: i64 = 9223372036854775807
  let least = -big - i64 1
  let top: u64 = 0xFFFFFFFFFFFFFFFF
  for spec in [ "B99"; "b99"; "D99"; "X99"; "x99"; "F99"; "N99" ] do
    let low = Format.format least spec
    let high = Format.format top spec
    println $"{spec}: {String.length low} {String.length high}"
  let wide = Format.format (u8 5) "B99"
  let grouped = Format.format top "N0"
  println $"{String.sub wide 90 9} {Format.format least "X"} {grouped} {Format.format (i8 -1) "b"}"
  let bad = String.concat [ "B"; "zz" ]
  println "before"
  println (Format.format 42 bad)
  0
