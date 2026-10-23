/// Lazy sequences: generators. A `seq { }`'s body runs when the sequence is consumed, and each
/// `yield` gives the consumer one element (the `Yield` effect, handled by the consumer), so
/// nothing is built in between: `Seq.map`, `filter` and `take` over a generator, consumed by
/// `Seq.iter` or `for`, run inside the generator's loop, each stage handling an element where
/// it's yielded, with nothing allocated per element. A sequence is computed again each time it's
/// consumed.
namespace Collections

/// A lazy sequence of `'a`: what `seq { }` makes. Its function yields the elements.
type Seq<'a> = Seq of (unit -> unit / Yield<'a>)

/// Functions on `Seq`.
module Seq =
  /// Yields the sequence's elements to the consumer of the sequence the caller is in:
  /// `yield! s` in a `seq { }`.
  let yieldAll s =
    match s with
    | Seq gen -> gen ()

  /// The sequence of no elements.
  let empty () = Seq(fun () -> ())

  /// The sequence of the one element `x`.
  let singleton x = Seq(fun () -> Yield.yield x)

  /// The elements of a list, in order.
  let ofList xs = Seq(fun () -> List.iter Yield.yield xs)

  /// The elements of an array, in order.
  let ofArray (a: array<'a>) =
    Seq(fun () ->
      for i in 0 .. Array.length a - 1 do
        Yield.yield a.[i])

  /// `n` elements, `f 0` to `f (n - 1)`, each computed as it's consumed.
  let init n (f: int -> 'a / <>) =
    Seq(fun () ->
      for i in 0 .. n - 1 do
        Yield.yield (f i))

  /// The elements of `state` unfolded: `f s` gives `Some (x, next)` for the element `x` and the
  /// next state, or `None` at the end. Infinite while `f` never gives `None`.
  let unfold (f: 's -> option<'a * 's> / <>) state =
    Seq(fun () ->
      let mutable s = Some state
      while Option.isSome s do
        match s with
        | Some st ->
          match f st with
          | Some(x, next) ->
            Yield.yield x
            s <- Some next
          | None -> s <- None
        | None -> ())

  /// Calls `f` on each element, in order.
  let iter f s =
    handle yieldAll s with
    | Yield.yield x, k ->
      f x
      k ()

  /// Like `Seq.iter`, with each element's index: `f i x`.
  let iteri f s =
    let mutable i = 0
    handle yieldAll s with
    | Yield.yield x, k ->
      f i x
      i <- i + 1
      k ()

  /// Combines the elements from the left: `Seq.fold f s [a; b] = f (f s a) b`.
  let fold f state s =
    let mutable acc = state
    handle yieldAll s with
    | Yield.yield x, k ->
      acc <- f acc x
      k ()
    acc

  /// The elements as a list, in order.
  let toList s =
    let mutable acc = []
    handle yieldAll s with
    | Yield.yield x, k ->
      acc <- x :: acc
      k ()
    List.rev acc

  /// The elements as an array, in order.
  let toArray s = Array.ofList (toList s)

  /// The number of elements. Consumes the whole sequence.
  let length s = fold (fun n _ -> n + 1) 0 s

  /// The sum of the elements (`0` for none), with `+` and `Add.zero`.
  let sum s = fold (fun acc x -> acc + x) Add.zero s

  /// The sum of `f x` over the elements.
  let sumBy f s = fold (fun acc x -> acc + f x) Add.zero s

  /// Whether `f` holds for some element. Stops at the first.
  let exists f s =
    handle yieldAll s with
    | Yield.yield x, k -> if f x then true else k ()
    | return () -> false

  /// Whether `f` holds for every element. Stops at the first for which it doesn't.
  let forall f s =
    handle yieldAll s with
    | Yield.yield x, k -> if f x then k () else false
    | return () -> true

  /// The first element for which `f` holds, if any. Stops there.
  let tryFind f s =
    handle yieldAll s with
    | Yield.yield x, k -> if f x then Some x else k ()
    | return () -> None

  /// The first element, if any; the rest isn't computed.
  let tryHead s =
    handle yieldAll s with
    | Yield.yield x, _ -> Some x
    | return () -> None

  /// Whether the sequence has no elements. Computes at most the first.
  let isEmpty s = Option.isNone (tryHead s)

  /// The sequence of `f x` for each element `x`, computed as it's consumed.
  let map (f: 'a -> 'b / <>) s =
    Seq(fun () ->
      handle yieldAll s with
      | Yield.yield x, k ->
        Yield.yield (f x)
        k ())

  /// Like `Seq.map`, with each element's index: `f i x`.
  let mapi (f: int -> 'a -> 'b / <>) s =
    Seq(fun () ->
      let mutable i = 0
      handle yieldAll s with
      | Yield.yield x, k ->
        Yield.yield (f i x)
        i <- i + 1
        k ())

  /// The elements for which `f` holds, in order.
  let filter (f: 'a -> bool / <>) s =
    Seq(fun () ->
      handle yieldAll s with
      | Yield.yield x, k ->
        if f x then Yield.yield x
        k ())

  /// The values of `f x` that are `Some`, in order.
  let choose (f: 'a -> option<'b> / <>) s =
    Seq(fun () ->
      handle yieldAll s with
      | Yield.yield x, k ->
        match f x with
        | Some y -> Yield.yield y
        | None -> ()
        k ())

  /// The elements of `f x` for each element `x`, one sequence after another.
  let collect (f: 'a -> Seq<'b> / <>) s =
    Seq(fun () ->
      handle yieldAll s with
      | Yield.yield x, k ->
        yieldAll (f x)
        k ())

  /// The elements of `a`, then those of `b`.
  let append a b =
    Seq(fun () ->
      yieldAll a
      yieldAll b)

  /// The first `n` elements (all of them when there are fewer); the rest aren't computed.
  let take n s =
    Seq(fun () ->
      let mutable left = n
      if left > 0 then
        handle yieldAll s with
        | Yield.yield x, k ->
          Yield.yield x
          left <- left - 1
          if left > 0 then k ())

  /// The elements while `f` holds; the rest aren't computed.
  let takeWhile (f: 'a -> bool / <>) s =
    Seq(fun () ->
      handle yieldAll s with
      | Yield.yield x, k ->
        if f x then
          Yield.yield x
          k ())

  /// The elements after the first `n`.
  let skip n s =
    Seq(fun () ->
      let mutable left = n
      handle yieldAll s with
      | Yield.yield x, k ->
        if left > 0 then left <- left - 1 else Yield.yield x
        k ())

  /// Pairs of each element with its index, from 0.
  let indexed s = mapi (fun i x -> (i, x)) s

/// A sequence's elements, as it yields them; the generator stops when `f` does.
impl Iter<Seq<'a>, 'a> =
  let forEach s f =
    handle Seq.yieldAll s with
    | Yield.yield x, k -> if f x then k () else false
    | return () -> true
