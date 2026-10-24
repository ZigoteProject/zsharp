// The whole program under test, with no disk and no terminal: Io.Memory supplies both.
// Run with: zs test (from examples/logstat)
open Testing
open Io

let api =
  [ "2025-12-09T10:00:01Z INFO GET /api/users 200 20ms"
    "2025-12-09T10:00:02Z ERROR GET /api/reports 500 900ms"
    "garbage" ]
  |> String.join "\n"

let disk =
  [ ("logs/api.log", api)
    ("logs/old/web.log", "2025-12-08T22:10:01Z INFO GET /api/users 200 40ms")
    ("logs/notes.txt", "not a log") ]
  |> Map.ofList

// App.run with an in-memory disk and terminal: the exit code and what was printed
let logstat args = Memory.terminal (fun () -> Memory.files disk (fun () -> App.run args))

[<Tests>]
let tests =
  testList "logstat" [
    test "summarises a directory" (fun () ->
      let (code, screen) = logstat [ "--top"; "1"; "logs" ]
      assert (code = 0)
      assert (screen.err = [])
      assert (List.head screen.out = "3 entries, 1 unreadable lines")
      assert (List.contains "  GET /api/users          2 hits, avg 30 ms, 0% 5xx" screen.out)
      assert (List.contains "  ! logs/api.log:3: expected 6 fields" screen.out))

    test "verbose logs discovery to stderr" (fun () ->
      let (_, screen) = logstat [ "-v"; "logs" ]
      assert (screen.err = [ "logstat: logs: 2 log files" ]))

    test "a missing file is reported and fails the run" (fun () ->
      let (code, screen) = logstat [ "logs/api.log"; "nope.log" ]
      assert (code = 1)
      assert (screen.err = [ "logstat: cannot open nope.log: No such file or directory" ])
      assert (List.head screen.out = "2 entries, 1 unreadable lines"))

    test "bad arguments print usage" (fun () ->
      let (code, screen) = logstat [ "--top"; "x" ]
      assert (code = 2)
      assert (screen.out = [])
      assert (screen.err = [ $"logstat: --top needs a positive number, got 'x'\n{Cli.Args.usage}" ]))
  ]
