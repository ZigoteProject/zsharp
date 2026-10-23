// DateTime (0024): a moment in UTC as nanoseconds since 1970, printed in ISO 8601
let main () =
  let later: DateTime = { sinceEpoch = 1761120000250000000<ns> }
  let before: DateTime = { sinceEpoch = -1<ns> }
  println $"{DateTime.unixEpoch} {later} {before} {later > before}"
  let now = DateTime.utcNow ()
  println $"{now.sinceEpoch > 1700000000000000000<ns>}"
  0
