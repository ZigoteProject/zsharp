// --no-heap (0012): a top-level value computed at startup into the heap
let table = Array.init 4 (fun i -> i * i)

let main () = table.[2]
