// Net.Unix (0024): a socket at a path, Tcp's reads and writes over it
let talk () : Task<result<string, string>> =
  task {
    let path = Path.combine (Directory.temp ()) "zs-unix-test.sock"
    match Unix.listen path with
    | Error e -> return Error e
    | Ok l ->
      use listener = l
      let server =
        task {
          let! c = Unix.accept listener
          match c with
          | Ok conn ->
            use s = conn
            let buf = Buffer.create 16 (u8 0)
            let! n = Tcp.read s buf
            let! _ = Tcp.write s buf (Result.defaultValue 0 n)
            return ()
          | Error _ -> return ()
        }
      let client =
        task {
          let! c = Unix.connect path
          match c with
          | Ok conn ->
            use s = conn
            let! _ = Tcp.write s (Buffer.ofSpan (String.bytes "ping")) 4
            let back = Buffer.create 16 (u8 0)
            let! n = Tcp.read s back
            return Ok (String.ofBytes back.[0 .. Result.defaultValue 0 n - 1])
          | Error e -> return Error e
        }
      let! (_, answer) = Task.both server client
      File.delete path |> ignore
      return answer
  }

let main () =
  println $"{Task.run (talk ())}"
  println $"{Task.run (Unix.connect "/nonexistent/zs.sock")}"
  0
