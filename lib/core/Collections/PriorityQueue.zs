/// Lowest priority first.
namespace Collections

/// A priority queue: `PriorityQueue.dequeue` gives the item of the lowest priority (`'p` with
/// `Ord`), as .NET's; items of equal priority come in no set order. A leftist heap: `enqueue` and
/// `dequeue` take a logarithmic number of steps, reusing the old queue's cells when nothing else
/// refers to it, and an older queue kept alive (`match dequeue q with Some(x, rest) -> q <- rest`)
/// costs no copy.
type PriorityQueue<'a, 'p> =
  /// no items
  | Empty
  /// a node: the length of its rightmost path, its item and priority, and the two below it, the
  /// left one's rightmost path no shorter; no priority below a node's is lower than its own
  | Node of rank: int * item: 'a * priority: 'p * left: PriorityQueue<'a, 'p> * right: PriorityQueue<'a, 'p> * size: int

/// Functions on `PriorityQueue`.
module PriorityQueue =
  /// An empty priority queue.
  let empty : PriorityQueue<'a, 'p> = Empty

  /// The number of items.
  let count (q: PriorityQueue<'a, 'p>) =
    match q with
    | Empty -> 0
    | Node(_, _, _, _, _, n) -> n

  let private rank (q: PriorityQueue<'a, 'p>) =
    match q with
    | Empty -> 0
    | Node(r, _, _, _, _, _) -> r

  // a node over two heaps, the one with the longer rightmost path on the left
  let private node (x: 'a) (p: 'p) (a: PriorityQueue<'a, 'p>) (b: PriorityQueue<'a, 'p>) : PriorityQueue<'a, 'p> =
    let n = count a + count b + 1
    if rank a >= rank b then Node(rank b + 1, x, p, a, b, n) else Node(rank a + 1, x, p, b, a, n)

  // two heaps as one: down the rightmost paths, the lower priority on top
  let rec private merge (a: PriorityQueue<'a, 'p>) (b: PriorityQueue<'a, 'p>) : PriorityQueue<'a, 'p> =
    match (a, b) with
    | (Empty, _) -> b
    | (_, Empty) -> a
    | (Node(_, x, p, al, ar, _), Node(_, y, q, bl, br, _)) ->
      if p <= q then node x p al (merge ar b) else node y q bl (merge a br)

  /// The queue with `x` added at priority `p`.
  let enqueue (x: 'a) (p: 'p) (q: PriorityQueue<'a, 'p>) : PriorityQueue<'a, 'p> =
    merge (Node(1, x, p, Empty, Empty, 1)) q

  /// The item of the lowest priority, with its priority, and the queue without it; `None` when
  /// it's empty.
  let dequeue (q: PriorityQueue<'a, 'p>) : option<('a * 'p) * PriorityQueue<'a, 'p>> =
    match q with
    | Empty -> None
    | Node(_, x, p, l, r, _) -> Some((x, p), merge l r)

  /// The item of the lowest priority, with its priority, or `None`.
  let peek (q: PriorityQueue<'a, 'p>) : option<'a * 'p> =
    match q with
    | Empty -> None
    | Node(_, x, p, _, _, _) -> Some(x, p)
