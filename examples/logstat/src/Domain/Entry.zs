// One parsed log line: `2025-12-09T10:00:01Z INFO GET /api/users 200 123ms`.
// Parsing throws (Throw<string>): a bad field stops the line at once, with no result threading.

type Level =
  | Debug
  | Info
  | Warn
  | Err

type Entry = { time: string; level: Level; meth: string; path: string; status: int; ms: int }

let private level (s: string) =
  match s with
  | "DEBUG" -> Debug
  | "INFO" -> Info
  | "WARN" -> Warn
  | "ERROR" -> Err
  | _ -> Throw.throw $"unknown level '{s}'"

let private number (what: string) (s: string) =
  Throw.ofOption $"bad {what} '{s}'" (String.parseInt s)

let private millis (s: string) =
  if String.endsWith "ms" s then number "duration" (String.sub s 0 (String.length s - 2))
  else Throw.throw $"bad duration '{s}'"

// the words, runs of spaces counting as one (filtered only when there are any: most lines)
let private words (line: string) =
  let ws = String.split " " line
  if List.contains "" ws then List.filter (fun w -> w <> "") ws else ws

let parse (line: string) =
  match words line with
  | [ time; lv; meth; path; status; ms ] ->
    { time = time; level = level lv; meth = meth; path = path; status = number "status" status; ms = millis ms }
  | _ -> Throw.throw "expected 6 fields"

let levelName lv =
  match lv with
  | Debug -> "DEBUG"
  | Info -> "INFO"
  | Warn -> "WARN"
  | Err -> "ERROR"
