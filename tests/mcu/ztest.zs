// zs test --target <chip> (0009, D11): the tests built into one image and run under QEMU in one
// process, Core's runner printing each; a pending one skipped; a test's own output kept to itself;
// a property runs its cases there too (0010's last step), from Core's PCG, nothing recorded
open Testing

let double (x: int) = x * 2

[<Tests>]
let tests =
  testList "chip" [
    test "doubles" (fun () -> assert (double 21 = 42))
    test "prints" (fun () ->
      println "inside the test"
      assert (double 2 = 4))
    testPropertyWith { runs = 30; seed = Some (u64 1) } "halves" (fun (n: int) -> double n / 2 = n)
    testList "bits" [
      test "pops" (fun () -> assert (Int.popCount (u8 255) = 8))
      ptest "later" (fun () -> assert false)
    ]
  ]
