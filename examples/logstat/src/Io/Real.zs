// The real terminal and disk. One handler per effect, so they compose with Io.Memory's: a fake
// disk with the real terminal, say.
open Effects

let terminal (app: unit -> 'a) =
  handle app () with
  | Terminal.out s, k ->
    println s
    k ()
  | Terminal.err s, k ->
    eprintln s
    k ()

// one file, given up on after timeoutMs: a stuck mount can't hang the run
let private read (timeoutMs: int) (file: string) =
  task {
    let! r = Task.timeout timeoutMs (File.readAllTextAsync file)
    match r with
    | Some (Ok text) -> return Ok (file, text)
    | Some (Error e) -> return Error e
    | None -> return Error $"{file}: no data after {timeoutMs} ms"
  }

let files (app: unit -> 'a) =
  handle app () with
  | Files.isDirectory p, k -> k (Directory.exists p)
  | Files.listRecursive p, k -> k (Directory.listRecursive p |> Result.map (List.map (Path.combine p)))
  | Files.readAll (ms, paths), k -> k (Task.run (Task.all (List.map (read ms) paths)))
