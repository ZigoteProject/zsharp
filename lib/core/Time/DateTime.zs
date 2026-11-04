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

  /// The moment of a civil date and time in UTC: `DateTime.ofParts 2026 11 4 8 30 0 0` (year,
  /// month, day, hour, minute, second, nanoseconds), or `None` when a part is out of its range
  /// (the day's, for its month and year; the year's, 1678 to 2262).
  let ofParts (year: int) (month: int) (day: int) (hour: int) (minute: int) (second: int) (nanos: int) : option<DateTime> =
    let leap = year % 4 = 0 && (year % 100 <> 0 || year % 400 = 0)
    let daysIn =
      match month with
      | 2 -> if leap then 29 else 28
      | 4
      | 6
      | 9
      | 11 -> 30
      | _ -> 31
    if year < 1678 || year > 2262 || month < 1 || month > 12 || day < 1 || day > daysIn || hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59 || nanos < 0 || nanos > 999999999 then
      None
    else
      // the day number of a civil date (Howard Hinnant's days_from_civil)
      let y = i64 (if month <= 2 then year - 1 else year)
      let m = i64 month
      let era = floorDiv y (i64 400)
      let yoe = y - era * i64 400
      let doy =
        (i64 153 * (if m > i64 2 then m - i64 3 else m + i64 9) + i64 2) / i64 5 + i64 day - i64 1
      let doe = yoe * i64 365 + yoe / i64 4 - yoe / i64 100 + doy
      let days = era * i64 146097 + doe - i64 719468
      let secs = days * i64 86400 + i64 hour * i64 3600 + i64 minute * i64 60 + i64 second
      Some { sinceEpoch = (secs * i64 1000000000 + i64 nanos) * 1<ns> }

  /// The moment ISO 8601 writes: `2026-11-04T08:30:00Z`, `2026-11-04T08:30:00.25Z`, with
  /// `+02:00` or `-05:30` instead of `Z` (the offset taken off, the moment in UTC) or no zone at
  /// all (taken as UTC), without the seconds (`2026-11-04T08:30Z`), or a date alone
  /// (`2026-11-04`, midnight UTC); a space may stand for the `T`. `None` for anything else, a
  /// part out of its range included.
  let parseIso (s: string) : option<DateTime> =
    let n = String.length s
    let at (i: int) = if i < n then int (String.byte s i) else -1
    let digit (i: int) = at i >= 48 && at i <= 57
    // the number of the digits from i for len: -1 when one isn't a digit
    let number (i: int) (len: int) =
      let mutable v = 0
      for k in i .. i + len - 1 do
        v <- if v < 0 || not (digit k) then -1 else v * 10 + at k - 48
      v
    let year = number 0 4
    let month = number 5 2
    let day = number 8 2
    if year < 0 || at 4 <> 45 || month < 0 || at 7 <> 45 || day < 0 then
      None
    else if n = 10 then
      ofParts year month day 0 0 0 0
    else if at 10 <> 84 && at 10 <> 32 then
      None
    else
      let hour = number 11 2
      let minute = number 14 2
      if hour < 0 || at 13 <> 58 || minute < 0 then
        None
      else
        let mutable i = 16
        let mutable second = 0
        let mutable nanos = 0
        let mutable ok = true
        if at i = 58 then
          second <- number (i + 1) 2
          ok <- second >= 0
          i <- i + 3
          if ok && at i = 46 then
            // a fraction of any length, the first nine digits nanoseconds
            i <- i + 1
            let mutable scale = 100000000
            if not (digit i) then
              ok <- false
            while digit i do
              nanos <- nanos + (at i - 48) * scale
              scale <- scale / 10
              i <- i + 1
        // the zone: Z, or an offset, taken off
        let mutable offset = 0
        if ok then
          if at i = 90 then
            i <- i + 1
          else if at i = 43 || at i = 45 then
            let sign = if at i = 43 then 1 else -1
            let oh = number (i + 1) 2
            let om = number (i + 4) 2
            if oh < 0 || at (i + 3) <> 58 || om < 0 || oh > 23 || om > 59 then
              ok <- false
            else
              offset <- sign * (oh * 3600 + om * 60)
              i <- i + 6
        if not ok || i <> n then
          None
        else
          match ofParts year month day hour minute second nanos with
          | Some t -> Some { sinceEpoch = t.sinceEpoch - i64 offset * 1000000000<ns> }
          | None -> None

/// A moment prints in ISO 8601 (`DateTime.toIso`).
impl Show<DateTime> =
  let show (t: DateTime) = DateTime.toIso t
