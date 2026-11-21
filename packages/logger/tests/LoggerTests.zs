open Testing
open Logger

let private at : DateTime =
  match DateTime.ofParts 2026 11 21 8 0 0 0 with
  | Some t -> t
  | None -> panic "a date"

let private record (level: Level) (message: string) (fields: list<string * string>) : Record =
  { time = at; level = level; source = "net"; message = message; fields = fields }

// a sink that keeps every record's message, for a test to read
let private kept (least: Level) : Sink * Mutex<list<string>> =
  let seen = Mutex.make []
  ({ least = least; write = fun r -> Mutex.update seen (fun xs -> xs @ [ r.message ]) |> ignore },
    seen)

// a function that logs, as a program's would: its type says so
let private connect (tries: int) : bool =
  info "connecting"
  for i in 1 .. tries do
    event Warn "retrying" [ field "try" i ]
  lazily Debug (fun () -> "costly")
  tries < 3

[<Tests>]
let tests =
  testList "logger" [
    test "a text line, a value with a space or a quote in quotes" (fun () ->
      let fields = [ field "tries" 3; ("host", "a b"); ("q", "x=\"y\""); ("e", "") ]
      let line = Format.text (record Warn "retrying" fields)
      let want =
        "2026-11-21T08:00:00Z WARN  net: retrying tries=3 host=\"a b\" q=\"x=\\\"y\\\"\" e=\"\""
      assert (line = want))
    test "a message can't make a second line or a false field" (fun () ->
      expect (Format.text (record Info "ok\n2026-11-21T08:00:00Z ERROR forged\t\u{7f}" [ ("k\r", "v\n") ])) """
        2026-11-21T08:00:00Z INFO  net: ok\n2026-11-21T08:00:00Z ERROR forged\t\u007F k\r=v\n
        """)
    test "a JSON line" (fun () ->
      let line = Format.json (record Fail "said \"no\" \\ here\n" [ field "code" 7 ])
      let head = "{\"time\":\"2026-11-21T08:00:00Z\",\"level\":\"error\",\"source\":\"net\","
      let want = head + "\"message\":\"said \\\"no\\\" \\\\ here\\n\",\"code\":\"7\"}"
      assert (line = want))
    test "levels are ordered least first" (fun () ->
      assert (Trace < Debug && Debug < Info && Info < Warn && Warn < Fail))
    test "a sink takes its level and those above it" (fun () ->
      let (low, lows) = kept Debug
      let (high, highs) = kept Warn
      let logger = create [ low; high ]
      for (level, m) in [ (Trace, "t"); (Debug, "d"); (Info, "i"); (Warn, "w"); (Fail, "f") ] do
        write logger level "x" m []
      expect (Mutex.get lows, Mutex.get highs, written logger) "([d; i; w; f], [w; f], 4)")
    test "a level no sink takes isn't enabled, and a logger with no sinks takes nothing" (fun () ->
      let (sink, _) = kept Warn
      expect (enabled (create [ sink ]) Info,
        enabled (create [ sink ]) Fail,
        enabled (create []) Fail) "(false, true, false)")
    test "a filter passes only what it keeps" (fun () ->
      let (sink, seen) = kept Trace
      let logger = create [ Sink.filter (fun r -> r.source = "ble") sink ]
      write logger Info "ble" "kept" []
      write logger Info "ui" "dropped" []
      expect (Mutex.get seen) "[kept]")
    test "memory keeps the last records, oldest first" (fun () ->
      let (sink, held) = Sink.memory 3 Trace
      let logger = create [ sink ]
      for i in 1 .. 10 do
        write logger Info "x" $"{i}" []
      expect (List.map (fun (r: Record) -> r.message) (Sink.records 3 held)) "[8; 9; 10]")
    test "the effect: what a function logs goes to the logger, under its source" (fun () ->
      let (sink, held) = Sink.memory 10 Info
      let ok = into (create [ sink ]) "bt" (fun () -> connect 2)
      let lines = List.map Format.text (Sink.records 10 held)
      expect (ok, List.map (fun (l: string) -> String.join " " (List.tail (String.split " " l))) lines) "(true, [INFO  bt: connecting; WARN  bt: retrying try=1; WARN  bt: retrying try=2])")
    test "the effect: a level nothing listens to isn't made" (fun () ->
      let made = ref false
      let (sink, _) = Sink.memory 10 Info
      let costly () : string =
        made.Value <- true
        "costly"
      into (create [ sink ]) "x" (fun () -> lazily Debug costly)
      assert (not made.Value))
    test "collect gives a test what was logged" (fun () ->
      expect (collect (fun () -> connect 1)) "(true, [(Logger.Info, connecting, []); (Logger.Warn, retrying, [(try, 1)]); (Logger.Debug, costly, [])])")
    test "silent drops everything" (fun () -> expect (silent (fun () -> connect 4)) "false")
    test "a file rotates once past its size, and a line that can't be written is lost quietly" (fun () ->
      let dir = Result.defaultValue "" (Directory.createTemp "logger")
      let path = Path.combine dir "app.log"
      let logger = create [ Sink.file path 100 Trace Format.text ]
      for i in 1 .. 4 do
        write logger Info "x" $"line {i} of a log that grows" []
      let nowhere = create [ Sink.file (Path.combine dir "no/such/dir.log") 100 Trace Format.text ]
      write nowhere Fail "x" "lost" []
      let lines (p: string) : int = List.length (Result.defaultValue [] (File.readAllLines p))
      let counted = (lines path, lines (path + ".1"))
      Directory.deleteRecursive dir |> ignore
      expect counted "(2, 2)")
    test "many threads at once: no record lost or mixed" (fun () ->
      let (sink, held) = Sink.memory 100000 Trace
      let logger = create [ sink ]
      Parallel.for 0 2000 (fun i -> write logger Info "t" $"{i}" [ field "i" i ])
      let records = Sink.records 100000 held
      let whole = List.forall (fun (r: Record) -> r.fields = [ ("i", r.message) ]) records
      expect (List.length records,
        written logger,
        whole,
        List.length (List.distinct (List.map (fun (r: Record) ->
              r.message) records))) "(2000, 2000, true, 2000)")
    test "queued: another thread writes the records, in order" (fun () ->
      let (sink, held) = Sink.memory 1000 Trace
      let (logger, queue) = queued 1000 [ sink ]
      let produce () : unit =
        for i in 1 .. 500 do
          write logger Info "q" $"{i}" []
        close queue
      Parallel.both (fun () -> drain queue) produce |> ignore
      let got =
        List.map (fun (r: Record) -> int (Option.defaultValue 0 (String.parseInt r.message))) (Sink.records 1000 held)
      expect (List.length got, got = List.init 500 (fun i -> i + 1), dropped queue) "(500, true, 0)")
    test "queued: with nothing draining, records past the capacity are dropped, not waited for" (fun () ->
      let (sink, held) = Sink.memory 100 Trace
      let (logger, queue) = queued 10 [ sink ]
      for i in 1 .. 25 do
        write logger Info "q" $"{i}" []
      close queue
      drain queue
      expect (List.length (Sink.records 100 held), dropped queue) "(10, 15)")
    testProperty "any text is one line, in both formats" (fun (message: string, key: string, value: string) ->
      let r = record Info message [ (key, value) ]
      let oneLine (s: string) : bool =
        not (List.exists (fun c -> c = '\n' || c = '\r') (String.chars s))
      oneLine (Format.text r) && oneLine (Format.json r))
    ]
