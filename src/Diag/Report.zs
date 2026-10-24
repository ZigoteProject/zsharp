/// Reporting diagnostics (decision 74): a pass performs `Report.diagnostic` and goes on, and the
/// boundary of a job or a task collects what it reported.
open Diagnostic

/// A diagnostic reported where it was found.
effect Report =
  /// Reports it; the work goes on.
  abstract diagnostic : Diagnostic -> unit

/// Runs `f`, keeping what it reports: its result and the diagnostics in order.
let collect (f: unit -> 'a / Report) : 'a * array<Diagnostic> =
  let found = Buffer.empty
  let result =
    handle f () with
    | Report.diagnostic d, k ->
      Buffer.push d found
      k ()
  (result, Buffer.toArray found)
