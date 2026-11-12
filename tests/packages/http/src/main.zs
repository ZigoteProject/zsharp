// packages/http (0032): a server and a client of this program's own over loopback. Requests of
// each kind and their answers, redirects, what the server refuses (not HTTP, a head or a body
// past its limits, a request that never ends), two requests on one connection, the same over
// TLS with a certificate made as the test starts, and what the client refuses.
open Http

let handler (req: Request) : Task<Response> =
  task {
    match req.method, req.path with
    | Get, "/hello" -> return Response.text 200 "hello"
    | Head, "/hello" -> return Response.text 200 "hello"
    | Post, "/echo" ->
      let kind = Option.defaultValue "none" (Request.header "content-type" req)
      return Response.bytes 200 kind req.body
    | Get, "/query" -> return Response.text 200 $"query: {req.query}"
    | Get, "/big" ->
      return Response.bytes 200 "application/octet-stream" (Array.create 300000 (u8 7))
    | Get, "/moved" -> return Response.empty 302 |> Response.withHeader "Location" "/hello"
    | Post, "/see" -> return Response.empty 303 |> Response.withHeader "Location" "query?from=see"
    | Get, "/loop" -> return Response.empty 302 |> Response.withHeader "Location" "/loop"
    | Get, "/secret" ->
      return Response.text 200 (Option.defaultValue "no authorization" (Request.header "Authorization" req))
    | Get, "/smuggle" -> return Response.text 200 "x" |> Response.withHeader "X-A" "1\r\nX-B: 2"
    | Get, "/nothing" -> return Response.empty 204
    | Get, "/stream" ->
      // a body written as it's made, a piece at a time
      return Response.stream 200 "text/plain" (fun write ->
        task {
          for i in 1 .. 3 do
            let! _ = write (Array.ofSpan (String.bytes $"piece {i}; "))
            ()
        })
    | Get, "/slow" ->
      let! _ = Task.sleep 150
      return Response.text 200 "slow, and whole"
    | Post, "/upload" ->
      // a body read in pieces, of any size (a server with streamRequests)
      let mutable total = 0
      let mutable pieces = 0
      let mutable more = true
      while more do
        let! piece = Request.read req
        match piece with
        | Ok bytes when Array.length bytes > 0 ->
          total <- total + Array.length bytes
          pieces <- pieces + 1
        | _ -> more <- false
      return Response.text 200 $"{total} bytes, in more than one piece: {pieces > 1}"
    | _ -> return Response.text 404 $"no {req.path}"
  }

let show (r: result<Response, Error>) : string =
  match r with
  | Ok res ->
    let body =
      if Array.length res.body > 60 then $"{Array.length res.body} bytes" else Response.body res
    $"{res.status} {body}"
  | Error (Io _) -> "error: the socket"
  | Error (Secure (Tls.Failed (_, m))) -> $"error: {m}"
  | Error e -> $"error: {Error.message e}"

// what a server answers to bytes sent as they are, in parts a moment apart: each response's
// status
let rawParts (port: int) (parts: list<string>) : Task<string> =
  task {
    let! connected = Tcp.connect "127.0.0.1" port
    match connected with
    | Error e -> return e
    | Ok stream ->
      use s = stream
      for part in parts do
        let! _ = Tcp.writeText s part
        let! _ = Task.sleep 50
        ()
      let buf = Buffer.create 65536 (u8 0)
      let mutable all = ""
      let mutable more = true
      while more do
        let! r = Tcp.read s buf
        match r with
        | Ok n when n > 0 -> all <- all + String.ofBytes buf.[0 .. n - 1]
        | _ -> more <- false
      // a response may begin right after the last one's body
      let statuses =
        String.split "HTTP/1.1 " all |> List.tail |> List.map (fun r -> String.sub r 0 3)
      return String.join ", " statuses
  }

let raw (port: int) (text: string) : Task<string> = rawParts port [ text ]

let requests (port: int) (secure: option<Tls.ClientConfig>) : Task<unit> =
  task {
    let scheme = if Option.isSome secure then "https" else "http"
    let at = $"{scheme}://127.0.0.1:{port}"
    let config = { Client.defaults with tls = secure; timeout = 5000 }
    let ask (method: Method) (path: string) (headers: list<string * string>) (body: string) =
      Client.send config method (at + path) headers (Array.ofSpan (String.bytes body))
    let! a = ask Get "/hello" [] ""
    println $"GET /hello: {show a}"
    let! b = ask Head "/hello" [] ""
    let length = Result.map (fun r -> Option.defaultValue "" (Response.header "content-length" r)) b
    println $"HEAD /hello: {show b}, Content-Length {Result.defaultValue "" length}"
    let! c = ask Post "/echo" [ ("Content-Type", "text/x-test") ] "some text"
    let kind = Result.map (fun r -> Option.defaultValue "" (Response.header "Content-Type" r)) c
    println $"POST /echo: {show c} ({Result.defaultValue "" kind})"
    let! d = ask Get "/query?a=1&b=two%20words" [] ""
    println $"GET /query: {show d}"
    let! e = ask Get "/big" [] ""
    println $"GET /big: {show e}"
    let! f = ask Get "/moved" [] ""
    println $"GET /moved: {show f}"
    let! g = ask Post "/see" [ ("Content-Type", "text/plain") ] "posted"
    println $"POST /see: {show g}"
    let! h = ask Get "/loop" [] ""
    println $"GET /loop: {show h}"
    let! i = ask Get "/nowhere" [] ""
    println $"GET /nowhere: {show i}"
    let! j = ask Get "/smuggle" [] ""
    println $"GET /smuggle: {show j}"
    let! k = ask Get "/nothing" [] ""
    println $"GET /nothing: {show k}"
    let! l = ask Post "/echo" [] (String.repeat 2000 "x")
    println $"POST /echo, 2000 bytes: {show l}"
    let! m = ask Get "/secret" [ ("Authorization", "Bearer abc") ] ""
    println $"GET /secret: {show m}"
    let! n = ask Get "/stream" [] ""
    let framing =
      Result.map (fun r -> Option.defaultValue "none" (Response.header "transfer-encoding" r)) n
    println $"GET /stream: {show n} ({Result.defaultValue "" framing})"
  }

let refusals (port: int) : Task<unit> =
  task {
    let! a = raw port "this is not HTTP\r\n\r\n"
    println $"not HTTP: {a}"
    let! b =
      raw port ("GET /hello HTTP/1.1\r\nHost: x\r\nX-Long: " + String.repeat 3000 "a" + "\r\n\r\n")
    println $"a head past the limit: {b}"
    let! c =
      raw port "GET /hello HTTP/1.1\r\nHost: x\r\n\r\nGET /nowhere HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n"
    println $"two requests on a connection: {c}"
    let! d = raw port "GET /hello HTTP/1.1\r\nHost: x\r\nX-Unfinished: "
    println $"a request that never ends: {d}"
    let! e =
      rawParts port [ "POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 4\r\nExpect: 100-continue\r\nConnection: close\r\n\r\n"; "abcd" ]
    println $"Expect: 100-continue: {e}"
    let! f =
      raw port "POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n4\r\nabcd\r\n0\r\n\r\n"
    println $"a chunked body: {f}"
    let! g =
      raw port "POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 4\r\nContent-Length: 5\r\n\r\nabcd"
    println $"two lengths: {g}"
    let! h =
      raw port "GET /hello HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: upgrade\r\n\r\n"
    println $"an upgrade asked for, and not given: {h}"
    let! i = raw port "GET /stream HTTP/1.0\r\n\r\n"
    println $"a stream to HTTP/1.0, ended by the close: {i}"
  }

let serving (config: Server.Config) (body: int -> Task<unit>) : unit =
  match Server.listen config with
  | Error e -> println (Error.message e)
  | Ok made ->
    use l = made
    Task.run (Task.scope (fun scope ->
        task {
          Task.start scope (Server.run l handler) |> ignore
          let! _ = body l.port
          Task.cancel scope
        }))

let main () =
  let limits =
    { Server.defaults with port = 0
      maxBodyBytes = 1000
      maxHeaderBytes = 2000
      headerTimeout = 300
      idleTimeout = 300 }
  println "== over TCP"
  serving limits (fun port ->
    task {
      let! _ = requests port None
      println "== refused by the server"
      let! _ = refusals port
      ()
    })
  println "== over TLS"
  match Tls.Config.selfSigned "127.0.0.1" with
  | Error e -> println (Tls.Error.message e)
  | Ok (certificate, key) ->
    match Tls.Config.server certificate key, Tls.Config.clientTrusting certificate with
    | Ok server, Ok client ->
      use s = server
      use c = client
      serving { limits with tls = Some s } (fun port ->
        task {
          let! _ = requests port (Some c)
          // the system's authorities don't know this certificate
          let! stranger =
            Client.send { Client.defaults with timeout = 5000 } Get $"https://127.0.0.1:{port}/hello" [] [||]
          println $"without the certificate trusted: {show stranger}"
          let! plain = raw port "GET /hello HTTP/1.1\r\nHost: x\r\n\r\n"
          println $"plain HTTP to it: [{plain}]"
        })
    | _ -> println "no configuration"
  println "== requests' bodies in pieces"
  serving { limits with streamRequests = true } (fun port ->
    task {
      let big = Array.create 500000 (u8 1)
      let! a = Client.send Client.defaults Post $"http://127.0.0.1:{port}/upload" [] big
      println $"POST /upload, 500000 bytes: {show a}"
      let! b =
        Client.send Client.defaults Post $"http://127.0.0.1:{port}/echo" [] (Array.create 10 (u8 65))
      println $"a handler that doesn't read: {show b}"
      let! c =
        raw port "POST /query HTTP/1.1\r\nHost: x\r\nContent-Length: 4\r\n\r\nabcdGET /hello HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n"
      println $"an unread body, then the next request: {c}"
    })
  println "== a session's connections"
  serving limits (fun port ->
    task {
      use session = Client.session { Client.defaults with timeout = 5000 }
      let at = $"http://127.0.0.1:{port}"
      let! a = Client.sendIn session Get (at + "/hello") [] [||]
      let! b = Client.sendIn session Get (at + "/query?second") [] [||]
      println $"two requests: {show a}; {show b}; connections made: {session.made.Value}"
      // the server closes a connection idle for 300 ms: the next request finds that out
      let! _ = Task.sleep 500
      let! c = Client.sendIn session Get (at + "/hello") [] [||]
      println $"after the server closed it: {show c}; connections made: {session.made.Value}"
      let! d = Client.sendIn session Post (at + "/echo") [] (Array.create 3 (u8 66))
      println $"a POST: {show d}; connections made: {session.made.Value}"
    })
  println "== a stop"
  match Server.listen limits with
  | Error e -> println (Error.message e)
  | Ok made ->
    use l = made
    let (ended, answered) =
      Task.run (Task.both (Server.run l handler) (task {
            let asking = Client.send Client.defaults Get $"http://127.0.0.1:{l.port}/slow" [] [||]
            let stopping =
              task {
                let! _ = Task.sleep 50
                Server.stop l
              }
            let! (r, _) = Task.both asking stopping
            return r
          }))
    println $"the request being answered: {show answered}"
    println $"the server: {Result.isOk ended}"
    dispose l
    println $"a request after it: {show (Task.run (Client.get $"http://127.0.0.1:{l.port}/hello"))}"
  println "== refused by the client"
  let refused (url: string) = println $"{url}: {show (Task.run (Client.get url))}"
  refused "ftp://example.org/"
  refused "http://user@example.org/"
  refused "http://example.org:99999/"
  refused "http://exa mple.org/"
  refused "http://127.0.0.1:1/"
  let bad =
    Task.run (Client.send Client.defaults Get "http://127.0.0.1:1/" [ ("X-A", "1\r\nX-B: 2") ] [||])
  println $"a header with a line end: {show bad}"
  0
