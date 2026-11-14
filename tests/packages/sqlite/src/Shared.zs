// what doesn't compile (tests/packages/sqlite.sh checks this file and expects the errors): a
// connection handed to another thread, a column's own bytes read outside `unsafe`, and
// SQLite's pointer taken out of a handle
open Sqlite

let count (db: Db) : Task<result<int, Error>> = Task.blocking (fun () -> Db.exec db "select 1" [])

let borrowed (row: Row) : int = Span.length (Row.textSpan row 0)

// SQLite's pointer isn't a program's to take from a handle: kept, it could be put back after
// the close, or a connection's put where a statement's goes
let kept (s: Statement) : option<cptr> = s.handle.compiled.Value

let swapped (db: Db) (s: Statement) : unit = s.handle.compiled.Value <- db.handle.connection.Value
