# sqlite

SQLite for Z#: a database in a file or in memory, through SQLite's own code
([proposal 0032](../../docs/proposals/0032-first-party-packages.md)).

```fsharp
open Sqlite

let names (db: Db) : result<list<string>, Error> =
  Db.query db "select name from users where age > ? order by name" [ Int (i64 18) ] (fun row ->
    Row.text row 0)
```

- **Use:** `sqlite = { path = "…/packages/sqlite" }` under `[dependencies]`. `src/Sqlite.zs`'s
  doc comments are the reference (`zs doc`).
- **Values are bound, never formatted into SQL.** `use` closes a connection and a statement; one
  used after its close is `Error Closed`. A connection stays on the thread that opened it.
- **Targets:** those with an operating system.
- **The library:** SQLite 3.54.1's amalgamation in `c/`, unmodified; `c/VERSION` says where it's
  from and how to update it. Its options are set in `c/shim.c`.
- **License:** this package's code is the repository's (MIT). SQLite is in the public domain and
  asks for no notice.
