// zs test: [<Test>] functions, each run in its own process
let double x = x * 2

[<Test>]
let doublesNumbers () =
  assert (double 21 = 42)

[<Test>]
let failsAnAssert () =
  assert (double 2 = 5)

[<Test>]
let panicsWithAMessage () =
  let xs: list<int> = []
  println "some output first"
  ignore (List.head xs)

[<Test>]
let stringsWork () =
  assert ("a" + "b" = "ab")
