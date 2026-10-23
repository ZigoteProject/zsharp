/// Time: `DateTime`, a moment in UTC, and `Duration`, a length of time in nanoseconds
/// (`i64<ns>`, so that a plain number isn't one). `DateTime.utcNow` reads the clock (Std).
namespace Time

/// Nanoseconds: the unit of a `Duration`.
[<Measure>]
type ns

/// A length of time in nanoseconds: an `i64` on every target, since an `int` of nanoseconds is
/// 2.1 seconds on a microcontroller.
type Duration = i64<ns>

/// A moment: nanoseconds since 1970-01-01T00:00:00Z, in UTC (the years 1678 to 2262). Its
/// equality, ordering and hashing are its number's; `string` prints it in ISO 8601.
type DateTime =
  { /// Nanoseconds since 1970-01-01T00:00:00Z.
    sinceEpoch: Duration }

/// Functions on `DateTime`.
module DateTime =
  /// 1970-01-01T00:00:00Z.
  let unixEpoch : DateTime = { sinceEpoch = 0<ns> }

  // a / b rounded down (toward minus infinity), for moments before the epoch
  let private floorDiv (a: i64) (b: i64) = if a >= i64 0 then a / b else (a - b + i64 1) / b

  let private twoDigits (n: i64) = if n < i64 10 then "0" + string n else string n

  /// The moment in ISO 8601: `2026-10-22T08:00:00Z`, with a fraction of a second only when it
  /// has one (`08:00:00.25Z`).
  let toIso (t: DateTime) =
    let total = t.sinceEpoch / 1<ns>
    let perDay: i64 = 86400000000000 // typed, so the literal is 64 bits on every target
    let days = floorDiv total perDay
    let inDay = total - days * perDay
    // the civil date of a day number (Howard Hinnant's days_from_civil, inverted)
    let z = days + i64 719468
    let era = floorDiv z (i64 146097)
    let doe = z - era * i64 146097
    let yoe = (doe - doe / i64 1460 + doe / i64 36524 - doe / i64 146096) / i64 365
    let doy = doe - (i64 365 * yoe + yoe / i64 4 - yoe / i64 100)
    let mp = (i64 5 * doy + i64 2) / i64 153
    let day = doy - (i64 153 * mp + i64 2) / i64 5 + i64 1
    let month = if mp < i64 10 then mp + i64 3 else mp - i64 9
    let year = yoe + era * i64 400 + (if month <= i64 2 then i64 1 else i64 0)
    let secs = inDay / i64 1000000000
    let nanos = inDay % i64 1000000000
    // the fraction without its trailing zeros
    let fraction =
      if nanos = i64 0 then
        ""
      else
        let mutable digits = string (nanos + i64 1000000000)
        digits <- String.sub digits 1 9
        while String.endsWith "0" digits do
          digits <- String.sub digits 0 (String.length digits - 1)
        "." + digits

    let yearText =
      if year >= i64 0 && year < i64 1000 then
        String.padLeftWith 4 '0' (string year)
      else
        string year
    $"{yearText}-{twoDigits month}-{twoDigits day}T{twoDigits (secs / i64 3600)}:{twoDigits (secs / i64 60 % i64 60)}:{twoDigits (secs % i64 60)}{fraction}Z"

/// A moment prints in ISO 8601 (`DateTime.toIso`).
impl Show<DateTime> =
  let show (t: DateTime) = DateTime.toIso t
