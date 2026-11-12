/// HTTP/1.1 (proposal 0032): a server and a client on `Net.Tcp`, tasks and the `tls` package,
/// with llhttp (`c/llhttp`, Node's parser) reading every message. A server is a function from
/// a `Request` to a task of a `Response`; each connection is a task, and every size and wait a
/// peer controls has a limit in the configuration. A body is whole, in memory, up to its limit,
/// unless a server asks for requests' bodies in pieces (`streamRequests`) or a handler answers
/// with `Response.stream`.

extern zs_http_new : i32 -> usize -> cptr
extern zs_http_free : cptr -> unit
extern zs_http_no_body : cptr -> i32 -> unit
extern zs_http_feed : cptr -> span<u8> -> i32
extern zs_http_finish : cptr -> i32
extern zs_http_next : cptr -> unit
extern zs_http_consumed : cptr -> usize
extern zs_http_head_done : cptr -> i32
extern zs_http_error : cptr -> cstr
extern zs_http_method : cptr -> cstr
extern zs_http_status : cptr -> i32
extern zs_http_keep_alive : cptr -> i32
extern zs_http_minor : cptr -> i32
extern zs_http_url : cptr -> ptr<u8>
extern zs_http_url_length : cptr -> usize
extern zs_http_headers : cptr -> usize
extern zs_http_name : cptr -> usize -> ptr<u8>
extern zs_http_name_length : cptr -> usize -> usize
extern zs_http_value : cptr -> usize -> ptr<u8>
extern zs_http_value_length : cptr -> usize -> usize
extern zs_http_body : cptr -> ptr<u8>
extern zs_http_body_length : cptr -> usize
extern zs_http_body_taken : cptr -> unit

/// Why a call failed.
type Error =
  /// The socket failed, with the system's message.
  | Io of message: string
  /// TLS failed.
  | Secure of Tls.Error
  /// The peer sent what isn't HTTP, with the parser's reason.
  | Malformed of reason: string
  /// A head or a body larger than the configuration allows.
  | TooLarge
  /// The time the configuration allows ran out.
  | TimedOut
  /// The connection ended before a whole message came.
  | Ended
  /// Not a URL this client can ask for, with why.
  | BadUrl of reason: string
  /// More redirects than the configuration allows.
  | TooManyRedirects

/// A request's method.
type Method =
  /// GET.
  | Get
  /// HEAD.
  | Head
  /// POST.
  | Post
  /// PUT.
  | Put
  /// PATCH.
  | Patch
  /// DELETE.
  | Delete
  /// OPTIONS.
  | Options
  /// Any other method, by its name in capitals.
  | Other of string

/// A request, as a server's handler gets it.
type Request =
  { /// The method.
    method: Method
    /// The path, as sent (percent-encoded), without the query.
    path: string
    /// The query after the `?`, as sent; empty when there's none.
    query: string
    /// The headers in the order sent.
    headers: list<string * string>
    /// The body, whole; empty when it's read in pieces.
    body: array<u8>
    /// What gives the body's next piece, for a server with `streamRequests` (`Request.read`).
    reader: option<unit -> Task<result<array<u8>, Error>>> }

/// A response: what a handler gives, and what the client gets.
type Response =
  { /// The status code.
    status: int
    /// The headers. A server adds `Content-Length` and `Connection` itself.
    headers: list<string * string>
    /// The body, whole; empty when the response is streamed.
    body: array<u8>
    /// What writes a streamed body, a piece a call of the function it's given
    /// (`Response.stream`).
    stream: option<(array<u8> -> Task<result<unit, Error>>) -> Task<unit>> }

/// Functions on `Error`.
module Error =
  /// The error as a line of text.
  let message (e: Error) : string =
    match e with
    | Io m -> m
    | Secure t -> Tls.Error.message t
    | Malformed reason -> $"not HTTP: {reason}"
    | TooLarge -> "too large"
    | TimedOut -> "timed out"
    | Ended -> "the connection ended early"
    | BadUrl reason -> $"bad URL: {reason}"
    | TooManyRedirects -> "too many redirects"

/// Functions on `Method`.
module Method =
  /// The method's name: `GET`.
  let name (m: Method) : string =
    match m with
    | Get -> "GET"
    | Head -> "HEAD"
    | Post -> "POST"
    | Put -> "PUT"
    | Patch -> "PATCH"
    | Delete -> "DELETE"
    | Options -> "OPTIONS"
    | Other n -> n

  /// The method of a name in capitals.
  let ofName (n: string) : Method =
    match n with
    | "GET" -> Get
    | "HEAD" -> Head
    | "POST" -> Post
    | "PUT" -> Put
    | "PATCH" -> Patch
    | "DELETE" -> Delete
    | "OPTIONS" -> Options
    | _ -> Other n

/// Functions on a list of headers.
module Headers =
  /// The first header of the name, whatever its letters' case.
  let tryFind (name: string) (headers: list<string * string>) : option<string> =
    let wanted = String.toLower name
    headers
    |> List.tryFind (fun (n, _) -> String.toLower n = wanted)
    |> Option.map (fun (_, v) -> v)

  /// The headers with the name's one set to the value, replacing any there.
  let set (name: string) (value: string) (headers: list<string * string>) : list<string * string> =
    let wanted = String.toLower name
    List.append (List.filter (fun (n, _) -> String.toLower n <> wanted) headers) [ (name, value) ]

/// Functions on `Request`.
module Request =
  /// The first header of the name, whatever its letters' case.
  let header (name: string) (r: Request) : option<string> = Headers.tryFind name r.headers

  /// The body as text (a byte that isn't UTF-8 reads as U+FFFD).
  let text (r: Request) : string = String.ofBytes r.body.[0..]

  /// The next piece of the body of a request read in pieces (a server with `streamRequests`):
  /// empty at its end, and for a request that isn't read that way.
  let read (r: Request) : Task<result<array<u8>, Error>> =
    match r.reader with
    | Some next -> next ()
    | None -> task { return Ok [||] }

/// Functions on `Response`.
module Response =
  /// A response with a body of bytes and its `Content-Type`.
  let bytes (status: int) (contentType: string) (body: array<u8>) : Response =
    { status = status; headers = [ ("Content-Type", contentType) ]; body = body; stream = None }

  /// A response with a body of plain text.
  let text (status: int) (body: string) : Response =
    bytes status "text/plain; charset=utf-8" (Array.ofSpan (String.bytes body))

  /// A response whose body is JSON text.
  let json (status: int) (body: string) : Response =
    bytes status "application/json" (Array.ofSpan (String.bytes body))

  /// A response with no body.
  let empty (status: int) : Response =
    { status = status; headers = []; body = [||]; stream = None }

  /// A response whose body is written as it's made: `produce` gets a function that sends a
  /// piece and waits until it's gone, and the body ends when `produce` does. A piece that
  /// can't be sent (the client has gone) is an `Error`, and so is every one after it.
  let stream (status: int) (contentType: string) (produce: (array<u8> -> Task<result<unit, Error>>) -> Task<unit>) : Response =
    { status = status
      headers = [ ("Content-Type", contentType) ]
      body = [||]
      stream = Some produce }

  /// The response with a header set.
  let withHeader (name: string) (value: string) (r: Response) : Response =
    { r with headers = Headers.set name value r.headers }

  /// The first header of the name, whatever its letters' case.
  let header (name: string) (r: Response) : option<string> = Headers.tryFind name r.headers

  /// The body as text (a byte that isn't UTF-8 reads as U+FFFD).
  let body (r: Response) : string = String.ofBytes r.body.[0..]

// a connection, plain or under TLS
type private Conn =
  | Plain of TcpStream
  | Tlsed of Tls.TlsStream

impl Dispose<Conn> =
  let dispose (c: Conn) =
    match c with
    | Plain s -> dispose s
    | Tlsed s -> dispose s

// llhttp's parser for one connection, freed by `use`
type private Parser = { handle: cptr; freed: ref<bool> }

impl Dispose<Parser> =
  let dispose (p: Parser) =
    if not p.freed.Value then
      p.freed.Value <- true
      zs_http_free p.handle

// what reading a message came to
type private Incoming =
  // a whole message is in the parser; the bytes read after it
  | Whole of rest: array<u8>
  // the connection ended where no message had begun
  | Nothing
  // the head is in and the body isn't whole (asked for with mode 1)
  | HeadIn
  // some of the body came and more will (mode 2)
  | Piece
  | Problem of Error

let private readConn (c: Conn) (buf: Buffer<u8>) : Task<result<int, Error>> =
  task {
    match c with
    | Plain s ->
      let! r = Tcp.read s buf
      return Result.mapError (fun e -> Io e) r
    | Tlsed s ->
      let! r = Tls.read s buf
      return Result.mapError (fun e -> Secure e) r
  }

let private writeConn (c: Conn) (data: array<u8>) : Task<result<unit, Error>> =
  task {
    let buf = Buffer.ofArray data
    match c with
    | Plain s ->
      let! r = Tcp.write s buf (Buffer.length buf)
      return Result.mapError (fun e -> Io e) r
    | Tlsed s ->
      let! r = Tls.write s buf (Buffer.length buf)
      return Result.mapError (fun e -> Secure e) r
  }

// a copy of n bytes of C memory as text
let private textAt (p: ptr<u8>) (n: usize) : string =
  if n = usize 0 then "" else String.ofBytes (unsafe (Span.ofPtr p (int n)))

// the headers of the message in the parser
let private headersOf (p: cptr) : list<string * string> =
  let count = int (zs_http_headers p)
  let mutable found = []
  let mutable i = count - 1
  while i >= 0 do
    let at = usize i
    let name = textAt (zs_http_name p at) (zs_http_name_length p at)
    let value = textAt (zs_http_value p at) (zs_http_value_length p at)
    found <- (name, value) :: found
    i <- i - 1
  found

// what one message's body may come to, and what has come
type private Taking = { limit: int; size: ref<int>; pieces: ref<list<array<u8>>> }

let private taking (limit: int) : Taking = { limit = limit; size = ref 0; pieces = ref [] }

let private bodyOf (t: Taking) : array<u8> = Array.concat (List.rev t.pieces.Value)

// Parses `data`, then reads and parses until a message is whole (mode 0), or until its head is
// in (mode 1), or until some of its body has come (mode 2). `onHead` runs once in mode 0, when
// the head is in and the body isn't yet (a server answers `Expect: 100-continue` there).
let rec private receive (c: Conn) (p: cptr) (buf: Buffer<u8>) (data: array<u8>) (t: Taking) (onHead: unit -> Task<unit>) (mode: int) : Task<Incoming> =
  task {
    if Array.length data = 0 then
      let! got = readConn c buf
      match got with
      | Ok n when n > 0 -> return! receive c p buf (Array.ofSpan buf.[0 .. n - 1]) t onHead mode
      | Error (Secure Tls.Truncated) when zs_http_head_done p = i32 0 -> return Nothing
      | Error e -> return Problem e
      | Ok _ ->
        // the end of the connection ends a message whose body has no length
        let r = zs_http_finish p
        if r = i32 1 then return Whole [||]
        else if r = i32 0 then return Nothing
        else return Problem Ended
    else
      let hadHead = zs_http_head_done p <> i32 0
      let r = zs_http_feed p data.[0..]
      let n = int (zs_http_body_length p)
      if n > 0 then
        t.size.Value <- t.size.Value + n
        if t.size.Value <= t.limit then
          t.pieces.Value <- Array.ofSpan (unsafe (Span.ofPtr (zs_http_body p) n)) :: t.pieces.Value
        zs_http_body_taken p
      if r < i32 0 then
        let reason = String.ofCStr (zs_http_error p)
        return Problem (if reason = "the head is too large" || reason = "too many headers" then
          TooLarge
        else
          Malformed reason)
      else if t.size.Value > t.limit then
        return Problem TooLarge
      else if r = i32 1 then
        let used = int (zs_http_consumed p)
        return Whole (Array.sub data used (Array.length data - used))
      else
        let headNow = not hadHead && zs_http_head_done p <> i32 0
        if headNow && mode = 1 then
          return HeadIn
        else if mode = 2 && n > 0 then
          return Piece
        else
          if headNow then
            let! _ = onHead ()
            ()
          return! receive c p buf [||] t onHead mode
  }

// whether a header's name and value can be written as they are: no line end smuggled in
let private writable (headers: list<string * string>) : bool =
  let clean (s: string) =
    List.forall (fun c -> c <> '\r' && c <> '\n' && u32 c <> u32 0) (String.chars s)
  let token (s: string) =
    not (String.isEmpty s) && List.forall (fun c -> c > ' ' && c <> ':' && u32 c < u32 127) (String.chars s)
  List.forall (fun (n, v) -> token n && clean v) headers

// header lines, without those this file writes itself
let private lines (headers: list<string * string>) (own: list<string>) : string =
  headers
  |> List.filter (fun (n, _) -> not (List.contains (String.toLower n) own))
  |> List.map (fun (n, v) -> $"{n}: {v}\r\n")
  |> String.concat

let private reason (status: int) : string =
  match status with
  | 200 -> "OK"
  | 201 -> "Created"
  | 202 -> "Accepted"
  | 204 -> "No Content"
  | 301 -> "Moved Permanently"
  | 302 -> "Found"
  | 303 -> "See Other"
  | 304 -> "Not Modified"
  | 307 -> "Temporary Redirect"
  | 308 -> "Permanent Redirect"
  | 400 -> "Bad Request"
  | 401 -> "Unauthorized"
  | 403 -> "Forbidden"
  | 404 -> "Not Found"
  | 405 -> "Method Not Allowed"
  | 408 -> "Request Timeout"
  | 409 -> "Conflict"
  | 413 -> "Content Too Large"
  | 429 -> "Too Many Requests"
  | 431 -> "Request Header Fields Too Large"
  | 500 -> "Internal Server Error"
  | 502 -> "Bad Gateway"
  | 503 -> "Service Unavailable"
  | _ -> if status < 400 then "OK" else "Error"

// the request in the parser, with its body
let private requestOf (p: cptr) (body: array<u8>) : Request =
  let url = textAt (zs_http_url p) (zs_http_url_length p)
  let (path, query) =
    match String.indexOf "?" url with
    | Some i -> (String.sub url 0 i, String.sub url (i + 1) (String.length url - i - 1))
    | None -> (url, "")
  { method = Method.ofName (String.ofCStr (zs_http_method p))
    path = path
    query = query
    headers = headersOf p
    body = body
    reader = None }

/// One whole request from its bytes, as a server reads it off a connection, with a server's
/// default limits: for a test, or a request that came some other way. Bytes after the request
/// are ignored; an `Error` when the bytes aren't one whole request.
let parseRequest (bytes: array<u8>) : result<Request, Error> =
  let made = zs_http_new (i32 0) (usize 16384)
  let raw: ptr<u8> = unsafe Ptr.ofCPtr made
  if Ptr.isNull raw then
    Error (Io "out of memory")
  else
    use parser = { handle = made; freed = ref false }
    let p = parser.handle
    let r = zs_http_feed p bytes.[0..]
    let n = int (zs_http_body_length p)
    if r = i32 1 && n <= 1048576 then
      let body = if n = 0 then [||] else Array.ofSpan (unsafe (Span.ofPtr (zs_http_body p) n))
      Ok (requestOf p body)
    else if r = i32 1 then
      Error TooLarge
    else if r = i32 0 then
      Error Ended
    else
      Error (Malformed (String.ofCStr (zs_http_error p)))

/// A server.
module Server =
  /// A server's address, its TLS, and the limits on what a client may send and how slowly.
  type Config =
    { /// The address to listen on.
      host: string
      /// The port.
      port: int
      /// The certificate and key to serve HTTPS with; `None` serves plain HTTP.
      tls: option<Tls.ServerConfig>
      /// The most a request's URL and headers may come to, in bytes.
      maxHeaderBytes: int
      /// The most a request's body may come to, in bytes.
      maxBodyBytes: int
      /// How long a request may take to arrive whole once its first bytes have, and how long
      /// a TLS handshake may take, in milliseconds.
      headerTimeout: int
      /// How long a connection may wait for its next request, in milliseconds.
      idleTimeout: int
      /// How many connections are served at once; one more is closed as it's accepted.
      maxConnections: int
      /// Whether a handler reads a request's body in pieces (`Request.read`), of any size,
      /// instead of getting it whole and limited by `maxBodyBytes`.
      streamRequests: bool
      /// How long requests being answered have to finish after `Server.stop`, in milliseconds.
      shutdownGrace: int }

  /// Port 8080 on this machine only, plain HTTP, 16 KB of headers, 1 MB of body, 10 seconds
  /// for a request to arrive, 60 between requests, 10,000 connections, bodies whole, and 5
  /// seconds for requests to finish at a stop.
  let defaults : Config =
    { host = "127.0.0.1"
      port = 8080
      tls = None
      maxHeaderBytes = 16384
      maxBodyBytes = 1048576
      headerTimeout = 10000
      idleTimeout = 60000
      maxConnections = 10000
      streamRequests = false
      shutdownGrace = 5000 }

  /// A server's socket, listening and not yet served (`Server.listen`); `use` closes it.
  type Listening =
    { /// The socket.
      listener: TcpListener
      /// The port it listens on: the one the system chose when the configuration's is 0.
      port: int
      /// The configuration it was made with.
      config: Config
      /// Fulfilled when the server is asked to stop (`Server.stop`).
      stopping: Promise<unit>
      /// Whether it has been asked to stop.
      stopped: ref<bool> }

  /// `use` closes the listening socket.
  impl Dispose<Listening> =
    let dispose (l: Listening) = dispose l.listener

  // the response's head and, unless `head` (the answer to a HEAD) or the status has none, its
  // body, as bytes; `close` says the connection ends after it. A streamed one's head has no
  // length: `framing` says how its body ends.
  let private encode (r: Response) (head: bool) (close: bool) (framing: string) : array<u8> =
    let bodiless = r.status < 200 || r.status = 204 || r.status = 304
    let streamed = Option.isSome r.stream
    let length = if bodiless || streamed then "" else $"Content-Length: {Array.length r.body}\r\n"
    let ending = if close then "Connection: close\r\n" else ""
    let own = [ "content-length"; "connection"; "transfer-encoding" ]
    let top =
      $"HTTP/1.1 {r.status} {reason r.status}\r\n{lines r.headers own}{length}{framing}{ending}\r\n"
    if head || bodiless || streamed then Array.ofSpan (String.bytes top)
    else Array.append (String.bytes top) r.body.[0..]

  // Sends the response: whether all of it went. `old` is a client of HTTP/1.0, to which a
  // streamed body is sent as it is and ends with the connection.
  let private answer (c: Conn) (given: Response) (head: bool) (close: bool) (old: bool) : Task<bool> =
    task {
      let r =
        if writable given.headers && given.status >= 100 && given.status <= 999 then given
        else Response.text 500 "the handler's response can't be sent"
      let bodiless = head || r.status < 200 || r.status = 204 || r.status = 304
      match r.stream with
      | Some produce when not bodiless ->
        let! started =
          writeConn c (encode r head close (if old then "" else "Transfer-Encoding: chunked\r\n"))
        let going = ref (Result.isOk started)
        let write (piece: array<u8>) : Task<result<unit, Error>> =
          task {
            if not going.Value then
              return Error Ended
            else if Array.length piece = 0 then
              return Ok ()
            else
              let size = Array.ofSpan (String.bytes $"{Array.length piece:X}\r\n")
              let framed =
                if old then
                  piece
                else
                  Array.concat [ size; piece; Array.ofSpan (String.bytes "\r\n") ]
              let! sent = writeConn c framed
              if Result.isError sent then going.Value <- false
              return sent
          }
        if going.Value then
          let! _ = produce write
          ()
        if going.Value && not old then
          let! last = writeConn c (Array.ofSpan (String.bytes "0\r\n\r\n"))
          return Result.isOk last
        else
          return going.Value
      | _ ->
        let! sent = writeConn c (encode r head close "")
        return Result.isOk sent
    }

  // reads what a handler left of a streamed body, `left` bytes at most: whether it ended
  let rec private drain (next: unit -> Task<result<array<u8>, Error>>) (left: int) : Task<bool> =
    task {
      let! piece = next ()
      match piece with
      | Ok bytes when Array.length bytes = 0 -> return true
      | Ok bytes when Array.length bytes <= left -> return! drain next (left - Array.length bytes)
      | _ -> return false
    }

  // Serves the connection's requests in turn: `data` is what has been read past the last one.
  let rec private requests (l: Listening) (handler: Request -> Task<Response>) (c: Conn) (p: cptr) (buf: Buffer<u8>) (data: array<u8>) : Task<unit> =
    task {
      let config = l.config
      // the next request's first bytes, waited for as long as an idle connection may be, or
      // until the server is asked to stop
      let! first =
        if Array.length data > 0 then task { return Some (Ok data) }
        else if l.stopped.Value then task { return None }
        else
          let reading =
            Task.timeout config.idleTimeout (task {
                let! got = readConn c buf
                return Result.map (fun n -> Array.ofSpan buf.[0 .. n - 1]) got
              })
          let halted =
            task {
              let! _ = Task.wait l.stopping
              return None
            }
          Task.race reading halted
      match first with
      | Some (Ok start) when Array.length start > 0 ->
        let t = taking (if config.streamRequests then 0x7FFFFFFF else config.maxBodyBytes)
        let expecting () : Task<unit> =
          task {
            match Headers.tryFind "expect" (headersOf p) with
            | Some v when String.toLower v = "100-continue" ->
              let! _ = writeConn c (Array.ofSpan (String.bytes "HTTP/1.1 100 Continue\r\n\r\n"))
              ()
            | _ -> ()
          }
        // the handler's answer sent: whether the connection may carry another request
        let respond (request: Request) : Task<bool> =
          task {
            let! response = handler request
            let wantsClose =
              match Response.header "connection" response with
              | Some v -> String.toLower v = "close"
              | None -> false
            let old = zs_http_minor p = i32 0
            let ends = old && Option.isSome response.stream
            let close = wantsClose || ends || l.stopped.Value || zs_http_keep_alive p = i32 0
            let! sent = answer c response (request.method = Head) close old
            return sent && not close
          }
        let mode = if config.streamRequests then 1 else 0
        let! got = Task.timeout config.headerTimeout (receive c p buf start t expecting mode)
        match got with
        | Some (Whole rest) ->
          // a body that came whole with its head is still read in pieces where they're asked for
          let whole = bodyOf t
          let given = ref (Array.length whole = 0)
          let once () : Task<result<array<u8>, Error>> =
            task {
              if given.Value then
                return Ok [||]
              else
                given.Value <- true
                return Ok whole
            }
          let request =
            if config.streamRequests then { requestOf p [||] with reader = Some once }
            else requestOf p whole
          let! on = respond request
          if on then
            zs_http_next p
            return! requests l handler c p buf rest
        | Some HeadIn ->
          // the body in pieces, as the handler asks for them
          let over = ref false
          let broken = ref false
          let rest = ref [||]
          let early = ref (bodyOf t)
          let told = ref false
          let next () : Task<result<array<u8>, Error>> =
            task {
              if Array.length early.Value > 0 then
                let piece = early.Value
                early.Value <- [||]
                return Ok piece
              else if over.Value then
                return Ok [||]
              else if broken.Value then
                return Error Ended
              else
                if not told.Value then
                  told.Value <- true
                  let! _ = expecting ()
                  ()
                let piece = taking 0x7FFFFFFF
                let! more =
                  Task.timeout config.idleTimeout (receive c p buf [||] piece (fun () ->
                      task { return () }) 2)
                match more with
                | Some (Whole after) ->
                  over.Value <- true
                  rest.Value <- after
                  return Ok (bodyOf piece)
                | Some Piece -> return Ok (bodyOf piece)
                | Some (Problem e) ->
                  broken.Value <- true
                  return Error e
                | Some _ ->
                  broken.Value <- true
                  return Error Ended
                | None ->
                  broken.Value <- true
                  return Error TimedOut
            }
          let! on = respond { requestOf p [||] with reader = Some next }
          let! ended = drain next config.maxBodyBytes
          if on && ended then
            zs_http_next p
            return! requests l handler c p buf rest.Value
        | Some (Problem TooLarge) ->
          let status = if zs_http_head_done p = i32 0 then 431 else 413
          let! _ = answer c (Response.text status (reason status)) false true false
          ()
        | Some (Problem (Malformed why)) ->
          let! _ = answer c (Response.text 400 why) false true false
          ()
        | Some _ -> ()
        | None ->
          let! _ = answer c (Response.text 408 (reason 408)) false true false
          ()
      | _ -> ()
    }

  // one accepted connection: TLS when the configuration has it, then its requests
  let private connection (l: Listening) (handler: Request -> Task<Response>) (stream: TcpStream) : Task<unit> =
    task {
      let config = l.config
      let! made =
        match config.tls with
        | None -> task { return Some (Plain stream) }
        | Some t ->
          task {
            let! s = Task.timeout config.headerTimeout (Tls.accept t stream)
            match s with
            | Some (Ok secure) -> return Some (Tlsed secure)
            | _ -> return None
          }
      match made with
      | None -> ()
      | Some conn ->
        use c = conn
        let made = zs_http_new (i32 0) (usize config.maxHeaderBytes)
        let raw: ptr<u8> = unsafe Ptr.ofCPtr made
        if not (Ptr.isNull raw) then
          use parser = { handle = made; freed = ref false }
          let! _ = requests l handler c parser.handle (Buffer.create 16384 (u8 0)) [||]
          ()
    }

  let rec private accepting (l: Listening) (handler: Request -> Task<Response>) (scope: Scope) (active: ref<int>) : Task<result<unit, Error>> =
    task {
      let! r = Tcp.accept l.listener
      match r with
      | Error e -> return Error (Io e)
      | Ok stream ->
        if active.Value >= l.config.maxConnections then
          dispose stream
        else
          active.Value <- active.Value + 1
          Task.start scope (task {
              let! _ = connection l handler stream
              active.Value <- active.Value - 1
            })
          |> ignore
        return! accepting l handler scope active
    }

  // waits until no connection is being served
  // ponytail: a poll every 10 ms; a promise fulfilled at the last one's end if this ever shows
  let rec private settled (active: ref<int>) : Task<unit> =
    task {
      if active.Value > 0 then
        let! _ = Task.sleep 10
        return! settled active
      else
        return ()
    }

  /// Listens on the configuration's address, without serving yet: for a program that needs
  /// the port before the first request (port 0 asks the system for a free one).
  let listen (config: Config) : result<Listening, Error> =
    match Tcp.listen config.host config.port with
    | Error e -> Error (Io e)
    | Ok l ->
      let (TcpListener fd) = l
      Ok { listener = l
        port = Udp.port (UdpSocket fd)
        config = config
        stopping = Task.promise ()
        stopped = ref false }

  /// Asks the server to stop: it accepts no more connections, closes those waiting for a
  /// request, lets the requests being answered finish for `shutdownGrace`, and `run` returns.
  let stop (l: Listening) : unit =
    l.stopped.Value <- true
    Task.fulfill l.stopping ()

  /// Answers each request on the listening socket with what `handler` gives for it, each
  /// connection a task of its own, until `Server.stop` (`Ok`) or until accepting fails (an
  /// `Error`); cancelling it closes every connection at once.
  let run (l: Listening) (handler: Request -> Task<Response>) : Task<result<unit, Error>> =
    Task.scope (fun scope ->
      task {
        let active = ref 0
        let asked =
          task {
            let! _ = Task.wait l.stopping
            return Ok ()
          }
        let! ended = Task.race (accepting l handler scope active) asked
        stop l
        let! _ = Task.timeout l.config.shutdownGrace (settled active)
        Task.cancel scope
        return ended
      })

  /// Listens and serves: `listen`, then `run`, the socket closed when it ends.
  let serve (config: Config) (handler: Request -> Task<Response>) : Task<result<unit, Error>> =
    task {
      match listen config with
      | Error e -> return Error e
      | Ok made ->
        use l = made
        return! run l handler
    }

/// A client: one request over one connection.
module Client =
  /// A client's limits, and what it trusts.
  type Config =
    { /// How long a request and its redirects may take in all, in milliseconds.
      timeout: int
      /// How many redirects are followed.
      maxRedirects: int
      /// The most a response's body may come to, in bytes.
      maxBodyBytes: int
      /// The most a response's headers may come to, in bytes.
      maxHeaderBytes: int
      /// What an `https` server's certificate is verified against; `None` is the system's
      /// certificate authorities.
      tls: option<Tls.ClientConfig> }

  /// 30 seconds, 5 redirects, 16 MB of body, 64 KB of headers, the system's authorities.
  let defaults : Config =
    { timeout = 30000
      maxRedirects = 5
      maxBodyBytes = 16777216
      maxHeaderBytes = 65536
      tls = None }

  // where a URL points
  type private Url = { secure: bool; host: string; port: int; target: string }

  // the URL's parts; no user name, and nothing in it that could end the request line
  let private parse (url: string) : result<Url, Error> =
    let lower = String.toLower url
    let (secure, rest) =
      if String.startsWith "https://" lower then (true, String.sub url 8 (String.length url - 8))
      else if String.startsWith "http://" lower then
        (false, String.sub url 7 (String.length url - 7))
      else (false, "")
    let rest =
      match String.indexOf "#" rest with
      | Some i -> String.sub rest 0 i
      | None -> rest
    let cut =
      match String.indexOf "/" rest, String.indexOf "?" rest with
      | Some a, Some b -> if a < b then a else b
      | Some a, None -> a
      | None, Some b -> b
      | None, None -> String.length rest
    let authority = String.sub rest 0 cut
    let after = String.sub rest cut (String.length rest - cut)
    let target = if String.startsWith "/" after then after else "/" + after
    let (host, portText) =
      if String.startsWith "[" authority then
        match String.indexOf "]" authority with
        | Some i ->
          let tail = String.sub authority (i + 1) (String.length authority - i - 1)
          (String.sub authority 1 (i - 1),
            if String.startsWith ":" tail then String.sub tail 1 (String.length tail - 1) else "")
        | None -> ("", "")
      else
        match String.lastIndexOf ":" authority with
        | Some i ->
          (String.sub authority 0 i, String.sub authority (i + 1) (String.length authority - i - 1))
        | None -> (authority, "")
    let port =
      if String.isEmpty portText then
        Some (if secure then 443 else 80)
      else
        String.parseInt portText
    let hostOk =
      not (String.isEmpty host) && List.forall (fun c ->
        Char.isLetterOrDigit c || c = '.' || c = '-' || c = ':' || c = '_') (String.chars host)
    let targetOk = List.forall (fun c -> c > ' ' && u32 c <> u32 127) (String.chars target)
    if String.isEmpty rest then
      Error (BadUrl "it must begin with http:// or https://")
    else if String.contains "@" authority then
      Error (BadUrl "a user name in it")
    else if not hostOk then
      Error (BadUrl "its host")
    else if not targetOk then
      Error (BadUrl "a space or a control character in it")
    else
      match port with
      | Some n when n > 0 && n < 65536 ->
        Ok { secure = secure; host = host; port = n; target = target }
      | _ -> Error (BadUrl "its port")

  // a connection to the URL's server, under TLS for https
  let private dial (config: Config) (u: Url) : Task<result<Conn, Error>> =
    task {
      let! connected = Tcp.connect u.host u.port
      match connected with
      | Error e -> return Error (Io e)
      | Ok stream ->
        if not u.secure then
          return Ok (Plain stream)
        else
          match config.tls with
          | Some trust ->
            let! s = Tls.connect trust u.host stream
            return s |> Result.map (fun x -> Tlsed x) |> Result.mapError (fun e -> Secure e)
          | None ->
            match Tls.Config.client () with
            | Error e ->
              dispose stream
              return Error (Secure e)
            | Ok trust ->
              use system = trust
              let! s = Tls.connect system u.host stream
              return s |> Result.map (fun x -> Tlsed x) |> Result.mapError (fun e -> Secure e)
    }

  // reads the response, passing over any 1xx before it
  let rec private response (c: Conn) (p: cptr) (buf: Buffer<u8>) (data: array<u8>) (limit: int) : Task<result<Response * bool, Error>> =
    task {
      let t = taking limit
      let! got = receive c p buf data t (fun () -> task { return () }) 0
      match got with
      | Whole rest ->
        let status = int (zs_http_status p)
        if status >= 100 && status < 200 && status <> 101 then
          zs_http_next p
          return! response c p buf rest limit
        else
          // with whether the connection has nothing more on it
          return Ok ({ status = status; headers = headersOf p; body = bodyOf t; stream = None },
            Array.length rest = 0)
      | Problem e -> return Error e
      | _ -> return Error Ended
    }

  // a connection to a server, with its parser: kept between a session's requests
  type private Kept = { id: int; key: string; conn: Conn; parser: Parser; buf: Buffer<u8> }

  // a connection in use: closed at the scope's end unless it was kept
  type private Held = { held: Kept; kept: ref<bool> }

  impl Dispose<Held> =
    let dispose (h: Held) =
      if not h.kept.Value then
        dispose h.held.conn
        dispose h.held.parser

  /// A client that keeps its connections: a request to a server it has asked before goes on
  /// the connection that's still open (`Client.session`, `Client.sendIn`). `use` closes them.
  type Session =
    { /// The limits and the trust of each request.
      config: Config
      /// The connections open and not in use.
      idle: ref<list<Kept>>
      /// How many connections it has made.
      made: ref<int> }

  /// `use` closes the session's connections.
  impl Dispose<Session> =
    let dispose (s: Session) =
      for k in s.idle.Value do
        dispose k.conn
        dispose k.parser
      s.idle.Value <- []

  /// A session with no connection yet.
  let session (config: Config) : Session = { config = config; idle = ref []; made = ref 0 }

  // the request on the connection, and its response; the connection goes back to the session
  // when it can carry another
  let private exchange (config: Config) (session: option<Session>) (method: Method) (u: Url) (headers: list<string * string>) (body: array<u8>) (k: Kept) : Task<result<Response, Error>> =
    task {
      use held = { held = k; kept = ref false }
      let standard = (u.secure && u.port = 443) || (not u.secure && u.port = 80)
      let name = if String.contains ":" u.host then $"[{u.host}]" else u.host
      let host = if standard then name else $"{name}:{u.port}"
      let sends = Array.length body > 0 || method = Post || method = Put || method = Patch
      let length = if sends then $"Content-Length: {Array.length body}\r\n" else ""
      let agent =
        if Option.isSome (Headers.tryFind "user-agent" headers) then
          ""
        else
          "User-Agent: zs-http\r\n"
      let ending = if Option.isSome session then "" else "Connection: close\r\n"
      let own = [ "host"; "content-length"; "connection"; "transfer-encoding" ]
      let top =
        $"{Method.name method} {u.target} HTTP/1.1\r\nHost: {host}\r\n{lines headers own}{agent}{length}{ending}\r\n"
      let! sent = writeConn k.conn (Array.append (String.bytes top) body.[0..])
      match sent with
      | Error e -> return Error e
      | Ok () ->
        let p = k.parser.handle
        if method = Head then zs_http_no_body p (i32 1)
        let! got = response k.conn p k.buf [||] config.maxBodyBytes
        match got, session with
        | Ok (r, clean), Some s when clean && zs_http_keep_alive p <> i32 0 && List.length s.idle.Value < 8 ->
          zs_http_next p
          held.kept.Value <- true
          s.idle.Value <- k :: s.idle.Value
          return Ok r
        | Ok (r, _), _ -> return Ok r
        | Error e, _ -> return Error e
    }

  // one request to one server: no redirect followed
  let private once (config: Config) (session: option<Session>) (method: Method) (u: Url) (headers: list<string * string>) (body: array<u8>) : Task<result<Response, Error>> =
    let key = $"{u.secure} {u.host} {u.port}"
    let fresh () : Task<result<Response, Error>> =
      task {
        let! dialed = dial config u
        match dialed with
        | Error e -> return Error e
        | Ok conn ->
          let made = zs_http_new (i32 1) (usize config.maxHeaderBytes)
          let raw: ptr<u8> = unsafe Ptr.ofCPtr made
          if Ptr.isNull raw then
            dispose conn
            return Error (Io "out of memory")
          else
            let id =
              match session with
              | Some s ->
                s.made.Value <- s.made.Value + 1
                s.made.Value
              | None -> 0
            let k =
              { id = id
                key = key
                conn = conn
                parser = { handle = made; freed = ref false }
                buf = Buffer.create 16384 (u8 0) }
            return! exchange config session method u headers body k
      }
    // a connection the session has open to this server, for a request that's safe to send
    // again: the server may have closed it meanwhile, and then the request goes on a new one
    let again = method = Get || method = Head || method = Put || method = Delete || method = Options
    let waiting =
      match session with
      | Some s when again -> List.tryFind (fun (k: Kept) -> k.key = key) s.idle.Value
      | _ -> None
    match session, waiting with
    | Some s, Some k ->
      task {
        s.idle.Value <- List.filter (fun (o: Kept) -> o.id <> k.id) s.idle.Value
        let! r = exchange config session method u headers body k
        match r with
        | Error (Io _) -> return! fresh ()
        | Error Ended -> return! fresh ()
        | Error (Secure _) -> return! fresh ()
        | other -> return other
      }
    | _ -> fresh ()

  // where a redirect's Location points, from the URL that gave it
  let private follow (from: Url) (location: string) : string =
    let lower = String.toLower location
    if String.startsWith "http://" lower || String.startsWith "https://" lower then
      location
    else
      let scheme = if from.secure then "https" else "http"
      let name = if String.contains ":" from.host then $"[{from.host}]" else from.host
      let path =
        if String.startsWith "/" location then
          location
        else
          // relative to the directory of the path it came from
          let before =
            match String.indexOf "?" from.target with
            | Some i -> String.sub from.target 0 i
            | None -> from.target
          match String.lastIndexOf "/" before with
          | Some i -> String.sub before 0 (i + 1) + location
          | None -> "/" + location
      $"{scheme}://{name}:{from.port}{path}"

  let rec private attempt (config: Config) (session: option<Session>) (method: Method) (url: string) (headers: list<string * string>) (body: array<u8>) (left: int) : Task<result<Response, Error>> =
    task {
      match parse url with
      | Error e -> return Error e
      | Ok u ->
        let! got = once config session method u headers body
        match got with
        | Ok r when r.status = 301 || r.status = 302 || r.status = 303 || r.status = 307 || r.status = 308 ->
          match Response.header "location" r with
          | None -> return Ok r
          | Some location ->
            if left = 0 then
              return Error TooManyRedirects
            else
              let next = follow u location
              // 307 and 308 repeat the request; the others ask for a GET of the new place
              let same = r.status = 307 || r.status = 308 || method = Get || method = Head
              // what was meant for one server isn't handed to another
              let moved =
                match parse next with
                | Ok n -> n.host <> u.host || n.port <> u.port || (u.secure && not n.secure)
                | Error _ -> true
              let secret (n: string) =
                let l = String.toLower n
                l = "authorization" || l = "cookie" || l = "proxy-authorization"
              let kept =
                if moved then List.filter (fun (n, _) -> not (secret n)) headers else headers
              if same then
                return! attempt config session method next kept body (left - 1)
              else
                let plain =
                  List.filter (fun (n, _) -> not (String.startsWith "content-" (String.toLower n))) kept
                return! attempt config session Get next plain [||] (left - 1)
        | other -> return other
    }

  let private sendWith (config: Config) (session: option<Session>) (method: Method) (url: string) (headers: list<string * string>) (body: array<u8>) : Task<result<Response, Error>> =
    task {
      let name = Method.name method
      if not (writable headers) || String.isEmpty name || not (List.forall Char.isUpper (String.chars name)) then
        return Error (Malformed "a header or the method can't be sent")
      else
        let! got =
          Task.timeout config.timeout (attempt config session method url headers body config.maxRedirects)
        match got with
        | Some r -> return r
        | None -> return Error TimedOut
    }

  /// Sends a request to the URL (`http://` or `https://`) on a connection of its own, and
  /// gives the response, redirects followed. A header that can't be sent as it is (a line end
  /// in it) is an `Error`.
  let send (config: Config) (method: Method) (url: string) (headers: list<string * string>) (body: array<u8>) : Task<result<Response, Error>> =
    sendWith config None method url headers body

  /// `send`, on a connection the session has open to the server when there's one, and
  /// leaving the connection open for the next request. A request that changes something and
  /// can't be told apart from its repeat (POST, PATCH) always goes on a new connection.
  let sendIn (s: Session) (method: Method) (url: string) (headers: list<string * string>) (body: array<u8>) : Task<result<Response, Error>> =
    sendWith s.config (Some s) method url headers body

  /// GETs the URL with `Client.defaults`.
  let get (url: string) : Task<result<Response, Error>> = send defaults Get url [] [||]

  /// POSTs the body to the URL with its `Content-Type` and `Client.defaults`.
  let post (url: string) (contentType: string) (body: array<u8>) : Task<result<Response, Error>> =
    send defaults Post url [ ("Content-Type", contentType) ] body
