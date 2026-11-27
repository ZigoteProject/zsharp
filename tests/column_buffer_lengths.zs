// A ColumnBuffer's columns are one length (0037): truncated past it, every column stays; and one
// column pushed to alone through b.f is found by whatever then takes every column (set,
// truncate, clear, pop, a row written, for, push), a panic that says so, not a row that mixes two
[<Derive(Columns)>]
type P = { a: int; s: string }

// a ColumnBuffer one column of which is longer than the others
let lone () =
  let b = ColumnBuffer.create 3 { a = 1; s = "x" }
  Buffer.push 9 b.a
  b

// whether doing f to such a one panics (in a contained job, so the program goes on)
let finds (name: string) (f: share<unit -> unit>) =
  match Contained.run f with
  | Ok() -> println $"{name}: not found"
  | Error _ -> println $"{name}: found"

let main () =
  let b = ColumnBuffer.create 3 { a = 1; s = "x" }
  ColumnBuffer.truncate 10 b
  println $"{ColumnBuffer.length b} {Buffer.length b.a} {Buffer.length b.s}"
  finds "set" (fun () -> ColumnBuffer.set (lone ()) 0 { a = 2; s = "y" })
  finds "truncate" (fun () -> ColumnBuffer.truncate 2 (lone ()))
  finds "clear" (fun () -> ColumnBuffer.clear (lone ()))
  finds "pop" (fun () -> ColumnBuffer.pop (lone ()) |> ignore)
  finds "a row written" (fun () -> (lone ()).[0] <- { a = 2; s = "y" })
  finds "for" (fun () ->
    for p in lone () do
      ignore p)
  Buffer.push "alone" b.s
  println $"{Buffer.length b.a} {Buffer.length b.s}"
  ColumnBuffer.push { a = 2; s = "y" } b
  println "not reached"
