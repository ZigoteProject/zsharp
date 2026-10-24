// Finding the inputs: a directory becomes the .log files under it. It asks the Files effect,
// not the disk, so it runs as well against a test's in-memory one, and it reports what it found
// through Progress, which the caller shows or not.
open Io.Effects

effect Progress =
  abstract note : string -> unit

let private logsUnder (dir: string) =
  match Files.listRecursive dir with
  | Ok paths ->
    let logs = paths |> List.filter (fun p -> Path.getExtension p = ".log")
    Progress.note $"{dir}: {List.length logs} log files"
    logs
  | Error e ->
    Progress.note $"skipping {dir}: {e}"
    []

let files (inputs: list<string>) =
  inputs |> List.collect (fun input -> if Files.isDirectory input then logsUnder input else [ input ])
