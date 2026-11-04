// properties (0010, step 3): a failing case shows its labels; this one is odd
open Testing

let main () =
  Testing.runAll [
    testPropertyWith { seed = Some (u64 9) } "labels on a failure" (fun (n: int) ->
      prop {
        do! Prop.label (if n % 2 = 0 then "even" else "odd")
        return n < 25
      })
  ]
