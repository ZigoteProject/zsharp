// A main file's own names come before an opened module's (spec 2.4): a union's cases, a type
// and a function named as the opened module's are, used bare, are the file's own; the module's
// are still there by its name.
open Testing

type Verdict =
  | Passed
  | Failed of int
  | Pending

type Model = { count: int }

let test (m: Model) : Verdict =
  if m.count = 0 then Pending else if m.count > 0 then Passed else Failed m.count

let say (v: Verdict) : string =
  match v with
  | Passed -> "passed"
  | Failed n -> $"failed by {n}"
  | Pending -> "pending"

let main () =
  println (say (test { count = 1 }))
  println (say (test { count = -2 }))
  println (say (test { count = 0 }))
  // the opened module's own, by its name
  let theirs = Testing.test "a test" (fun () -> ())
  match theirs with
  | Testing.Case (name, _, Testing.Normal, _) -> println $"Testing's case: {name}"
  | _ -> println "another kind of test"
  0
