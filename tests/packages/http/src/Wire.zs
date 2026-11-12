// Http.parseRequest on any bytes: a request or an error, never a crash. `zs test src/Wire.zs`
// runs it on random bytes; `zs fuzz src/Wire.zs "requests/parses anything"` under libFuzzer,
// the parser and its C built with the sanitizers.
open Testing
open Http

[<Tests>]
let tests =
  testList "requests" [
    test "a request" (fun () ->
      let text = "POST /a/b?c=d HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\n\r\nhi and more"
      match parseRequest (Array.ofSpan (String.bytes text)) with
      | Ok r ->
        assert (r.method = Post && r.path = "/a/b" && r.query = "c=d")
        assert (Request.text r = "hi" && Request.header "HOST" r = Some "x")
      | Error e -> panic (Error.message e))
    test "half a request" (fun () ->
      match parseRequest (Array.ofSpan (String.bytes "GET / HTTP/1.1\r\nHost")) with
      | Error Ended -> ()
      | _ -> panic "not Ended")
    testProperty "parses anything" (fun () ->
      prop {
        let! input = Gen.bytes ()
        let _ = parseRequest input
        return true
      })
  ]
