// used by session.sh: the test tool
open Testing

[<Tests>]
let tests =
  testList "mcp" [
    test "adds" (fun () -> assert (1 + 1 = 2))
    test "fails" (fun () -> assert (1 + 1 = 3))
  ]
