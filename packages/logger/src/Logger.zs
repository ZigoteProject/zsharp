/// Logging: records with a level and fields, written to sinks.
///
/// - **A `Logger` is its sinks.** `write` gives it a record from any thread: sinks get one
///   record at a time. A level no sink wants costs a comparison.
/// - **A `Sink` is a record of a level and a function,** so a program makes its own.
///   `Sink.stderr`, `Sink.file` (which rotates) and `Sink.memory` (the last records, to show)
///   are here, with `Format.text` and `Format.json` for a record's line.
/// - **`queued`** gives a logger whose records are written by another thread, for sinks that
///   are slow. When that thread falls behind, records are dropped and counted, not waited for.
/// - **The `Log` effect** is for code that shouldn't hold a logger: `info "ready"` shows in
///   the function's type, `into logger source` sends what a call logs to a logger, and
///   `collect` gives it to a test.
/// - **A sink never fails its caller:** a file that can't be written loses the record, and
///   a text line's control characters are escaped, so a message can't forge a line.

/// How much a record matters, least first. A sink takes its level and those above it.
type Level =
  | Trace
  | Debug
  | Info
  | Warn
  | Fail

/// A level's name as a line shows it.
let levelName (level: Level) : string =
  match level with
  | Trace -> "TRACE"
  | Debug -> "DEBUG"
  | Info -> "INFO"
  | Warn -> "WARN"
  | Fail -> "ERROR"

/// Something that happened: when, how much it matters, the part of the program that says
/// so, the message, and named values beside it.
type Record =
  { time: DateTime
    level: Level
    source: string
    message: string
    fields: list<string * string> }

/// A record's named values, in order.
type Fields = list<string * string>

/// A field from any value that shows: `field "tries" 3`.
let field (key: string) (value: 'a) : string * string = (key, $"{value}")

/// A record's line.
module Format =
  // a control character as an escape, and for JSON the quote and the backslash too
  let private escaped (json: bool) (text: string) : string =
    let one (c: char) : string =
      match c with
      | '\n' -> "\\n"
      | '\r' -> "\\r"
      | '\t' -> "\\t"
      | '"' when json -> "\\\""
      | '\\' when json -> "\\\\"
      | _ when int c < 32 || int c = 127 -> $"\\u{int c:X4}"
      | _ -> String.ofChars [ c ]
    let special (c: char) : bool = int c < 32 || int c = 127 || (json && (c = '"' || c = '\\'))
    // most text needs nothing: look without making anything first
    let mutable any = false
    for c in text do
      if special c then any <- true
    if any then
      String.join "" (List.map one (String.chars text))
    else
      text

  // a field's value, in quotes when it is empty or holds a space, a quote or an equals sign,
  // so that `key=value` pairs read back unambiguously
  let private value (v: string) : string =
    let plain = escaped false v
    let odd (c: char) : bool = c = ' ' || c = '"' || c = '='
    let mutable quoted = plain = ""
    for c in plain do
      if odd c then quoted <- true
    if not quoted then plain
    else "\"" + String.replace plain "\"" "\\\"" + "\""

  /// `2026-11-21T08:00:00Z WARN  net: retrying tries=3 host="a b"`: a line a person reads.
  /// Control characters are escaped, so a record is always one line.
  let text (record: Record) : string =
    let fields = List.map (fun (k, v) -> $" {escaped false k}={value v}") record.fields
    let head =
      $"{DateTime.toIso record.time} {levelName record.level,-5} {escaped false record.source}"
    $"{head}: {escaped false record.message}{String.join "" fields}"

  /// A JSON object on one line, for a program to read: `time`, `level`, `source`, `message`,
  /// then each field as a string.
  let json (record: Record) : string =
    let pair (k: string) (v: string) : string = $"\"{escaped true k}\":\"{escaped true v}\""
    let head =
      [ pair "time" (DateTime.toIso record.time)
        pair "level" (String.toLower (levelName record.level))
        pair "source" record.source
        pair "message" record.message ]
    let all = head @ List.map (fun (k, v) -> pair k v) record.fields
    "{" + String.join "," all + "}"

/// Where records go: the least level it takes, and what it does with a record. `write` may
/// be called from any thread, one call at a time for a logger's sinks.
type Sink = { least: Level; write: share<Record -> unit> }

/// The sinks that come with the package, and what changes one.
module Sink =
  /// Lines on standard error.
  let stderr (least: Level) (format: share<Record -> string>) : Sink =
    { least = least; write = fun record -> eprintln (format record) }

  /// Lines added to a file. Once the file has grown past `maxBytes` it is moved to
  /// `<path>.1`, over the one before it, and a new file begun. A line that can't be written
  /// (no room, no directory) is lost, not reported: a log mustn't fail its program.
  let file (path: string) (maxBytes: int) (least: Level) (format: share<Record -> string>) : Sink =
    let size = Atomic.make (int (Result.defaultValue (i64 0) (File.size path)))
    let write (record: Record) : unit =
      let line = format record + "\n"
      if Atomic.get size > maxBytes then
        File.move path (path + ".1") |> ignore
        Atomic.set size 0
      if Result.isOk (File.appendAllText path line) then
        Atomic.add size (String.length line) |> ignore
    { least = least; write = write }

  /// The records a `memory` sink holds: how many, and the records, newest first.
  type Memory = Memory of Mutex<int * list<Record>>

  /// A sink that keeps the last `capacity` records, and what reads them: for a window that
  /// shows a program's own log, or a report sent after a failure. A write is a cons; the
  /// list is cut back to the capacity once it has doubled, so its cost is spread thin.
  let memory (capacity: int) (least: Level) : Sink * Memory =
    let held = Mutex.make (0, [])
    let keep (record: Record) (count: int, records: list<Record>) : int * list<Record> =
      if count >= 2 * capacity then (capacity, record :: List.take (capacity - 1) records)
      else (count + 1, record :: records)
    let write (record: Record) : unit = Mutex.update held (keep record) |> ignore
    ({ least = least; write = write }, Memory held)

  /// The records held, oldest first.
  let records (capacity: int) (Memory held) : list<Record> =
    List.rev (List.take capacity (snd (Mutex.get held)))

  /// A sink that gets only the records `keep` says to, of those the sink takes.
  let filter (keep: share<Record -> bool>) (sink: Sink) : Sink =
    let inner = sink.write
    { least = sink.least; write = fun record -> if keep record then inner record }

/// Sinks, written to one record at a time. It can be shared between threads.
type Logger =
  { sinks: list<Sink>
    /// The least level any sink takes.
    least: Level
    /// How many records were written, and the lock they are written under.
    count: Mutex<int> }

/// A logger over sinks.
let create (sinks: list<Sink>) : Logger =
  let least = List.fold (fun (l: Level) (s: Sink) -> min l s.least) Fail sinks
  { sinks = sinks; least = least; count = Mutex.make 0 }

/// Whether a record of this level would reach a sink: for a message that is costly to make.
let enabled (logger: Logger) (level: Level) : bool =
  level >= logger.least && not (List.isEmpty logger.sinks)

/// Writes a record to the sinks that take its level, now, on this thread.
let write (logger: Logger) (level: Level) (source: string) (message: string) (fields: Fields) =
  if enabled logger level then
    let record =
      { time = DateTime.utcNow ()
        level = level
        source = source
        message = message
        fields = fields }
    let toSinks (written: int) : int =
      for sink in logger.sinks do
        if level >= sink.least then sink.write record
      written + 1
    Mutex.update logger.count toSinks |> ignore

/// How many records the logger has written.
let written (logger: Logger) : int = Mutex.get logger.count

/// Records waiting for the thread that writes them.
type Queue =
  { channel: Channel<option<Record>>
    waiting: Atomic<int>
    lost: Atomic<int>
    target: Logger }

/// A logger whose records are written to `sinks` by whichever thread runs `drain`: logging
/// costs a record handed over, however slow the sinks. At most `capacity` records wait; one
/// logged past that is dropped and counted (`dropped`), so a stalled disk never stalls the
/// program.
let queued (capacity: int) (sinks: list<Sink>) : Logger * Queue =
  let target = create sinks
  // room for every waiting record and for the one that ends the draining
  let channel = Channel.make (capacity + 1)
  let waiting = Atomic.make 0
  let lost = Atomic.make 0
  let hand (record: Record) : unit =
    if Atomic.add waiting 1 > capacity then
      Atomic.add waiting -1 |> ignore
      Atomic.add lost 1 |> ignore
    else
      Channel.send channel (Some record)
  let queue = { channel = channel; waiting = waiting; lost = lost; target = target }
  (create [ { least = target.least; write = hand } ], queue)

/// Writes the waiting records to the sinks, and those that come, until `close`. It blocks:
/// run it on a thread of its own (`pump`, or `Parallel.both`).
let drain (queue: Queue) : unit =
  let mutable going = true
  while going do
    match Channel.receive queue.channel with
    | Some (Some record) ->
      Atomic.add queue.waiting -1 |> ignore
      let toSinks (n: int) : int =
        for sink in queue.target.sinks do
          if record.level >= sink.least then sink.write record
        n + 1
      Mutex.update queue.target.count toSinks |> ignore
    | Some None | None -> going <- false

/// `drain` on a helper thread, as a task for a program that has an event loop.
let pump (queue: Queue) : Task<unit> = Task.blocking (fun () -> drain queue)

/// Ends `drain`, once what is waiting has been written. Records logged after it are dropped.
let close (queue: Queue) : unit = Channel.send queue.channel None

/// How many records were dropped because too many were waiting.
let dropped (queue: Queue) : int = Atomic.get queue.lost

/// Logging as an effect: a function that logs has `Log` in its type, and what handles it
/// decides where the records go. `event` takes a level, a message and fields; `wants` says
/// whether a level is listened to.
effect Log =
  abstract event : Level * string * list<string * string> -> unit
  abstract wants : Level -> bool

/// Logs a message at a level, with fields.
let event (level: Level) (message: string) (fields: list<string * string>) : unit =
  Log.event (level, message, fields)

/// Logs a message at `Trace`.
let trace (message: string) : unit = Log.event (Trace, message, [])

/// Logs a message at `Debug`.
let debug (message: string) : unit = Log.event (Debug, message, [])

/// Logs a message at `Info`.
let info (message: string) : unit = Log.event (Info, message, [])

/// Logs a message at `Warn`.
let warn (message: string) : unit = Log.event (Warn, message, [])

/// Logs a message at `Fail`.
let fail (message: string) : unit = Log.event (Fail, message, [])

/// Logs a message that is made only if its level is listened to: for one that is costly.
let lazily (level: Level) (message: unit -> string) : unit =
  if Log.wants level then Log.event (level, message (), [])

/// Runs `body`, what it logs going to a logger under a source's name.
let into (logger: Logger) (source: string) (body: unit -> 'a) : 'a =
  handle body () with
  | Log.event (level, message, fields), k ->
    write logger level source message fields
    k ()
  | Log.wants level, k -> k (enabled logger level)

/// Runs `body`, what it logs going nowhere.
let silent (body: unit -> 'a) : 'a =
  handle body () with
  | Log.event _, k -> k ()
  | Log.wants _, k -> k false

/// Runs `body` and gives its result with what it logged, in order: for a test.
let collect (body: unit -> 'a) : 'a * list<Level * string * list<string * string>> =
  let mutable seen = []
  let result =
    handle body () with
    | Log.event logged, k ->
      seen <- logged :: seen
      k ()
    | Log.wants _, k -> k true
  (result, List.rev seen)
