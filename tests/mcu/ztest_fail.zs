// a failing test on a chip: its panic ends the run after `test path`, which names it, with what
// it printed before and every line of the panic's message (a falsified property's spans three;
// a blank one among them doesn't end it)
open Testing

[<Tests>]
let tests =
  testList "chip" [
    test "passes" (fun () -> assert (1 + 1 = 2))
    test "fails" (fun () ->
      println "about to fail"
      (panic "falsified after 4 cases (2 shrinks): 3\n\n  false\n  replay: testPropertyWith { seed = Some (u64 5) }" : unit))
    test "never runs" (fun () -> assert true)
  ]
