// A trait method only its result gives the type of builds where something gives it: a generic
// function's caller, or the default, int, whose impl may come after the use, as long as nothing
// settles the type there (0037's check runs once the module is checked)
trait Make<'a> =
  abstract make : unit -> 'a

type Name = { text: string }

impl Make<Name> =
  let make () = { text = "named" }

// its type is its caller's
let pair () : 'a * 'a = (Make.make (), Make.make ())

let main () =
  let m = Make.make ()
  let (a, b) : Name * Name = pair ()
  println $"{m} {a.text} {b.text}"

impl Make<int> =
  let make () = 41
