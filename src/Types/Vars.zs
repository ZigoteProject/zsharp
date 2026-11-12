/// The checker's type variables (decision 73): each one, by its number, bound to a type or free
/// with its kind. While a trial is open (an impl tried, an overload), each change is trailed, so a
/// trial that misses undoes what it bound.
open Ty

/// The variables: one heap cell, read field by field, so passing them on is one count, not one
/// for each buffer (they're passed to nearly every function on types).
type Vars =
  | Vars of VarsData

and VarsData =
  { /// each variable's binding (None: free)
    links: Buffer<option<Ty>>
    kinds: Buffer<Kind>
    /// the changes made while a trial is open: the variable, and its binding and kind before
    trailVar: Buffer<int>
    trailLink: Buffer<option<Ty>>
    trailKind: Buffer<Kind>
    /// how many trials are open
    trials: ref<int> }

type Vars with
  member v.links =
    match v with
    | Vars { links = x } -> x
  member v.kinds =
    match v with
    | Vars { kinds = x } -> x
  member v.trailVar =
    match v with
    | Vars { trailVar = x } -> x
  member v.trailLink =
    match v with
    | Vars { trailLink = x } -> x
  member v.trailKind =
    match v with
    | Vars { trailKind = x } -> x
  member v.trials =
    match v with
    | Vars { trials = x } -> x

/// No variables yet.
let make () : Vars =
  let none : VarsData =
    { links = Buffer.empty
      kinds = Buffer.empty
      trailVar = Buffer.empty
      trailLink = Buffer.empty
      trailKind = Buffer.empty
      trials = ref 0 }
  Vars none

/// A new free variable of a kind.
let fresh (v: Vars) (k: Kind) : Ty =
  let n = Buffer.length v.links
  Buffer.push None v.links
  Buffer.push k v.kinds
  TVar n

/// How many variables there are (the next one's number).
let count (v: Vars) : int = Buffer.length v.links

/// A free variable's kind (a bound one's is kAny).
let kindOf (v: Vars) (i: int) : Kind =
  match v.links.[i] with
  | None -> v.kinds.[i]
  | Some _ -> kAny

/// Whether a variable is free.
let isFree (v: Vars) (i: int) : bool = Option.isNone v.links.[i]

// a change, trailed when a trial is open
let private trail (v: Vars) (i: int) =
  if v.trials.Value > 0 then
    Buffer.push i v.trailVar
    Buffer.push v.links.[i] v.trailLink
    Buffer.push v.kinds.[i] v.trailKind

// what a variable is bound to (None: free, or not a variable)
let private next (v: Vars) (t: Ty) : option<Ty> =
  match t with
  | TVar i -> v.links.[i]
  | _ -> None

/// A type with its outermost bound variables followed to what they're bound to. A chain of
/// variables bound to variables (an array literal's elements, each unified with the one before)
/// is walked once: each one on it is then bound straight to the end (trailed, so a trial that
/// misses undoes that too), as a union-find's path compression does, and in a loop, as a chain
/// can be as long as the program.
let prune (v: Vars) (t: Ty) : Ty =
  match next v t with
  | None -> t
  | Some b0 ->
    match next v b0 with
    | None -> b0
    | Some _ ->
      let mutable last = b0
      while true do
        match next v last with
        | Some b -> last <- b
        | None -> break
      let mutable c = t
      while true do
        match c with
        | TVar i ->
          match v.links.[i] with
          | Some b when Option.isSome (next v b) ->
            trail v i
            v.links.[i] <- Some last
            c <- b
          | _ -> break
        | _ -> break
      last

/// Binds a free variable to a type.
let bind (v: Vars) (i: int) (t: Ty) =
  trail v i
  v.links.[i] <- Some t

/// Gives a free variable another kind.
let setKind (v: Vars) (i: int) (k: Kind) =
  trail v i
  v.kinds.[i] <- k

/// Opens a trial: where its changes start.
let mark (v: Vars) : int =
  v.trials.Value <- v.trials.Value + 1
  Buffer.length v.trailVar

/// Ends a trial that missed: its changes undone, the last first.
let undo (v: Vars) (at: int) =
  while Buffer.length v.trailVar > at do
    let i = Buffer.removeLast v.trailVar
    v.links.[i] <- Buffer.removeLast v.trailLink
    v.kinds.[i] <- Buffer.removeLast v.trailKind
  v.trials.Value <- v.trials.Value - 1

/// Ends a trial that held: its changes kept (and trailed still, for a trial around it).
let commit (v: Vars) (at: int) =
  v.trials.Value <- v.trials.Value - 1
  if v.trials.Value = 0 then
    Buffer.truncate at v.trailVar
    Buffer.truncate at v.trailLink
    Buffer.truncate at v.trailKind
