// Property tests: laws that hold for any input, checked on random ones (see Check.zs).
// Run with: zs test (from examples/logstat)
open Testing
open Check
open Domain.Entry
open Domain.Stats
open Domain

// ---- generators

let genEntry () =
  { time = $"2025-12-{10 + Gen.below 20}T10:{10 + Gen.below 50}:00Z"
    level = pick [ Debug; Info; Warn; Err ]
    meth = pick [ "GET"; "POST"; "DELETE" ]
    path = pick [ "/"; "/api/users"; "/api/orders"; "/health" ]
    status = pick [ 200; 201; 404; 429; 500; 503 ]
    ms = Gen.below 5000 }

let format (e: Entry) = $"{e.time} {levelName e.level} {e.meth} {e.path} {e.status} {e.ms}ms"

let genLines () = List.init (Gen.below 12) (fun _ -> format (genEntry ()))

// lines that are mostly wrong: real fields and junk, shuffled, in any number
let genJunk () =
  List.init (Gen.below 9) (fun _ -> pick [ "INFO"; "GET"; "/a"; "200"; "12ms"; "ms"; "-1"; "x"; ""; "  " ])
  |> String.join " "

let genStats () = Chunk.countFile ("f", String.join "\n" (List.append (genLines ()) [ genJunk () ]))

[<Tests>]
let tests =
  testList "properties" [
    test "parse reads back what format writes" (fun () ->
      assert (check 1000 (fun () ->
        let e = genEntry ()
        (e, Throw.catch (fun () -> Entry.parse (format e)) = Ok e)) = None))

    test "parse never panics, and rejects what isn't 6 fields" (fun () ->
      assert (check 2000 (fun () ->
        let line = genJunk ()
        let fields = String.split " " line |> List.filter (fun w -> w <> "") |> List.length
        let r = Throw.catch (fun () -> Entry.parse line)
        (line, fields = 6 || r = Error "expected 6 fields")) = None))

    test "every non-blank line is counted or reported" (fun () ->
      assert (check 500 (fun () ->
        let lines = List.append (genLines ()) [ genJunk (); ""; genJunk () ]
        let s = Chunk.countFile ("f", String.join "\n" lines)
        let nonBlank = lines |> List.filter (fun l -> String.trimStart l <> "") |> List.length
        (lines, s.lines + List.length s.bad = nonBlank)) = None))

    test "zero is the identity" (fun () ->
      assert (check 300 (fun () ->
        let a = genStats ()
        (a, Add.zero + a = a && a + Add.zero = a)) = None))

    test "+ is associative" (fun () ->
      assert (check 300 (fun () ->
        let (a, b, c) = (genStats (), genStats (), genStats ())
        ((a, b, c), (a + b) + c = a + (b + c))) = None))

    // the split point doesn't matter, bad lines' numbers included
    test "a file counted in two parts adds up to the whole" (fun () ->
      assert (check 300 (fun () ->
        let lines = List.append (genLines ()) [ genJunk (); ""; genJunk () ]
        let cut = Gen.below (List.length lines + 1)
        // a file splits at line ends: each part keeps its lines' "\n"
        let part xs = Chunk.countFile ("f", String.concat (List.map (fun l -> l + "\n") xs))
        (lines, part lines = part (List.take cut lines) + part (List.skip cut lines))) = None))

    // the fast path, one call per line, is the monoid's +, just cheaper
    test "addEntry s e = s + ofEntry e" (fun () ->
      assert (check 1000 (fun () ->
        let (s, e) = (genStats (), genEntry ())
        ((s, e), addEntry s e = s + ofEntry e)) = None))

    // why the parallel run is right: however a file is cut, its chunks add up to the whole
    test "chunks of any size add up to the whole file" (fun () ->
      assert (check 500 (fun () ->
        let text = String.join "\n" (List.append (genLines ()) [ genJunk (); "  " ])
        let size = 1 + Gen.below 200
        let parts = Chunk.cut size ("f", text) |> List.map Chunk.count |> List.sum
        ((size, text), parts = Chunk.countFile ("f", text))) = None))
  ]
