// zs test: tests are values (0009), each run in its own process; a failed comparison shows both
// sides and where they differ, and an expect test compares a value's text with its literal.
open Testing

type Point = { x: int; y: int }

let double x = x * 2

[<Tests>]
let tests =
  testList "sample" [
    test "doubles numbers" (fun () -> assert (double 21 = 42))
    test "fails an assert" (fun () -> assert (double 2 = 5))
    test "points differ" (fun () -> assert ({ x = 1; y = double 2 } = { x = 1; y = 5 }))
    test "panics with a message" (fun () ->
      let xs: list<int> = []
      println "some output first"
      ignore (List.head xs))
    test "an Error fails" (fun () -> if double 1 = 2 then Error "two" else Ok ())
    testList "strings" [
      test "concatenate" (fun () -> assert ("a" + "b" = "ab"))
      test "expected text" (fun () -> expect [ 1; 2 ] "[1; 2]")
    ]
    ptest "not yet" (fun () -> assert false)
    testWithTimeout 200 "hangs" (fun () ->
      while true do
        ())
  ]
