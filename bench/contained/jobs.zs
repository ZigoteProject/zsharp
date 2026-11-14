// Contained jobs (proposal 0035), measured: what a job costs when it does nothing, when it
// allocates, and when it fails; and what its result's copy out of its memory costs, a megabyte
// of small objects at a time. Usage: jobs [count] (a million by default); bench/contained/run.sh
// runs it.
type Row = { name: string; next: int }

let line = "a row of the table, which is seventy-two bytes long with its eight to spare."

// n rows, a megabyte in 8,192 of them: a list cell with its record (40 bytes) and a string of
// 64 (88 with its header), each made with nothing else
let rows (n: int) : list<Row> =
  List.init n (fun i -> { name = String.sub line (i % 8) 64; next = i })

// the best of three runs
let each (name: string) (n: int) (work: unit -> int) =
  let mutable best = 0.0
  let mutable r = 0
  for k in 1 .. 3 do
    let start = Runtime.ticks ()
    r <- work ()
    let ns = float (Runtime.ticks () - start) / float n
    if k = 1 || ns < best then best <- ns
  println $"{name}: {best:F0} ns each ({r})"

let main () =
  let n =
    match Environment.args () with
    | s :: _ -> Option.defaultValue 1000000 (String.parseInt s)
    | _ -> 1000000
  // the call alone: a closure made and called
  each "a function called" n (fun () ->
    let mutable sum = 0
    for i in 1 .. n do
      let f = fun () -> i
      sum <- sum + f ()
    sum)
  each "a job that does nothing" n (fun () ->
    let mutable sum = 0
    for i in 1 .. n do
      sum <- sum + Result.defaultValue 0 (Contained.run (fun () -> i))
    sum)
  each "a job that makes a list of ten" n (fun () ->
    let mutable sum = 0
    for i in 1 .. n do
      sum <- sum + Result.defaultValue 0 (Contained.run (fun () ->
          List.sum (List.init 10 (fun k -> k + i))))
    sum)
  each "a job in a job" n (fun () ->
    let mutable sum = 0
    for i in 1 .. n do
      sum <- sum + Result.defaultValue 0 (Contained.run (fun () ->
          Result.defaultValue 0 (Contained.run (fun () -> i))))
    sum)
  // a megabyte made in a job and dropped there, and one copied out as the job's result
  let megabytes = max 1 (n / 2000)
  each "a megabyte made and dropped, not in a job" megabytes (fun () ->
    let mutable sum = 0
    for _ in 1 .. megabytes do
      sum <- sum + List.length (rows 8192)
    sum)
  each "a megabyte made in a job and left in it" megabytes (fun () ->
    let mutable sum = 0
    for _ in 1 .. megabytes do
      sum <- sum + Result.defaultValue 0 (Contained.run (fun () -> List.length (rows 8192)))
    sum)
  each "a megabyte made in a job, returned and dropped" megabytes (fun () ->
    let mutable sum = 0
    for _ in 1 .. megabytes do
      sum <- sum + List.length (Result.defaultValue [] (Contained.run (fun () -> rows 8192)))
    sum)
  // what the caller shared with the job, returned: not copied
  let table = rows 8192
  each "a megabyte of the caller's returned" n (fun () ->
    let mutable sum = 0
    for _ in 1 .. n do
      match Contained.run (fun () -> table) with
      | Ok t -> if List.isEmpty t then sum <- sum + 1
      | Error _ -> ()
    sum)
  // a job that fails (its panic's line goes to standard error: send that to /dev/null)
  let failures = max 1 (n / 100)
  each "a job that panics" failures (fun () ->
    let mutable failed = 0
    for i in 1 .. failures do
      match Contained.run (fun () -> if i > 0 then panic "measured" else 0) with
      | Ok _ -> ()
      | Error _ -> failed <- failed + 1
    failed)
  0
