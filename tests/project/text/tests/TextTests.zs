// A test in tests/: it names src/Text.zs as Text, the way the program does, and its helper
// Samples.zs beside it
[<Tests>]
let tests =
  Testing.testList "tests" [
    Testing.test "sees src and its helpers" (fun () ->
      assert (Text.wordCount Samples.twoLines = 3)
      assert (Text.lineCount Samples.twoLines = 2))
  ]
