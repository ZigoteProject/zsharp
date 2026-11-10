// Unix.listen where something is at the path already: a file is an error and stays as it was, a
// live server's socket is an error (that server keeps it), and a socket no one listens on any
// more (an earlier run's) is replaced
let listens (path: string) =
  match Unix.listen path with
  | Ok listener ->
    use l = listener
    true
  | Error _ -> false

let main () =
  let file = Path.combine (Directory.temp ()) "zs-unix-path-test.txt"
  let sock = Path.combine (Directory.temp ()) "zs-unix-path-test.sock"
  File.writeAllText file "notes" |> ignore
  println $"a file: {listens file}, kept: {Result.defaultValue "" (File.readAllText file) = "notes"}"
  File.delete file |> ignore
  File.delete sock |> ignore
  match Unix.listen sock with
  | Ok listener ->
    use l = listener
    println $"a live server's socket: {listens sock}"
  | Error e -> println $"listen: {e}"
  // closed, its socket file is left
  println $"a socket no one listens on: {listens sock}"
  File.delete sock |> ignore
  0
