# http

An HTTP/1.1 server and client for Z#, on `Net.Tcp`, tasks and the `tls` package, with llhttp
reading every message ([proposal 0032](../../docs/proposals/0032-first-party-packages.md)).

```fsharp
open Http

let handler (req: Request) : Task<Response> =
  task {
    match req.method, req.path with
    | Get, "/hello" -> return Response.text 200 "hello"
    | _ -> return Response.text 404 "not found"
  }

let main () =
  match Task.run (Server.serve { Server.defaults with port = 8080 } handler) with
  | Ok () -> 0
  | Error e ->
    println (Error.message e)
    1
```

- **Use:** `http = { path = "…/packages/http" }` under `[dependencies]`. `src/Http.zs`'s doc
  comments are the reference; `examples/service` is a whole program.
- **A server's limits are on by default:** 16 KB of headers, 1 MB of body, 10 seconds for a
  request to arrive, 60 between requests, 10,000 connections (`Server.defaults`). HTTPS is a
  `Tls.ServerConfig` in the configuration.
- **A client** (`Client.get`, `post`, `send`) follows redirects, verifies certificates, and has a
  timeout and a limit on the body it accepts.
- **Bodies are whole, in memory,** unless a server sets `streamRequests` (a handler then
  reads with `Request.read`) or a handler answers with `Response.stream`. `Server.stop` ends
  a server once the requests being answered have finished; `Client.session` keeps a client's
  connections open. No HTTP/2, no upgrades, no proxies.
- **Targets:** those with an operating system.
- **The library:** llhttp 9.4.3's generated C in `c/llhttp`, unmodified; `c/VERSION` says where
  it's from and how to update it.
- **License:** this package's code is the repository's (MIT). llhttp is MIT
  (`c/llhttp/LICENSE`), and this package brings `tls` and so Mbed TLS (Apache-2.0): a program
  distributed with it includes both notices.
