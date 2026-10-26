// types whose objects can form a reference cycle through a cell (0021): warned at the type that
// closes the cycle, with the path and the other types' fields as notes
type Node = Node of value: int * next: ref<option<Node>> * prev: ref<option<Node>>

type Parent = { kids: ref<list<Child>> }
and Child = { name: string; parent: ref<option<Parent>> }

// a subject and its observers, through a Buffer and a generic record
type Cell<'a> = { item: 'a }
type Subject = { observers: Buffer<Observer> }
and Observer = { subject: Cell<Subject> }

// two ways back and no back-pointer: what [<NoWarn "cycle">] is for
type Expr =
  | Num of int
  | Add of ref<Expr> * ref<Expr>

let main () = 0
