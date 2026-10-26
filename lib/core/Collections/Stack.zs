/// Last in, first out.
namespace Collections

/// A stack: `Stack.pop` gives the newest item. A value, as a list is.
type Stack<'a> =
  { /// The items, newest first.
    items: list<'a>
    /// The number of items.
    size: int }

/// Functions on `Stack`.
module Stack =
  /// An empty stack.
  let empty : Stack<'a> = { items = []; size = 0 }

  /// The stack with `x` on top.
  let push (x: 'a) (s: Stack<'a>) : Stack<'a> = { items = x :: s.items; size = s.size + 1 }

  /// The top item and the stack without it, or `None` when it's empty.
  let pop (s: Stack<'a>) : option<'a * Stack<'a>> =
    match s.items with
    | x :: rest -> Some(x, { items = rest; size = s.size - 1 })
    | [] -> None

  /// The top item, or `None`.
  let peek (s: Stack<'a>) : option<'a> = List.tryHead s.items

  /// The number of items.
  let count (s: Stack<'a>) = s.size
