// Unit tests: each module on its own, with no handlers beyond the ones a test needs.
// Run with: zs test (from examples/logstat)
open Testing
open Cli.Args
open Domain.Entry
open Domain.Stats

let entry = { time = "t"; level = Info; meth = "GET"; path = "/a"; status = 200; ms = 12 }

let tryParse line = Throw.catch (fun () -> Domain.Entry.parse line)
let tryArgs xs = Throw.catch (fun () -> Cli.Args.parse xs)

let parseCases =
  [ ("t INFO GET /a 200 12ms", Ok entry)
    ("t   INFO  GET /a 200 12ms", Ok entry)
    ("t ERROR GET /a 500 12ms", Ok { entry with level = Err; status = 500 })
    ("t TRACE GET /a 200 12ms", Error "unknown level 'TRACE'")
    ("t INFO GET /a 2x0 12ms", Error "bad status '2x0'")
    ("t INFO GET /a 200 12", Error "bad duration '12'")
    ("t INFO GET /a 200 xms", Error "bad duration 'x'")
    ("t INFO GET /a 200", Error "expected 6 fields")
    ("", Error "expected 6 fields") ]

[<Tests>]
let tests =
  testList "units" [
    testList "Entry.parse" [
      for (line, expected) in parseCases -> test $"'{line}'" (fun () -> assert (tryParse line = expected))
    ]

    testList "Args.parse" [
      test "defaults" (fun () ->
        assert (tryArgs [ "a.log" ] = Ok { top = 3; timeoutMs = 2000; verbose = false; inputs = [ "a.log" ] }))
      test "flags anywhere, inputs in order" (fun () ->
        assert (tryArgs [ "a"; "-v"; "--top"; "7"; "b"; "--timeout"; "50" ]
                = Ok { top = 7; timeoutMs = 50; verbose = true; inputs = [ "a"; "b" ] }))
      test "no inputs" (fun () -> assert (tryArgs [ "-v" ] = Error "no input files"))
      test "unknown flag" (fun () -> assert (tryArgs [ "--fast"; "a" ] = Error "unknown option --fast"))
      test "zero is not positive" (fun () -> assert (tryArgs [ "--top"; "0"; "a" ] = Error "--top needs a positive number, got '0'"))
      test "a flag missing its value" (fun () -> assert (tryArgs [ "a"; "--top" ] = Error "unknown option --top"))
    ]

    testList "Stats" [
      test "counts a file" (fun () ->
        let s = Domain.Chunk.countFile ("f", "t INFO GET /a 200 10ms\n\nt WARN GET /a 503 30ms\nnope")
        assert (s.lines = 2)
        assert (s.bad = [ { file = "f"; line = 4; why = "expected 6 fields" } ])
        assert (Map.toList s.seen = [ ("f", 4) ])
        assert (Map.toList s.levels = [ ("INFO", 1); ("WARN", 1) ])
        assert (Map.toList s.routes = [ ("GET /a", { hits = 2; totalMs = 40; errors = 1 }) ]))
      test "keeps the five slowest" (fun () ->
        let text = List.init 8 (fun i -> $"t INFO GET /a 200 {i + 1}ms") |> String.join "\n"
        assert ((Domain.Chunk.countFile ("f", text)).slowest |> List.map (fun e -> e.ms) = [ 8; 7; 6; 5; 4 ]))
    ]

    test "Report.render" (fun () ->
      let s = Domain.Chunk.countFile ("f", "t INFO GET /a 200 10ms\nt ERROR POST /b 500 90ms\nbad")
      let (_, screen) = Io.Memory.terminal (fun () -> Output.Report.render 1 s)
      expect (String.join "\n" screen.out) """
        2 entries, 1 unreadable lines
          ERROR       1  50%
          INFO        1  50%

        top 1 routes by traffic:
          GET /a                  1 hits, avg 10 ms, 0% 5xx

        slowest requests:
              90 ms  POST /b (500) at t
              10 ms  GET /a (200) at t

        unreadable lines:
          ! f:3: expected 6 fields
        """)
  ]
