// [<Section>] and [<Align>] (0014 item 12): on a function, with an alignment that isn't a power
// of two, and on a value computed at startup
[<Section ".ramfunc">]
let tick () = 1

[<Align 24>]
let table = [| 1; 2 |]

[<Section ".tables">]
let squares = Array.init 4 (fun i -> i * i)

let main () = tick () + table.[0] + squares.[1]
