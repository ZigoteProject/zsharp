/// TLS (proposal 0032) over a `Net.TcpStream`, through Mbed TLS (`c/mbedtls`): TLS 1.2 and
/// 1.3, nothing older. A client verifies the server's certificate and its name, always: there
/// is no setting that doesn't. `Tls.connect` and `Tls.accept` give a `TlsStream`, read and
/// written as `Tcp`'s streams are, each wait a task's. A configuration and a stream stay on the
/// thread that made them.

extern strlen : cptr -> usize
extern zs_tls_error_text : i32 -> cstr
extern zs_tls_last_error : unit -> i32
extern zs_tls_client_config : span<u8> -> cptr
extern zs_tls_server_config : span<u8> -> span<u8> -> cptr
extern zs_tls_config_release : cptr -> unit
extern zs_tls_self_signed : cstr -> ptr<u8> -> ptr<u8> -> usize -> i32
extern zs_tls_conn_new : cptr -> cstr -> cptr
extern zs_tls_conn_free : cptr -> unit
extern zs_tls_feed : cptr -> span<u8> -> i32
extern zs_tls_out : cptr -> ptr<u8>
extern zs_tls_out_length : cptr -> usize
extern zs_tls_out_done : cptr -> unit
extern zs_tls_handshake : cptr -> i32
extern zs_tls_read : cptr -> usize -> i32
extern zs_tls_plain : cptr -> ptr<u8>
extern zs_tls_write : cptr -> span<u8> -> i32
extern zs_tls_close_notify : cptr -> i32
extern zs_tls_conn_error : cptr -> cstr
extern zs_tls_conn_error_code : cptr -> i32

/// Why a call failed.
type Error =
  /// The stream or the configuration was closed already.
  | Closed
  /// The connection ended without the peer's notice that it was done: what was read may have
  /// been cut short.
  | Truncated
  /// The socket failed, with the system's message.
  | Io of message: string
  /// TLS failed (a certificate that doesn't verify, a handshake refused, a record damaged),
  /// with Mbed TLS's code and its message.
  | Failed of code: int * message: string

// Mbed TLS's pointer to a configuration and to a connection, until each is released. A private
// type each, so the field is private too: a program can't keep a pointer past its release and
// put it back, nor give a stream a configuration's, which Mbed TLS would read as a connection
type private Configured = { configured: ref<option<cptr>> }

type private Connected = { connected: ref<option<cptr>> }

/// What a client asks of a server: the certificates it trusts. `use` releases it.
type ClientConfig =
  { /// Mbed TLS's configuration with the roots, until it's released.
    roots: Configured }

/// What a server presents: its certificate and key. `use` releases it.
type ServerConfig =
  { /// Mbed TLS's configuration with the certificate and key, until it's released.
    identity: Configured }

/// A connection under TLS (`Tls.connect`, `Tls.accept`). `use` closes it and its socket;
/// `Tls.close` first tells the peer.
type TlsStream =
  { /// The socket under it.
    tcp: TcpStream
    /// Mbed TLS's connection, until it's closed.
    handle: Connected
    /// Where bytes from the socket are read before they're decrypted.
    scratch: Buffer<u8> }

// releases a configuration's handle once
let private release (cell: ref<option<cptr>>) : unit =
  match cell.Value with
  | Some p ->
    cell.Value <- None
    zs_tls_config_release p
  | None -> ()

/// `use` releases the configuration; connections made from it go on.
impl Dispose<ClientConfig> =
  let dispose (c: ClientConfig) = release c.roots.configured

/// `use` releases the configuration; connections made from it go on.
impl Dispose<ServerConfig> =
  let dispose (c: ServerConfig) = release c.identity.configured

/// `use` closes the connection and its socket, without a notice to the peer (`Tls.close`
/// sends one).
impl Dispose<TlsStream> =
  let dispose (s: TlsStream) =
    match s.handle.connected.Value with
    | Some p ->
      s.handle.connected.Value <- None
      zs_tls_conn_free p
      dispose s.tcp
    | None -> ()

// whether a handle from C is NULL
let private isNull (p: cptr) : bool =
  let raw: ptr<u8> = unsafe Ptr.ofCPtr p
  Ptr.isNull raw

// the error for an Mbed TLS code
let private failure (code: i32) : Error = Failed (int code, String.ofCStr (zs_tls_error_text code))

/// Functions on `Error`.
module Error =
  /// The error as a line of text.
  let message (e: Error) : string =
    match e with
    | Closed -> "closed"
    | Truncated -> "the connection ended without a close notice"
    | Io m -> m
    | Failed (code, m) -> $"{m} ({code})"

/// Configurations: what a client trusts and what a server presents.
module Config =
  // a configuration's handle, or why there's none
  let private made (p: cptr) : result<ref<option<cptr>>, Error> =
    if isNull p then Error (failure (zs_tls_last_error ())) else Ok (ref (Some p))

  /// A client's configuration that trusts the system's certificate authorities (`SSL_CERT_FILE`
  /// names another bundle, as for OpenSSL).
  let client () : result<ClientConfig, Error> =
    made (zs_tls_client_config (String.bytes ""))
    |> Result.map (fun h -> { roots = { configured = h } })

  /// A client's configuration that trusts only the certificates in `pem` (PEM text): a private
  /// authority's, or one server's own.
  let clientTrusting (pem: string) : result<ClientConfig, Error> =
    if String.isEmpty pem then
      Error (Failed (0, "no certificate in the text"))
    else
      made (zs_tls_client_config (String.bytes pem))
      |> Result.map (fun h -> { roots = { configured = h } })

  /// A server's configuration from PEM text: its certificate, followed by the chain above it,
  /// and its private key.
  let server (certificate: string) (key: string) : result<ServerConfig, Error> =
    made (zs_tls_server_config (String.bytes certificate) (String.bytes key))
    |> Result.map (fun h -> { identity = { configured = h } })

  /// A server's configuration from two PEM files.
  let ofFiles (certificate: string) (key: string) : result<ServerConfig, Error> =
    match File.readAllText certificate, File.readAllText key with
    | Ok c, Ok k -> server c k
    | Error e, _ -> Error (Io $"{certificate}: {e}")
    | _, Error e -> Error (Io $"{key}: {e}")

  /// A new key and a certificate for `host` signed with it, valid for a year, as PEM text: the
  /// certificate, then the key. For a test or a development server: a client trusts it with
  /// `clientTrusting`, and nothing else does.
  let selfSigned (host: string) : result<string * string, Error> =
    let plain (c: char) = Char.isLetterOrDigit c || c = '.' || c = '-'
    if String.isEmpty host || String.length host > 253 || not (List.forall plain (String.chars host)) then
      Error (Failed (0, "not a host name"))
    else
      let size = 4096
      let certificate: ptr<u8> = unsafe Ptr.alloc size
      let key: ptr<u8> = unsafe Ptr.alloc size
      let code = zs_tls_self_signed host certificate key (usize size)
      let made =
        if code = i32 0 then
          let text (p: ptr<u8>) =
            String.ofBytes (unsafe (Span.ofPtr p (int (strlen (Ptr.toCPtr p)))))
          Ok (text certificate, text key)
        else
          Error (failure code)
      unsafe Ptr.free certificate
      unsafe Ptr.free key
      made

// the connection's error after a step said there was one
let private failed (p: cptr) : Error =
  Failed (int (zs_tls_conn_error_code p), String.ofCStr (zs_tls_conn_error p))

// sends the socket what the connection has for the peer
let private flush (s: TlsStream) (p: cptr) : Task<result<unit, Error>> =
  task {
    let n = int (zs_tls_out_length p)
    if n = 0 then
      return Ok ()
    else
      let data = Buffer.ofSpan (unsafe (Span.ofPtr (zs_tls_out p) n))
      zs_tls_out_done p
      let! sent = Tcp.write s.tcp data n
      return Result.mapError (fun e -> Io e) sent
  }

// Runs `step` on the connection until it has a result: a count of bytes (0 or more), with the
// socket written and read as the step asks. `atEnd` is the result when the peer has said it's
// done. The handle is looked up again after each wait, since the stream may be closed meanwhile.
let rec private drive (s: TlsStream) (atEnd: result<int, Error>) (step: cptr -> i32) : Task<result<int, Error>> =
  task {
    match s.handle.connected.Value with
    | None -> return Error Closed
    | Some p ->
      let r = int (step p)
      // a failed step may have an alert for the peer: what it says comes first
      let problem = if r = -4 then Some (failed p) else None
      let! sent = flush s p
      match problem, sent with
      | Some e, _ -> return Error e
      | None, Error e -> return Error e
      | None, Ok () ->
        if r >= 0 then
          return Ok r
        else if r = -3 then
          return atEnd
        else if r = -2 then
          return! drive s atEnd step
        else
          let! got = Tcp.read s.tcp s.scratch
          match got, s.handle.connected.Value with
          | _, None -> return Error Closed
          | Error e, _ -> return Error (Io e)
          | Ok 0, _ -> return Error Truncated
          | Ok n, Some again ->
            if zs_tls_feed again s.scratch.[0 .. n - 1] <> i32 0 then
              return Error (Failed (0, "out of memory"))
            else
              return! drive s atEnd step
  }

// a stream whose handshake isn't done: disposing it closes the stream unless it was kept
type private Starting = { stream: TlsStream; kept: ref<bool> }

impl Dispose<Starting> =
  let dispose (s: Starting) =
    if not s.kept.Value then dispose s.stream

// a stream over the socket for a new connection of the configuration's, the handshake done;
// the socket is closed on a failure
let private start (config: ref<option<cptr>>) (host: string) (stream: TcpStream) : Task<result<TlsStream, Error>> =
  task {
    match config.Value with
    | None ->
      dispose stream
      return Error Closed
    | Some c ->
      let p = zs_tls_conn_new c host
      if isNull p then
        dispose stream
        return Error (failure (zs_tls_last_error ()))
      else
        let s =
          { tcp = stream
            handle = { connected = ref (Some p) }
            scratch = Buffer.create 16384 (u8 0) }
        // closed unless the handshake ends well: on a failure, and when the task is cancelled
        use starting = { stream = s; kept = ref false }
        let! shaken = drive s (Error Truncated) (fun c -> zs_tls_handshake c)
        match shaken with
        | Ok _ ->
          starting.kept.Value <- true
          return Ok s
        | Error e -> return Error e
  }

/// TLS as a client over a connected socket: the handshake, with the server's certificate
/// verified against the configuration's roots and for `host`. The stream owns the socket from
/// here, and closes it on a failure.
let connect (config: ClientConfig) (host: string) (stream: TcpStream) : Task<result<TlsStream, Error>> =
  if String.isEmpty host || String.contains "\0" host then
    task {
      dispose stream
      return Error (Failed (0, "not a host name"))
    }
  else
    start config.roots.configured host stream

/// TLS as a server over an accepted socket: the handshake. The stream owns the socket from
/// here, and closes it on a failure.
let accept (config: ServerConfig) (stream: TcpStream) : Task<result<TlsStream, Error>> =
  start config.identity.configured "" stream

/// Reads what has arrived into `buf`, waiting for at least one byte: how many, or 0 when the
/// peer has closed its side. A connection that ends without that notice is `Truncated`.
let read (s: TlsStream) (buf: Buffer<u8>) : Task<result<int, Error>> =
  task {
    let want = Buffer.length buf
    if want = 0 then
      return Ok 0
    else
      let! got = drive s (Ok 0) (fun p -> zs_tls_read p (usize want))
      match got, s.handle.connected.Value with
      | Ok n, Some p when n > 0 ->
        let plain = Buffer.ofSpan (unsafe (Span.ofPtr (zs_tls_plain p) n))
        Buffer.blit plain 0 buf 0 n
        return Ok n
      | Ok _, None -> return Error Closed
      | other, _ -> return other
  }

/// Writes the first `n` bytes of `buf`, all of them.
let write (s: TlsStream) (buf: Buffer<u8>) (n: int) : Task<result<unit, Error>> =
  let rec from (off: int) : Task<result<unit, Error>> =
    task {
      if off >= n then
        return Ok ()
      else
        let! took = drive s (Error Truncated) (fun p -> zs_tls_write p buf.[off .. n - 1])
        match took with
        | Ok k -> return! from (off + k)
        | Error e -> return Error e
    }
  if n < 0 || n > Buffer.length buf then panic "Tls.write: more than the buffer holds"
  from 0

/// Writes the text's bytes.
let writeText (s: TlsStream) (text: string) : Task<result<unit, Error>> =
  let data = Buffer.ofSpan (String.bytes text)
  write s data (Buffer.length data)

/// Tells the peer no more is coming, then closes the connection and its socket.
let close (s: TlsStream) : Task<unit> =
  task {
    let! _ = drive s (Ok 0) (fun c -> zs_tls_close_notify c)
    dispose s
  }
