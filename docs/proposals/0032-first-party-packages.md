# Proposal 0032: first-party packages: `sqlite`, `tls` and `http`

| | |
|---|---|
| **Status** | Draft |
| **Decided at** | not yet: a design review, with [0031](0031-stability-and-support.md) |
| **Builds** | track K's first-party packages ([ROADMAP](../../ROADMAP.md#packages-k)), after 0.7 |
| **Rests on** | decisions 26 (`zig cc`), 27 (source packages), 37 (Core and Std), 83 (versions) in [DESIGN §13](../../DESIGN.md#13-decisions); [0018 packages](0018-packages.md) (the `[c]` section, "wrap before writing"); `Task.waitFor` and `Task.blocking`; `packages/libclang` and `packages/xxhash` as the form |
| **Related** | [0001 type providers](0001-type-providers.md) (`sql`, and `rows = "sqlite"`); [0024 the library's API](0024-library-api.md) (what stays a package); track S's items 12 (bytes in C memory) and 14 (completion-based I/O); [security](../contributing/security.md) (hostile input) |
| **Changes** | three packages under `packages/`; their tests in the suite; the guide's [Programs](../guide/08-programs.md); no language change, and no library change unless question 2 is taken |

- [ ] Approved in principle
- [ ] Discussion
- [ ] Implementation

## Summary

A service needs to answer HTTP, speak TLS and keep data. Z# has TCP sockets and tasks, and
nothing above them: the twelve-dollar server wrote its own HTTP and its own SQLite binding,
half of it `unsafe`. This proposal designs the three packages that close that, each a thin,
typed Z# API over a C library that's already trusted with the job:

| Package | Wraps | Why that one |
|---|---|---|
| `sqlite` | SQLite's amalgamation (public domain) | one C file; the most deployed database there is |
| `tls` | Mbed TLS (Apache-2.0) | TLS 1.2 and 1.3, plain C, builds with `zig cc` everywhere, and on a Cortex-M later |
| `http` | llhttp (MIT), Node's parser | the part of HTTP where bugs are security bugs, in three C files |

The Z# in each is what C can't give: types that make a misuse a compile error, `use` for
every handle, `Task` for every wait, and limits on by default. None of the three rewrites its
library's work.

```fsharp
open Http
open Sqlite

let handle (db: Db) (req: Request) : Task<Response> =
  task {
    match req.method, req.path with
    | Get, "/health" -> return Response.text 200 "ok"
    | Get, "/users" ->
      let names = Db.query db "select name from users order by name" [] (fun row -> Row.text row 0)
      return Response.json 200 (toJson names)
    | _ -> return Response.text 404 "not found"
  }

let main () =
  match Db.open "app.db" with
  | Error e -> printfn $"{e}"
  | Ok opened ->
    use db = opened
    let tls = Tls.Config.ofFiles "cert.pem" "key.pem"
    let config = { Server.defaults with port = 8443; tls = Some tls }
    Task.run (Server.serve config (handle db)) |> ignore
```

## Motivation

**The server that had to write everything.** The twelve-dollar server's `Fast/` modules are
about half its Z#: index loops over `ptr<u8>` to parse requests, and a SQLite binding by hand.
Track S's item 12 gave it safe bytes; nothing gave it HTTP. Every Z# service starts by
writing the same thing, and a hand-written HTTP parser facing the internet is the defect
`SECURITY.md` calls "the library mishandling hostile input", once per program.

**What production means here.** A service that can't terminate TLS sits behind a proxy that
can, which is a fine deployment and a poor requirement. One that can't call another service
over HTTPS can't use an API. One without a database keeps state in files.

**Why not write them in Z#.** A TLS stack is years of review, and so is SQLite. A community
that could maintain either in Z# isn't coming soon ([track K](../../ROADMAP.md#packages-k));
the libraries exist, have C APIs, and are permissively licensed. The same reasoning picked
libclang and xxhash for the compiler.

## Design

### What the three share

- **Layout.** A package is `packages/<name>/` as `libclang` and `xxhash` are: `zs.toml` with a
  `[c]` section, the Z# modules, and `c/` holding the library's release **unmodified** plus a
  shim where one is needed. `c/VERSION` records the upstream release and the SHA-256 of its
  archive; a script in the package checks the files against it. Updating a library is
  replacing `c/` and the two lines, in one commit.
- **Two layers.** `<Name>.Native` is `import c` over the header: every function the package
  uses, as C has it, for the program that needs what the typed layer doesn't offer. The
  modules above it use no `unsafe` in their public signatures.
- **Handles.** Each C handle is a one-case union with a `Dispose` impl, so `use` closes it
  and a cancelled task closes it too. A handle C frees is never reachable after: the API gives
  no function that returns a closed one.
- **Errors are values.** `result<_, Error>` with a union per package (`Sqlite.Error`,
  `Tls.Error`, `Http.Error`), each case carrying the library's code and message. A panic only
  for a bug in the caller that a type couldn't prevent (a column index out of range).
- **Waiting.** A socket wait is `Task.waitFor` on the descriptor, as `Tcp` does it: the
  libraries are driven non-blocking and never own the loop. A call that blocks and can't be
  made not to (a SQLite write waiting on a lock) is offered through `Task.blocking`.
- **Limits by default.** Every size and every wait an outside party controls has a bound in
  the configuration record, with a default that's safe, not unlimited.
- **Targets.** Tier 1 ([0031](0031-stability-and-support.md)): the six hosts. The packages
  use Std, so a chip build rejects them by name (K5). Mbed TLS and SQLite both run on a
  Cortex-M; that's a later proposal with the embedded runtime's sockets, not this one.
- **Versions.** Each starts at 0.1 and follows 0018: its own 1.0 is part of the language's
  1.0 gate. A security release of a wrapped library is a patch release of the package within
  0031's window.

### `sqlite`

From the server's `Fast.Sqlite`, as the roadmap says:

```fsharp
type Db = | Db of ptr<Native.sqlite3>            // Dispose: sqlite3_close_v2
type Statement = | Statement of ptr<Native.sqlite3_stmt>   // Dispose: sqlite3_finalize

type Value = | Null | Int of i64 | Real of float | Text of string | Blob of array<u8>
type Step = | Row | Done | Failed of Error

module Db =
  let open (path: string) : result<Db, Error>
  let openWith (options: Options) (path: string) : result<Db, Error>   // read-only, busy timeout
  let prepare (db: Db) (sql: string) : result<Statement, Error>
  let exec (db: Db) (sql: string) (args: list<Value>) : result<int, Error>   // rows changed
  let query (db: Db) (sql: string) (args: list<Value>) (read: Row -> 'a)
    : result<list<'a>, Error>
  // rolls back on Error or a throw
  let transaction (db: Db) (body: unit -> result<'a, Error>) : result<'a, Error>

module Statement =
  let bind (s: Statement) (args: list<Value>) : result<unit, Error>
  let step (s: Statement) : Step
  let reset (s: Statement) : unit

module Row =
  let int (r: Row) (column: int) : i64
  let text (r: Row) (column: int) : string         // a copy
  let isNull (r: Row) (column: int) : bool
```

- **No string building.** Values reach SQL only through `bind`. There's no function that
  takes SQL and values and formats them together, so injection needs the caller to
  concatenate by hand.
- **Text is copied in the typed layer.** The server reads a column as a span of SQLite's own
  bytes, valid until the next step, and that's where its speed comes from. Nothing in the
  language stops such a span from being kept past the step: a span is safe because it holds
  its owner ([0003](0003-spans-and-slices.md)), and C memory has none. So the borrowing form
  is `Native.columnSpan`, under `unsafe`, and `Row.text` copies (question 8).
- **Threads.** SQLite is built serialized (`SQLITE_THREADSAFE=1`), so a `Db` is `Share` and
  may be used from `Task.blocking` or another thread. One connection per thread is still what
  performs; the docs say so.
- **Built with** the flags SQLite recommends for an application (`SQLITE_DQS=0`,
  `SQLITE_DEFAULT_FOREIGN_KEYS=1`, WAL available, a busy timeout of 5 s by default instead
  of failing at once).
- **With the `sql` provider.** The provider already types a query against a schema; with this
  package its generated functions run the query (0001's `rows = "sqlite"`): a later step, and
  the reason `Value` and `Row` are shaped as they are.

### `tls`

```fsharp
type TlsStream                                  // Dispose: close_notify, then the socket
module Tls =
  let connect (config: ClientConfig) (host: string) (stream: TcpStream)
    : Task<result<TlsStream, Error>>
  let accept (config: ServerConfig) (stream: TcpStream) : Task<result<TlsStream, Error>>
  let read (s: TlsStream) (buf: Buffer<u8>) : Task<result<int, Error>>
  let write (s: TlsStream) (buf: Buffer<u8>) (n: int) : Task<result<unit, Error>>

module Config =
  let client : ClientConfig                     // the system's roots, the host name checked
  let ofFiles (certificate: string) (key: string) : ServerConfig
  let withRoots (pemFile: string) (c: ClientConfig) : ClientConfig
```

- **Safe by default, and no switch for unsafe.** `Config.client` verifies the chain and the
  host name. There's no `verify = false`: a test uses `withRoots` and its own certificate.
- **The same four functions as `Tcp`,** so code over a connection reads the same either way.
- **I/O.** Mbed TLS reads and writes the socket through its own `net_sockets` functions on the
  stream's descriptor, non-blocking; `WANT_READ` and `WANT_WRITE` become `Task.waitFor`. No
  callback from C into Z# on the data path.
- **Randomness and time** come from the OS through Mbed TLS's own entropy sources.
- **System roots.** Mbed TLS doesn't read the platform's trust store. A shim per OS does: the
  certificate files on Linux, the Security framework on macOS, the system store on Windows.
  About fifty lines of C each, and the part of this package most likely to be wrong.
- **Configuration is compiled in:** one `mbedtls_config.h`, TLS 1.2 and 1.3, the modern
  suites, no legacy protocol versions. A program can't turn old ones on.

### `http`

```fsharp
type Method = | Get | Head | Post | Put | Patch | Delete | Options | Other of string
type Request = { method: Method; path: string; query: string; headers: Headers; body: Body }
type Response = { status: int; headers: Headers; body: Body }

module Server =
  type Config = {
    host: string; port: int; tls: option<Tls.ServerConfig>
    maxHeaderBytes: int        // 16 KB
    maxBodyBytes: int          // 1 MB; a handler may read more by asking
    headerTimeout: Duration    // 10 s for the request line and headers
    idleTimeout: Duration      // 60 s between requests on a connection
    maxConnections: int        // 10,000
  }
  let defaults : Config
  let serve (config: Config) (handler: Request -> Task<Response>) : Task<result<unit, Error>>

module Client =
  let send (config: Client.Config) (req: Request) (url: string) : Task<result<Response, Error>>
  let get (url: string) : Task<result<Response, Error>>
```

- **llhttp parses,** requests on the server and responses on the client, chunked bodies
  included. The Z# is the connection loop: read, feed the parser, call the handler, write.
- **A connection is a task** in the server's scope, as `examples/echo` does it. Cancelling
  `serve` stops accepting, lets requests in flight finish for a grace period, then cancels
  them: each `use` closes its socket. That's graceful shutdown, with no code of its own.
- **Bodies stream.** `Body` is read in pieces (`Body.read`), or whole up to the limit
  (`Body.readAll`); a response body is bytes, a string, or a function that writes pieces.
- **A handler that panics** answers 500 for that request and the connection closes; the
  server goes on. A handler that throws a typed exception is the same, with the exception
  logged through the configured sink.
- **Not a framework.** No router beyond `match` on the method and the path, no middleware
  type: a function from `Request` to `Task<Response>` composes with ordinary functions.
- **HTTP/1.1 only** here. HTTP/2 is another library (nghttp2) and a later proposal.
- **The client** is the same parser and the same `tls`: one request over one connection, with
  redirects (bounded), a total timeout, and a connection reused for the next request to the
  same host. Question 1 asks whether it should be libcurl instead.
- **Item 14 of track S** (completion-based I/O, answers batched in place) replaces the
  connection loop under the same `serve`, when it's built. The API above doesn't change.

### Order of implementation

1. **`sqlite`:** the smallest, no network, and the server's code exists. It proves the
   layout, `c/VERSION` and the suite's package tests.
2. **`tls`:** client and server against each other in one test, then against a public host by
   hand.
3. **`http`:** the server on `Tcp`, then on `tls`, then the client.
4. `examples/echo` rebuilt on `http` (track K's exit test), and the twelve-dollar server's
   `Fast.Sqlite` replaced by `sqlite`.

## Drawbacks

- **Vendored C is a duty.** Three libraries' security releases have to be followed. That's
  the cost of every binding, and smaller than the cost of having written the code.
- **Build time.** Mbed TLS is about a hundred C files and SQLite's one file is 250,000 lines.
  The first build of a project compiles them; whether `[c]` objects are cached across builds
  the way modules are needs measuring before this is approved.
- **Two memory models meet.** A statement SQLite owns or a buffer Mbed TLS holds is C memory
  under Z# types. The typed layer is where that has to be exactly right, and it's the code a
  review should read first.
- **Mbed TLS is slower** than the assembly-tuned stacks at bulk encryption. A service that
  cares terminates TLS in front, as it would have without this package.

## Alternatives

- **rustls, through rustls-ffi,** for `tls`: memory-safe, fast, and its platform verifier
  solves the system roots properly. But a package would need cargo and a Rust target per
  platform on every user's machine, or prebuilt archives per target in the package:
  `zs add tls` stops being the whole setup, and packages stop being source (decision 27).
  `examples/rust` shows the route works; it's the right choice if Mbed TLS's root-store shims
  or its speed turn out to be the problem.
- **OpenSSL or BoringSSL:** the fastest and the most deployed. Neither builds from a list of
  sources with `zig cc` (perl and assembly generation; CMake and Go), and neither fits a chip.
- **The system's TLS** (SChannel, Secure Transport, OpenSSL where installed): no vendoring,
  three APIs to wrap and three behaviours to test.
- **A whole HTTP server library** (h2o, civetweb, mongoose): each brings its own event loop
  and threads, which is what `Task` already is. Wrapping one means two schedulers.
- **picohttpparser** instead of llhttp: faster and smaller, and it leaves chunked bodies and
  the strictness rules to the caller. llhttp's are Node's, tested by the internet.
- **Postgres first** (libpq): what larger services use. It needs a server to test against and
  its own TLS; `sqlite` needs nothing. Next, with the same `Value` and `Row` shapes.
- **In Std instead of packages.** They'd be on every machine with no `zs add`. But Std would
  then carry three C libraries' releases in the compiler's own, and 0024 already drew the
  line: formats and protocols with many reasonable designs are packages.

## Compatibility

New packages: nothing existing changes. They need the release they're written against or a
later one; `zs.toml` gains no key. If question 2 is taken, Std gains a trait and `Tcp` an
impl, both additions.

## Pragmatics

- **Diagnostics:** a chip build that names one of these fails with K5's error. A missing
  certificate file, a failed handshake and a busy database are `Error` values whose text
  includes the library's own message.
- **Tooling:** the packages' `///` comments are read by `zs doc` and the LSP as the library's
  are. `zs doctor` gains nothing: there's no system dependency to look for.
- **Testing:** `tests/packages/` in the suite: `sqlite` round trips, a transaction rolled back
  by a throw, and everything closed under `ZS_LEAKCHECK=1`; `tls` client against server with a
  certificate generated when the test runs (no key is checked in); `http` request and response
  cases, each limit and each timeout reached on purpose. The request path runs under
  `zs fuzz` and the suite's `--sanitize` and `--valgrind` modes with the C included.
- **Performance:** the exit test is the twelve-dollar server at its present instructions per
  request with `sqlite` in place of `Fast.Sqlite`. `http` on tasks is expected to be slower
  than that server's hand-written loop until item 14; the proposal doesn't claim otherwise.
- **Licenses:** each package's `LICENSE` carries its library's, and a built program's notice
  obligations (Apache-2.0's, MIT's) are listed in the package's README.

## Unresolved questions

1. **The client: llhttp and `tls`, or libcurl?** The design above writes a small client in
   Z# over the same parser. libcurl is the robust one, and the rule for these packages is to
   wrap what's robust: proxies, HTTP/2, cookies, every redirect corner. But it's some two
   hundred source files and a configuration header kept by hand per platform, where the
   others are one to a hundred files with none. Recommended: the small client in `http` for
   calling an API, and a separate `curl` package when a program needs the rest, so a server
   never compiles it.
2. **A `Stream` trait in Std?** `http` runs over a `TcpStream` or a `TlsStream`. As designed
   it holds a two-case union and depends on `tls`. A trait (`read`, `write`) in `Net` would
   let `http` not know about `tls`, and serve Unix sockets and a test's in-memory stream too.
   It's a type packages must agree on, which is Std's job by track S's own rule; it's also a
   library addition this proposal would rather not need.
3. **Where they live.** `packages/` in this repository is where the suite can build them at
   every commit. Versions by tag (0018) want a repository each, and so does track K's exit
   test (`zs add` and nothing more). Develop here and publish to `zsharp/<name>` from a
   script, or move them out once they're stable?
4. **SQLite and tasks.** Reads are microseconds and are called inline; a write can wait on a
   lock. Is `Task.blocking` at the caller enough, or should `Db` have task-returning forms?
5. **System roots:** the three shims, or ship Mozilla's bundle in the package and accept that
   it ages with the package's releases?
6. **Logging.** `http` has to report a handler's failure somewhere. A function in the
   configuration is enough for this proposal; a `log` package or a Std type is its own
   question.
7. **`regex`, `cli`, `raylib`** are on the roadmap's list beside these. Not designed here:
   none blocks a service.
8. **A column's bytes without a copy, safely.** It needs a span that can't outlive a scope,
   which the language doesn't have. A function taking the reader (`Row.withText r 0 f`) only
   narrows it: `f` can still return the span. Leave it under `unsafe`, or is this the case
   that justifies a proposal for scoped borrows?

## History

- 2026-11-12: written after 0.7.1, from the question of what production use needs; the
  libraries are the roadmap's (track K), the SQLite shapes the twelve-dollar server's.
