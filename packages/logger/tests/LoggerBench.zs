open Testing
open Logger

let private sinkless = create []
let private (mem, _) = Sink.memory 2000 Debug
let private inMemory = create [ mem ]
let private (full, _) = Sink.memory 2000 Debug
let private filled =
  let l = create [ full ]
  for i in 1 .. 4000 do
    write l Debug "x" $"{i}" []
  l

[<Tests>]
let benches =
  testList "bench" [
    bench "write, no sink takes it" (fun () ->
      for _ in 1 .. 1000 do
        write sinkless Debug "aacp" "received" [ ("bytes", "04 00 04 00") ])
    bench "write to memory, empty" (fun () ->
      for _ in 1 .. 1000 do
        write inMemory Debug "aacp" "received" [ ("bytes", "04 00 04 00") ])
    bench "write to memory, full" (fun () ->
      for _ in 1 .. 1000 do
        write filled Debug "aacp" "received" [ ("bytes", "04 00 04 00") ])
    bench "format text" (fun () ->
      let r =
        { time = DateTime.unixEpoch
          level = Info
          source = "aacp"
          message = "received"
          fields = [ ("bytes", "04 00 04 00 06 00 00 01") ] }
      for _ in 1 .. 1000 do
        Format.text r |> ignore)
    bench "effect into a logger" (fun () ->
      into inMemory "core" (fun () ->
        for _ in 1 .. 1000 do
          debug "a step"))
  ]
