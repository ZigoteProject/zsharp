/// The checker's type variables (decision 73): each one, by its number, bound to a type or free
/// with its kind. While a trial is open (an impl tried, an overload), each change is trailed, so a
/// trial that misses undoes what it bound.
open Ty

type Vars =
  { /// each variable's binding (None: free)
    links: Buffer<option<Ty>>
    kinds: Buffer<Kind>
    /// the changes made while a trial is open: the variable, and its binding and kind before
    trailVar: Buffer<int>
    trailLink: Buffer<option<Ty>>
    trailKind: Buffer<Kind>
    /// how many trials are open
    trials: ref<int> }

/// No variables yet.
let make () : Vars =
  { links = Buffer.empty
    kinds = Buffer.empty
    trailVar = Buffer.empty
    trailLink = Buffer.empty
    trailKind = Buffer.empty
    trials = ref 0 }

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

/// A type with its outermost bound variables followed to what they're bound to.
let rec prune (v: Vars) (t: Ty) : Ty =
  match t with
  | TVar i ->
    match v.links.[i] with
    | Some b -> prune v b
    | None -> t
  | _ -> t

// a change, trailed when a trial is open
let private trail (v: Vars) (i: int) =
  if v.trials.Value > 0 then
    Buffer.push i v.trailVar
    Buffer.push v.links.[i] v.trailLink
    Buffer.push v.kinds.[i] v.trailKind

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
