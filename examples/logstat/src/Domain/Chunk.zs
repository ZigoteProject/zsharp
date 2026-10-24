// Counting a file in pieces. A chunk is the whole lines from `start` up to `stop` of a file's
// text: cutting a file copies nothing (chunks share the text) and reads nothing (chunks number
// their own lines; Stats' + puts the numbers right).
open Stats

type Chunk = { file: string; text: string; start: int; stop: int }

// a file cut into chunks of about `size` bytes, each ending at a line's end, so one big file
// spreads over every core as well as many small ones do
let cut (size: int) (input: string * string) =
  let (file, text) = input
  let len = String.length text
  let rec go start acc =
    if start >= len then List.rev acc
    else
      let nl = if start + size >= len then -1 else String.indexOfFrom text "\n" (start + size)
      let stop = if nl < 0 then len else nl + 1
      go stop ({ file = file; text = text; start = start; stop = stop } :: acc)
  go 0 []

// line `n` of a chunk added to s: blank lines skipped, bad ones kept with the reason
let private addLine (file: string) (s: Stats) (n: int) (line: string) =
  if line = "" then s
  else
    match Throw.catch (fun () -> Entry.parse line) with
    | Ok e -> addEntry s e
    | Error why -> addBad s { file = file; line = n; why = why }

// A chunk counted, line by line, with no list of its lines. Each line's Throw is handled
// here, so this runs on other threads effect-free. It copies its slice first: every chunk of a
// file shares the text, and each use of a shared object is an atomic count on one cache line
// that all their threads fight over; the copy is this thread's alone.
let count (c: Chunk) : Stats =
  let text = String.sub c.text c.start (c.stop - c.start)
  let len = String.length text
  // line n starts at pos
  let rec go pos n s =
    if pos >= len then { s with seen = Map.ofList [ (c.file, n - 1) ] }
    else
      let nl = String.indexOfFrom text "\n" pos
      let stop = if nl < 0 then len else nl
      go (stop + 1) (n + 1) (addLine c.file s n (String.trimEnd (String.sub text pos (stop - pos))))
  go 0 1 Add.zero

// a whole file as one chunk
let countFile (input: string * string) =
  let (file, text) = input
  count { file = file; text = text; start = 0; stop = String.length text }
