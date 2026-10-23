// File.writeAllBytes and readAllBytes keep every byte as it is, not just valid UTF-8 (0024).
let main () =
  let bytes = Array.init 512 (fun i -> u8 (i % 256))
  match File.createTemp "zs-bytes-" with
  | Error e -> panic e
  | Ok path ->
    File.writeAllBytes path bytes |> ignore
    match File.readAllBytes path with
    | Ok back ->
      println $"{Array.length back} {Array.toList back = Array.toList bytes} {back.[200]} {back.[511]}"
    | Error e -> println e
    println $"{File.size path}"
    File.delete path |> ignore
  0
