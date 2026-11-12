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
    // longer than one read, and than two
    let long = Array.init 200001 (fun i -> u8 (i * 7 % 251))
    File.writeAllBytes path long |> ignore
    match File.readAllBytes path with
    | Ok back ->
      // byte by byte: `=` on two lists this long overflows the stack in a debug build
      let mutable same = Array.length back = Array.length long
      for i in 0 .. Array.length back - 1 do
        if back.[i] <> long.[i] then same <- false
      println $"{Array.length back} {same} {back.[65536]} {back.[200000]}"
    | Error e -> println e
    File.delete path |> ignore
  0
