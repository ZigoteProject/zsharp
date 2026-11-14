/// SQLite (proposal 0032): a database in a file or in memory, through SQLite's own code
/// (`c/sqlite3.c`, the amalgamation). A `Db` is a connection and a `Statement` a compiled
/// query; `use` closes each. Values reach SQL only by being bound to a statement's `?`
/// parameters, never by being written into its text. A connection and its statements stay on
/// the thread that opened them: another thread opens its own.

/// SQLite's C API as `sqlite3.h` declares it, for what the functions below don't offer. A
/// handle from `Db` or `Statement` isn't reachable here: these are for a connection of one's
/// own, in `unsafe` code that keeps SQLite's rules itself.
module Native = import c "sqlite3.h"

extern zs_sqlite_open : cstr -> i32 -> i32 -> ptr<cptr> -> i32
extern zs_sqlite_prepare : cptr -> span<u8> -> ptr<cptr> -> i32
extern zs_sqlite_bind_text : cptr -> i32 -> span<u8> -> i32
extern zs_sqlite_bind_blob : cptr -> i32 -> span<u8> -> i32

/// Why a call failed.
type Error =
  /// Another connection holds the lock, and the busy timeout passed.
  | Busy of message: string
  /// A constraint (unique, not null, a foreign key, a check) refused the change.
  | Constraint of message: string
  /// The connection or the statement was closed already.
  | Closed
  /// Any other failure, with SQLite's extended result code and its message.
  | Other of code: int * message: string

/// A value bound to a parameter or read from a column: SQLite's five storage classes.
type Value =
  /// NULL.
  | Null
  /// A 64-bit integer.
  | Int of i64
  /// A 64-bit float.
  | Real of float
  /// Text, as UTF-8.
  | Text of string
  /// Bytes.
  | Blob of array<u8>

// SQLite's pointer to a connection and to a statement, until each is closed. A private type
// each, so the field is private too: a program can't keep a pointer past its close and put it
// back, nor give a statement a connection's, which SQLite would follow into freed memory
type private Connection = { connection: ref<option<cptr>> }

type private Compiled = { compiled: ref<option<cptr>> }

/// A connection to a database (`Db.connect`); `use` closes it.
type Db =
  { /// SQLite's connection, until it's closed.
    handle: Connection }

/// A compiled statement (`Db.prepare`); `use` finalizes it.
type Statement =
  { /// The connection it was prepared on.
    db: Db
    /// SQLite's statement, until it's finalized.
    handle: Compiled }

/// A statement standing at a row of its result, until its next `Statement.step` or
/// `Statement.reset`: `Row`'s functions read its columns.
type Row =
  /// The statement whose row this is.
  | RowOf of Statement

/// What a step of a statement came to.
type Step =
  /// A row of the result, to read before the next step.
  | Row of Row
  /// The statement has run to its end.
  | Done
  /// The step failed.
  | Failed of Error

/// How `Db.connectWith` opens a database.
type Options =
  { /// Open for reading only; the file must exist.
    readOnly: bool
    /// Create the file when it isn't there.
    create: bool
    /// How long a call waits for another connection's lock before it's `Busy`, in
    /// milliseconds.
    busyTimeout: int }

/// `use` closes the connection. Statements still open keep working until each is finalized.
impl Dispose<Db> =
  let dispose (db: Db) =
    match db.handle.connection.Value with
    | Some p ->
      db.handle.connection.Value <- None
      Native.sqlite3_close_v2 p |> ignore
    | None -> ()

/// `use` finalizes the statement.
impl Dispose<Statement> =
  let dispose (s: Statement) =
    match s.handle.compiled.Value with
    | Some p ->
      s.handle.compiled.Value <- None
      Native.sqlite3_finalize p |> ignore
    | None -> ()

// the error for a result code: the connection's message when it's open, else the code's own
let private errorOf (db: Db) (code: i32) : Error =
  let message =
    match db.handle.connection.Value with
    | Some p -> String.ofCStr (Native.sqlite3_errmsg p)
    | None -> String.ofCStr (Native.sqlite3_errstr code)
  let primary = int code &&& 0xFF
  if primary = Native.SQLITE_BUSY || primary = Native.SQLITE_LOCKED then
    Busy message
  else if primary = Native.SQLITE_CONSTRAINT then
    Constraint message
  else
    Other (int code, message)

/// Functions on `Error`.
module Error =
  /// The error as a line of text.
  let message (e: Error) : string =
    match e with
    | Busy m -> $"busy: {m}"
    | Constraint m -> $"constraint: {m}"
    | Closed -> "closed"
    | Other (code, m) -> $"{m} ({code})"

/// Functions on `Statement`.
module Statement =
  // binds one value to parameter `at` (from 1): SQLite's result code
  let private bindOne (p: cptr) (at: i32) (v: Value) : i32 =
    match v with
    | Null -> Native.sqlite3_bind_null p at
    | Int n -> Native.sqlite3_bind_int64 p at n
    | Real x -> Native.sqlite3_bind_double p at x
    | Text t -> zs_sqlite_bind_text p at (String.bytes t)
    | Blob b -> zs_sqlite_bind_blob p at b.[0..]

  /// Binds the values to the statement's parameters (`?`, `?1`, `:name`) in order, replacing
  /// what was bound. An `Error` when their number isn't the statement's.
  let bind (s: Statement) (args: list<Value>) : result<unit, Error> =
    match s.handle.compiled.Value with
    | None -> Error Closed
    | Some p ->
      let wants = int (Native.sqlite3_bind_parameter_count p)
      let given = List.length args
      if wants <> given then
        Error (Other (Native.SQLITE_MISUSE, $"the statement has {wants} parameters, {given} given"))
      else
        Native.sqlite3_reset p |> ignore
        let mutable i = 1
        let mutable failed = i32 0
        for v in args do
          if failed = i32 0 then
            failed <- bindOne p (i32 i) v
            i <- i + 1
        if failed = i32 0 then Ok () else Error (errorOf s.db failed)

  /// Runs the statement to its next row, or to its end.
  let step (s: Statement) : Step =
    match s.handle.compiled.Value with
    | None -> Failed Closed
    | Some p ->
      let code = Native.sqlite3_step p
      if int code = Native.SQLITE_ROW then
        Row (RowOf s)
      else if int code = Native.SQLITE_DONE then
        Done
      else
        // the reset gives the statement's own error code where the step gave a general one
        let precise = Native.sqlite3_reset p
        Failed (errorOf s.db (if precise = i32 0 then code else precise))

  /// Puts the statement back at its start, to run again with what's bound.
  let reset (s: Statement) : unit =
    match s.handle.compiled.Value with
    | Some p -> Native.sqlite3_reset p |> ignore
    | None -> ()

/// Functions on `Row`: a column is numbered from 0. Reading a column that isn't there, or a
/// row its statement has moved on from, is a panic.
module Row =
  // SQLite's statement, with the column checked against the row it stands at
  let private at (r: Row) (column: int) : cptr =
    let (RowOf s) = r
    match s.handle.compiled.Value with
    | None -> panic "Sqlite.Row: the statement is closed"
    | Some p ->
      let n = int (Native.sqlite3_data_count p)
      if n = 0 then panic "Sqlite.Row: the statement isn't at this row any more"
      if column < 0 || column >= n then panic $"Sqlite.Row: column {column} of {n}"
      p

  // the column's bytes, copied: SQLite's own are valid only until the next step
  let private bytes (p: cptr) (column: int) (text: bool) : array<u8> =
    let c = i32 column
    let data = if text then Native.sqlite3_column_text p c else Native.sqlite3_column_blob p c
    let n = int (Native.sqlite3_column_bytes p c)
    let first: ptr<u8> = unsafe Ptr.ofCPtr data
    if n = 0 || Ptr.isNull first then [||] else Array.ofSpan (unsafe (Span.ofPtr first n))

  /// How many columns the row has.
  let count (r: Row) : int =
    let (RowOf s) = r
    match s.handle.compiled.Value with
    | Some p -> int (Native.sqlite3_data_count p)
    | None -> 0

  // the column's storage class: SQLITE_INTEGER, SQLITE_TEXT, …
  let private kind (r: Row) (column: int) : int =
    int (Native.sqlite3_column_type (at r column) (i32 column))

  /// Whether the column is NULL.
  let isNull (r: Row) (column: int) : bool = kind r column = Native.SQLITE_NULL

  /// The column's text as SQLite's own bytes, with no copy: valid only until the statement's
  /// next step, reset or close, which nothing checks, so it's callable only from `unsafe`.
  /// For a server that writes a column straight into its answer.
  [<Unsafe>]
  let textSpan (r: Row) (column: int) : span<u8> =
    let p = at r column
    let data = Native.sqlite3_column_text p (i32 column)
    let n = int (Native.sqlite3_column_bytes p (i32 column))
    let first: ptr<u8> = unsafe Ptr.ofCPtr data
    if n = 0 || Ptr.isNull first then String.bytes "" else unsafe (Span.ofPtr first n)

  /// The column as an integer, converted as SQLite converts (NULL is 0).
  let int (r: Row) (column: int) : i64 = Native.sqlite3_column_int64 (at r column) (i32 column)

  /// The column as a float, converted as SQLite converts (NULL is 0.0).
  let real (r: Row) (column: int) : float =
    Native.sqlite3_column_double (at r column) (i32 column)

  /// The column as text, copied (NULL is ""); a byte that isn't UTF-8 reads as U+FFFD.
  let text (r: Row) (column: int) : string = String.ofBytes (bytes (at r column) column true).[0..]

  /// The column's bytes, copied (NULL is empty).
  let blob (r: Row) (column: int) : array<u8> = bytes (at r column) column false

  /// The column as the value SQLite stores.
  let value (r: Row) (column: int) : Value =
    let k = kind r column
    if k = Native.SQLITE_INTEGER then
      Int (int r column)
    else if k = Native.SQLITE_FLOAT then
      Real (real r column)
    else if k = Native.SQLITE_TEXT then
      Text (text r column)
    else if k = Native.SQLITE_BLOB then
      Blob (blob r column)
    else
      Null

/// Functions on `Db`.
module Db =
  /// `Db.connect`'s options: read and write, the file created when it isn't there, and five
  /// seconds' wait for another connection's lock.
  let defaults : Options = { readOnly = false; create = true; busyTimeout = 5000 }

  /// Opens the database at `path` (`":memory:"` is a database in memory, gone when closed).
  let connectWith (options: Options) (path: string) : result<Db, Error> =
    if String.contains "\0" path then
      Error (Other (Native.SQLITE_MISUSE, "a NUL byte in the path"))
    else
      let flags =
        if options.readOnly then
          Native.SQLITE_OPEN_READONLY
        else if options.create then
          Native.SQLITE_OPEN_READWRITE ||| Native.SQLITE_OPEN_CREATE
        else
          Native.SQLITE_OPEN_READWRITE
      let out: ptr<cptr> = unsafe Ptr.alloc 1
      let code = zs_sqlite_open path (i32 flags) (i32 options.busyTimeout) out
      let p = unsafe Ptr.read out
      unsafe Ptr.free out
      let raw: ptr<u8> = unsafe Ptr.ofCPtr p
      if Ptr.isNull raw then
        Error (Other (int code, "out of memory"))
      else
        let db = { handle = { connection = ref (Some p) } }
        if code = i32 0 then
          Ok db
        else
          let e = errorOf db code
          dispose db
          Error e

  /// Opens the database at `path` with `Db.defaults`.
  let connect (path: string) : result<Db, Error> = connectWith defaults path

  /// Compiles one statement. Text after it (a second statement) is an `Error`.
  let prepare (db: Db) (sql: string) : result<Statement, Error> =
    match db.handle.connection.Value with
    | None -> Error Closed
    | Some p ->
      let out: ptr<cptr> = unsafe Ptr.alloc 1
      let code = zs_sqlite_prepare p (String.bytes sql) out
      let made = unsafe Ptr.read out
      unsafe Ptr.free out
      let raw: ptr<u8> = unsafe Ptr.ofCPtr made
      if code <> i32 0 then
        if code = i32 -1 then
          Error (Other (Native.SQLITE_MISUSE, "more than one statement"))
        else
          Error (errorOf db code)
      else if Ptr.isNull raw then
        Error (Other (Native.SQLITE_MISUSE, "no statement in the text"))
      else
        Ok { db = db; handle = { compiled = ref (Some made) } }

  /// Runs a statement that gives no rows (an insert, an update, `create table`) with the values
  /// bound to its parameters: how many rows it changed.
  let exec (db: Db) (sql: string) (args: list<Value>) : result<int, Error> =
    match prepare db sql with
    | Error e -> Error e
    | Ok made ->
      use s = made
      match Statement.bind s args with
      | Error e -> Error e
      | Ok () ->
        let mutable last = Statement.step s
        while (match last with
          | Row _ -> true
          | _ -> false) do
          last <- Statement.step s
        match last, db.handle.connection.Value with
        | Failed e, _ -> Error e
        | _, Some p -> Ok (int (Native.sqlite3_changes64 p))
        | _, None -> Error Closed

  /// The row id of the last row this connection inserted (an `integer primary key`'s value),
  /// 0 when it has inserted none.
  let lastInsertId (db: Db) : i64 =
    match db.handle.connection.Value with
    | Some p -> Native.sqlite3_last_insert_rowid p
    | None -> i64 0

  /// Runs a query with the values bound to its parameters, and gives what `read` makes of
  /// each row, in order.
  let query (db: Db) (sql: string) (args: list<Value>) (read: Row -> 'a) : result<list<'a>, Error> =
    match prepare db sql with
    | Error e -> Error e
    | Ok made ->
      use s = made
      match Statement.bind s args with
      | Error e -> Error e
      | Ok () ->
        let mutable rows = []
        let mutable failed = None
        let mutable more = true
        while more do
          match Statement.step s with
          | Row r -> rows <- read r :: rows
          | Done -> more <- false
          | Failed e ->
            failed <- Some e
            more <- false
        match failed with
        | Some e -> Error e
        | None -> Ok (List.rev rows)

  // a transaction begun and not yet committed: disposing it rolls back
  type private Open = { db: Db; committed: ref<bool> }

  impl Dispose<Open> =
    let dispose (t: Open) =
      if not t.committed.Value then exec t.db "rollback" [] |> ignore

  /// Runs `body` in a transaction: committed when it gives `Ok`, rolled back when it gives an
  /// `Error` or is left by a throw.
  let transaction (db: Db) (body: unit -> result<'a, Error>) : result<'a, Error> =
    match exec db "begin" [] with
    | Error e -> Error e
    | Ok _ ->
      use t = { db = db; committed = ref false }
      match body () with
      | Error e -> Error e
      | Ok x ->
        match exec db "commit" [] with
        | Error e -> Error e
        | Ok _ ->
          t.committed.Value <- true
          Ok x
