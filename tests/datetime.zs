// DateTime (0024): a moment in UTC as nanoseconds since 1970, printed in ISO 8601
let main () =
  let later: DateTime = { sinceEpoch = 1761120000250000000<ns> }
  let before: DateTime = { sinceEpoch = -1<ns> }
  println $"{DateTime.unixEpoch} {later} {before} {later > before}"
  let now = DateTime.utcNow ()
  println $"{now.sinceEpoch > 1700000000000000000<ns>}"
  // ISO 8601 parsed (S6): the forms, the offset taken off, the fraction to nanoseconds; and what
  // isn't a moment, a day its month hasn't included
  for s in [ "2026-11-04T08:30:00Z"
    "2026-11-04T08:30:00.25Z"
    "2026-11-04T08:30:00+02:00"
    "2026-11-04T08:30:00-05:30"
    "2026-11-04T08:30Z"
    "2026-11-04"
    "2026-11-04 08:30:00"
    "1969-12-31T23:59:59.5Z"
    "2000-02-29T12:00:00.1234567891Z" ] do
    println $"{s} -> {DateTime.parseIso s}"
  println $"{List.map DateTime.parseIso [ "2026-11-4"; "2026-13-01"; "2026-02-29"; "2026-11-04T24:00:00Z"; "2026-11-04T08:30:00.Z"; "2026-11-04T08:30:00+2:00"; "1677-12-31" ]}"
  println $"{DateTime.ofParts 2262 4 11 23 47 16 0} {DateTime.ofParts 1678 1 1 0 0 0 0} {DateTime.ofParts 2026 4 31 0 0 0 0} {Option.map DateTime.toIso (DateTime.ofParts 2026 11 4 8 30 0 250000000)}"
  // the range's end, inside 2262: past it None (i64 nanoseconds overflowed), a moment that fits
  // in UTC though not as written included; and the first and last moments printed
  println $"{DateTime.ofParts 2262 4 11 23 47 16 854775807} {DateTime.ofParts 2262 4 11 23 47 16 854775808} {DateTime.ofParts 2262 12 31 0 0 0 0}"
  println $"{List.map DateTime.parseIso [ "2262-04-11T23:47:17Z"; "2262-12-31"; "2262-04-11T23:47:16-01:00"; "2262-04-12T00:30:00+01:00" ]}"
  let first: DateTime = { sinceEpoch = (i64 -9223372036854775807 - i64 1) * 1<ns> }
  let last: DateTime = { sinceEpoch = 9223372036854775807<ns> }
  println $"{first} {last}"
  0
