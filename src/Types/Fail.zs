/// The checker's failures: what it can't go on from in a declaration (the F# compiler's
/// CompileError), thrown to the nearest place that knows where it is, and reported at the
/// declaration's boundary; and unification's (Mismatched), caught by the expression under check.
open Ty

/// A failure: its message, and where it is when known: a token's index in the file's tree (-1:
/// not yet known), and whether only the token's line is meant (the error is shown with no column).
type Failure = { message: string; token: int; lineOnly: bool }

/// The checker stopping at what it can't go on from.
effect Fails =
  /// Fails with a failure.
  abstract fail : Failure -> 'a

/// Fails with a message whose place the nearest node with one gives.
let fail (message: string) : 'a / Fails = Fails.fail { message = message; token = -1; lineOnly = false }

/// Fails on the line of a token, with no column.
let failLine (token: int) (message: string) : 'a / Fails = Fails.fail { message = message; token = token; lineOnly = true }

/// Why two types don't unify: they differ, or one lacks a trait's impl (the trait, the type).
type Mismatch =
  | Differ
  | NoImpl of string * Ty

/// Unification's one way out.
effect Mismatched =
  /// Gives up: the types don't unify.
  abstract throw : Mismatch -> 'a
