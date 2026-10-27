/// The build server (zs server): zs build hands its work to one that stays running, a Unix socket
/// in the cache (one per compiler and environment), which builds in its own process, in the
/// request's directory, and sends the output back. The first build starts it and builds on its
/// own; it ends after ten idle minutes, or with zs server stop. ZS_NO_SERVER=1 builds in the
/// process that's asked. A message is its length in bytes, a newline, then its fields separated
/// by NULs: a request is the directory and the arguments, a reply the exit code and the output.
// ponytail: no warm cache to keep yet (0007's would live here); the server spares a process start

extern dup : i32 -> i32
extern dup2 : i32 -> i32 -> i32
extern close : i32 -> i32
extern creat : cstr -> u32 -> i32
extern chdir : cstr -> i32
extern fflush : cptr -> i32
extern chmod : cstr -> u32 -> i32

let private nul = String.ofByte (u8 0)

/// The server's socket for this compiler and this environment: what a build depends on of each.
let socketPath () : string =
  let named = [ "PATH"; "HOME"; "XDG_CACHE_HOME"; "TMPDIR"; "CPATH"; "C_INCLUDE_PATH"; "LIBRARY_PATH"; "PKG_CONFIG_PATH"; "PKG_CONFIG_LIBDIR"; "CC"; "CFLAGS"; "LDFLAGS"; "LANG"; "LC_ALL" ]
  let values = List.map (fun (v: string) -> v + "=" + Option.defaultValue "" (Environment.getVariable v)) named
  // every ZS_ variable (Linux lists them in /proc)
  // ponytail: none on macOS (no /proc): a ZS_ variable changed there reuses the server; list
  // them through environ when that matters
  let ours =
    match File.readAllText "/proc/self/environ" with
    | Ok text -> List.sort (List.filter (fun (kv: string) -> String.startsWith "ZS_" kv) (String.split nul text))
    | Error _ -> []
  // the compiler: its binary's size and time
  let size = Result.defaultValue (i64 0) (File.size (Build.Tools.selfPath ()))
  let time =
    match File.modifiedAt (Build.Tools.selfPath ()) with
    | Ok t -> $"{t}"
    | Error _ -> ""
  let key = String.join nul (List.concat [ [ $"{size} {time}" ]; values; ours ])
  Path.getFullPath (Path.combine (Path.combine (Build.Tools.cacheRoot ()) "servers") (String.sub (Xxhash.hex (String.bytes key)) 0 16 + ".sock"))

// ---- messages

let private sendFields (s: TcpStream) (fields: list<string>) : Task<result<unit, string>> =
  let body = String.join nul fields
  Tcp.writeText s $"{String.length body}\n{body}"

// a message's fields, read to its length (None when the connection ends first)
let private readFields (s: TcpStream) : Task<option<list<string>>> =
  let buf = Buffer.create 65536 (u8 0)
  let got = Buffer.empty
  let append (k: int) =
    for j in 0 .. k - 1 do
      Buffer.push buf.[j] got
  // the body once the length's line and that many bytes have come
  let complete () : option<string> =
    let mutable newline = -1
    for i in 0 .. Buffer.length got - 1 do
      if newline < 0 && got.[i] = u8 10 then
        newline <- i
    if newline < 0 then
      None
    else
      let bytes = Buffer.toArray got
      let len : option<int> = Int.parse (String.ofBytes (Array.sub bytes 0 newline))
      match len with
      | Some n when Array.length bytes - newline - 1 >= n -> Some(String.ofBytes (Array.sub bytes (newline + 1) n))
      | _ -> None
  let rec go () : Task<option<list<string>>> =
    task {
      match complete () with
      | Some body -> return Some(String.split nul body)
      | None ->
        let! got = Tcp.read s buf
        match got with
        | Ok k when k > 0 ->
          append k
          return! go ()
        | _ -> return None
    }
  go ()

// ---- running a command with its output captured

// runs f with standard output and standard error into the two files, in the directory
let private captured (dir: string) (out: string) (err: string) (f: unit -> int) : int =
  let none = Ptr.toCPtr (Ptr.null () : ptr<u8>)
  let here = Environment.currentDirectory ()
  fflush none |> ignore
  let savedOut = dup 1
  let savedErr = dup 2
  let o = creat out (u32 384)
  let e = creat err (u32 384)
  dup2 o 1 |> ignore
  dup2 e 2 |> ignore
  close o |> ignore
  close e |> ignore
  chdir dir |> ignore
  let code = f ()
  fflush none |> ignore
  chdir here |> ignore
  dup2 savedOut 1 |> ignore
  dup2 savedErr 2 |> ignore
  close savedOut |> ignore
  close savedErr |> ignore
  code

/// The server at the socket: unless another answers there, it listens until stopped or ten
/// minutes pass with no request, running each request with `run`. A request's tasks finish before
/// its build runs, so the build's own tasks (the processes it starts) have the loop to themselves.
let serve (path: string) (run: list<string> -> int) : int =
  let dir = Path.getDirectoryName path
  Build.Tools.makeDirectory dir
  // whoever reaches the socket runs zs commands as this user, so its directory is this user's
  // alone (made with the umask's permissions, it's open to every user under a umask of 0)
  let mine = chmod dir (u32 448) = 0
  // another server started first (two builds found none): it answers, this one ends
  let ping =
    task {
      let! got = Unix.connect path
      match got with
      | Ok s ->
        use probe = s
        let! sent = sendFields probe [ ""; "ping" ]
        return Result.isOk sent
      | Error _ -> return false
    }
  if not mine then
    eprintln $"zs server: cannot make {dir} private"
    1
  else if Task.run ping then
    0
  else
    File.delete path |> ignore
    match Unix.listen path with
    | Error e ->
      eprintln $"zs server: {e}"
      1
    | Ok listener ->
      use l = listener
      // beside its socket: another environment's server shares the directory
      let out = path + ".out"
      let err = path + ".err"
      let mutable going = true
      while going do
        match Task.run (Task.timeout 600000 (Unix.accept l)) with
        | Some(Ok conn) ->
          use c = conn
          match Task.run (readFields c) with
          | Some [ _; "stop" ] -> going <- false
          | Some [ _; "ping" ] -> ()
          | Some(cwd :: argv) ->
            let code = captured cwd out err (fun () -> run argv)
            let text (p: string) = Result.defaultValue "" (File.readAllText p)
            Task.run (sendFields c [ $"{code}"; text out; text err ]) |> ignore
            File.delete out |> ignore
            File.delete err |> ignore
          | _ -> ()
        | Some(Error _) -> ()
        | None -> going <- false
      File.delete path |> ignore
      0

/// Asks the build server to run the arguments: its exit code, with its output written here; None
/// when none answers (one is started for the next build, apart from this process, with this
/// environment).
let viaServer (args: list<string>) : option<int> =
  let path = socketPath ()
  let reply =
    Task.run (
      task {
        let! got = Unix.connect path
        match got with
        | Ok s ->
          use conn = s
          let! sent = sendFields conn (Environment.currentDirectory () :: args)
          if Result.isOk sent then
            let! fields = readFields conn
            return fields
          else
            return None
        | Error _ -> return None
      })
  match reply with
  | Some [ code; out; err ] ->
    print out
    let e = IO.Writer.ofFd 2
    IO.Writer.writeText e err |> ignore
    IO.Writer.flush e |> ignore
    Int.parse code
  | _ ->
    if args <> [ "stop" ] then
      // its own streams, so a caller reading this one's output isn't kept waiting
      let s : Diagnostics.ProcessStart = { program = Build.Tools.selfPath (); args = [ "server"; path ]; stdin = Diagnostics.Null; stdout = Diagnostics.Null; stderr = Diagnostics.Null }
      match Diagnostics.Process.start s with
      | Ok p -> Dispose.dispose p
      | Error _ -> ()
    None
