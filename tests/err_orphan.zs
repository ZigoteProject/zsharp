// The orphan rule (K9): an impl written lives with its trait or its type, so two packages can't
// both write one that a program using both would have twice. The program's trait for a library
// type, and a library trait for the program's type, are the program's to write; a library
// trait for a library type isn't.
type Point = { x: int; y: int }

trait Describe<'a> =
  abstract describe : 'a -> string

impl Describe<Point> =
  let describe p = $"({p.x}, {p.y})"

impl Describe<int> =
  let describe n = $"#{n}"

impl Ord<Point> =
  let compare a b = Ord.compare a.x b.x

impl Hash<Queue<'a>> =
  let hash q = Queue.length q

let main () = 0
