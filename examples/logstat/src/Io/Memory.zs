// An in-memory terminal and disk, for tests: run the whole program with no stdout and no files.
open Effects

// what reached the terminal
type Screen = { out: list<string>; err: list<string> }

// runs app with the terminal captured: its result and the screen
let terminal (app: unit -> 'a) =
  let mutable out = []
  let mutable err = []
  let result =
    handle app () with
    | Terminal.out s, k ->
      out <- s :: out
      k ()
    | Terminal.err s, k ->
      err <- s :: err
      k ()
  (result, { out = List.rev out; err = List.rev err })

// runs app against a disk of path -> contents
let files (disk: Map<string, string>) (app: unit -> 'a) =
  let under dir = Map.keys disk |> List.filter (String.startsWith (dir + "/"))
  let read path =
    match Map.tryFind path disk with
    | Some text -> Ok (path, text)
    | None -> Error $"cannot open {path}: No such file or directory"
  handle app () with
  | Files.isDirectory p, k -> k (under p <> [])
  | Files.listRecursive p, k -> k (Ok (under p))
  | Files.readAll (_, paths), k -> k (List.map read paths)
