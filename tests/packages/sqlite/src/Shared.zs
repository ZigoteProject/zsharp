// what doesn't compile (tests/packages/sqlite.sh checks this file and expects the errors): a
// connection handed to another thread, and a column's own bytes read outside `unsafe`
open Sqlite

let count (db: Db) : Task<result<int, Error>> = Task.blocking (fun () -> Db.exec db "select 1" [])

let borrowed (row: Row) : int = Span.length (Row.textSpan row 0)
