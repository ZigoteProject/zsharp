/// First in, first out.
namespace Collections

/// A queue: `Queue.dequeue` gives the oldest item. A value: `enqueue` and `dequeue` give the
/// changed queue, reusing the old one's cells when nothing else refers to it.
type Queue<'a> =
  { /// The oldest items, oldest first.
    front: list<'a>
    /// The newest items, newest first: reversed into `front` when it runs out.
    back: list<'a>
    /// The number of items.
    size: int }

/// Functions on `Queue`.
module Queue =
  /// An empty queue.
  let empty : Queue<'a> = { front = []; back = []; size = 0 }

  /// The queue with `x` added at the back.
  let enqueue (x: 'a) (q: Queue<'a>) : Queue<'a> =
    { front = q.front; back = x :: q.back; size = q.size + 1 }

  /// The oldest item and the queue without it, or `None` when it's empty.
  let dequeue (q: Queue<'a>) : option<'a * Queue<'a>> =
    match q.front with
    | x :: rest -> Some(x, { front = rest; back = q.back; size = q.size - 1 })
    | [] ->
      match List.rev q.back with
      | x :: rest -> Some(x, { front = rest; back = []; size = q.size - 1 })
      | [] -> None

  /// The oldest item, or `None`.
  let peek (q: Queue<'a>) : option<'a> =
    match q.front with
    | x :: _ -> Some x
    | [] -> List.tryLast q.back

  /// The number of items.
  let count (q: Queue<'a>) = q.size
