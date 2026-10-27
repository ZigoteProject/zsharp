// Numbers are written and read with a '.' whatever locale a C library sets: printf and strtod
// read LC_NUMERIC's decimal point, so after a setlocale (GTK's, an ncurses program's) $"{1.5}"
// was "1,5" (invalid JSON, two CSV fields) and Float.parse "1.5" failed. test.sh runs it with
// LOCPATH holding comma, a locale whose decimal point is ','.
extern setlocale : i32 -> cstr -> cptr
extern strtod : cstr -> cptr -> f64

let main () =
  // LC_NUMERIC is 1 on Linux; C's own strtod then reads a comma
  setlocale 1 "comma" |> ignore
  println $"C reads 1,5 as {strtod "1,5" (Ptr.toCPtr (Ptr.null () : ptr<u8>))}"
  println $"{1.5} {f32 2.25} {1.0e-7} {[ 0.5; 1.25 ]}"
  println $"{Float.parse "1.5"} {Float.parse "1,5"} {String.isFloat "1.5"} {String.toFloat "2.5"}"
  println $"{1.5:F2} {0.000125:E2} {2.5:G}"
  match Json.parse "{\"x\": 1.5, \"y\": [2.25]}" with
  | Ok j -> println $"{Json.print j}"
  | Error e -> println e
  0
