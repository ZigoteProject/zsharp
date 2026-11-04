// a failing test on a chip: its panic ends the run after `test path`, which names it, with what
// it printed before
open Testing

[<Tests>]
let tests =
  testList "chip" [
    test "passes" (fun () -> assert (1 + 1 = 2))
    test "fails" (fun () ->
      println "about to fail"
      assert (1 + 1 = 3))
    test "never runs" (fun () -> assert true)
  ]
