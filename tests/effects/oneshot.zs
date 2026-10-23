// A resumption runs once: resuming again panics
effect Gen<'a> =
  abstract gen : 'a -> unit

let main () =
  handle Gen.gen 1 with
  | Gen.gen x, k ->
    k ()
    k ()
  0
