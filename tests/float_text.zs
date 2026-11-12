// A float's text is the shortest that reads back as it: the decimals of up to 15 digits the
// runtime writes by hand, at the edges of that path (1e-4, 1e15, -0.0, 16 and 17 digits), and
// each one read back
let show (x: f64) =
  let t = string x
  println $"{t} {String.parseFloat t = Some x}"

let main () =
  let values =
    [ 0.0; -0.0; 1.0; -1.0; 0.5; 0.1; 0.2; 0.1 + 0.2; 0.3; 1.0 / 3.0; 2.5e3; -2.5e-3; 1234.25
      0.0001; 0.00009999; 0.000123456789012345; 0.00012345678901234567; 3e-7; 5e-324
      999999999999999.0; 999999999999999.9; 99999999999999.98; 1e15; 2.5e15; 123456789012345.6
      9007199254740992.0
      9007199254740993.0
      0.99999999999999989
      1e22
      1e23
      1.7976931348623157e308
      100.0; 1e14 + 0.5; 4503599627370496.5; 0.000001; 12345.678901234567 ]
  for x in values do
    show x
    show -x
  0
