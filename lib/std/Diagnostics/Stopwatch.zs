/// Measuring elapsed time.
namespace Diagnostics

/// A started stopwatch: `let sw = Stopwatch.startNew ()`, then `sw.ElapsedMilliseconds`.
type Stopwatch =
  { /// When it started: `Runtime.ticks ()`, in nanoseconds.
    startTicks: u64 }
  /// The time since it started, in nanoseconds.
  member sw.ElapsedNanoseconds = Runtime.ticks () - sw.startTicks
  /// The time since it started, in whole milliseconds.
  member sw.ElapsedMilliseconds = int ((Runtime.ticks () - sw.startTicks) / u64 1000000)

/// Functions on `Stopwatch`.
module Stopwatch =
  /// A stopwatch started now.
  let startNew () : Stopwatch = { startTicks = Runtime.ticks () }
