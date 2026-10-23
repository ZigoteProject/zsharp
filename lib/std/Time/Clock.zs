/// Reading the system's clock, which needs an operating system.
namespace Time

type DateTime with
  /// The current moment, from the system's real-time clock: `DateTime.utcNow ()`.
  static member utcNow () : DateTime = { sinceEpoch = Native.clockRealtime () * 1<ns> }
