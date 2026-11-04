// [<Section>] and [<Align>] on top-level values (0014 item 12): a constant table, a Buffer or a
// ref whose storage is in the image, in the named section and so aligned, with no startup code;
// the program uses them as any table, Buffer or ref (a push past a placed Buffer's room moves it
// to the heap and leaves the storage)
[<Section ".tables"; Align 64>]
let sine = [| 0; 3; 6; 9 |]

[<Align 32>]
let frame = Buffer.create 8 (u8 0)

[<Section ".noinit">]
let boots = ref 0

[<Section ".noinit">]
let log = Buffer.create 4 "-"

[<Section ".tables">]
let primes = [ 2; 3; 5; 7 ]

let main () =
  frame.[1] <- u8 7
  for i in 0 .. 2 do
    Buffer.push (u8 9) frame
  boots.Value <- boots.Value + 1
  log.[2] <- "x"
  println $"{sine.[2]} {Array.sum sine} {frame.[1]} {frame.[9]} {Buffer.length frame} {boots.Value} {String.concat (Array.toList (Buffer.toArray log))} {List.sum primes}"
  0
