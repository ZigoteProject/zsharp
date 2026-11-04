// [<Section>] and [<Align>] (0014 item 12): on a function, with an alignment that isn't a power
// of two, on a value computed at startup, a constant in .noinit (never loaded), a string in a
// .noinit ref (a pointer into memory that's gone after a reset), and a name no linker takes
[<Section ".ramfunc">]
let tick () = 1

[<Align 24>]
let table = [| 1; 2 |]

[<Section ".tables">]
let squares = Array.init 4 (fun i -> i * i)

[<Section ".noinit">]
let lost = [| 1; 2; 3 |]

[<Section ".noinit">]
let name = ref "start"

[<Section "bad name">]
let counts = ref 0

let main () = tick () + table.[0] + squares.[1] + lost.[0] + String.length name.Value + counts.Value
