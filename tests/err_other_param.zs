// A type whose impl of a trait is for another parameter than the one given says so, naming both
// (0037): a list of ints to a function over strings, and a program's own trait's put given a
// number for a box of strings
trait Indexed<'c, 'e> =
  abstract put : 'e -> 'c -> unit

type Box<'t> = { v: 't }

impl Indexed<Box<'t>, 't> =
  let put (x: 't) (b: Box<'t>) = ()

let strings () = Iter.iter (fun (s: string) -> println s) [ 1; 2 ]

let boxed () = Indexed.put 5 { v = "x" }

let main () = 0
