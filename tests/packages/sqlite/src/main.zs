// packages/sqlite (0032): values bound and read back in each storage class, what a statement
// refuses, a transaction committed and one rolled back, and handles used after they're closed.
open Sqlite

// the sql provider's typed queries, run on this package (0001's rows = "sqlite")
module Shop = import sql ("shop.sql", queries = "shop-queries.sql", rows = "sqlite")

let typed (db: Db) : result<unit, Error> =
  let _ =
    Db.exec db "create table customers (id integer primary key, name text not null, email text, credit real not null default 0, active boolean not null default 1, badge blob)" []?
  let a =
    Shop.AddCustomer.run db { name = "Ada"
      email = Some "ada@example.org"
      credit = 12.5
      active = true
      badge = Some [| u8 1; u8 2 |] }?
  let b = Shop.AddCustomer.run db { name = "Bob"; credit = 0.5; active = true }?
  println $"added {a + b}"
  let ada = Shop.GetCustomer.run db { id = 1 }?
  match ada with
  | Some c -> println $"{c.id} {c.name} {c.email} {c.credit:F1}"
  | None -> println "no customer 1"
  let nobody = Shop.GetCustomer.run db { id = 99 }?
  println $"customer 99: {Option.isSome nobody}"
  let off = Shop.Deactivate.run db { credit = 1.0 }?
  println $"deactivated {off}"
  let active = Shop.ActiveCustomers.run db { active = true }?
  for c in active do
    let badge = Option.map (fun (x: array<u8>) -> Array.length x) c.badge
    println $"{c.id} {c.name} {c.email} {c.active} {badge}"
  let all = Db.query db "select * from customers order by id" [] Shop.Customers.fromRow?
  println $"{List.map (fun (c: Shop.Customers) -> c.name) all}"
  let n = Shop.CountCustomers.run db?
  println $"{Option.map (fun (r: Shop.CountCustomers.Row) -> r.n) n}"
  Ok ()

let show (r: result<int, Error>) : string =
  match r with
  | Ok n -> $"ok {n}"
  | Error e -> $"error: {Error.message e}"

let describe (v: Value) : string =
  match v with
  | Null -> "null "
  | Int n -> $"int {n} "
  | Real x -> $"real {x:F1} "
  | Text t -> $"text {t} "
  | Blob b -> $"blob {Array.length b} "

let names (db: Db) : string =
  match Db.query db "select name from users order by id" [] (fun row -> Row.text row 0) with
  | Ok found -> String.concat (List.map (fun n -> String.replace n "\0" "<NUL>" + " ") found)
  | Error e -> Error.message e

// a transaction's body that inserts and then throws
let thrower (db: Db) (insert: string) () : result<int, Error> =
  Db.transaction db (fun () ->
    let _ = Db.exec db insert [ Text "thrown"; Null; Null ]?
    Throw.throw "left by a throw")

let run (db: Db) : result<unit, Error> =
  let _ =
    Db.exec db "create table users (id integer primary key, name text not null unique, score real, photo blob)" []?
  let insert = "insert into users (name, score, photo) values (?, ?, ?)"
  println (show (Db.exec db insert [ Text "ada"; Real 9.5; Blob [| u8 1; u8 0; u8 255 |] ]))
  println (show (Db.exec db insert [ Text "o'brien; drop table users"; Null; Blob [||] ]))
  println (show (Db.exec db insert [ Text "zoë\0x"; Real 1.0; Null ]))

  println $"last id {Db.lastInsertId db}"
  println "== read back"
  let rows =
    Db.query db "select id, name, score, photo from users order by id" [] (fun row ->
      let score = if Row.isNull row 2 then "null" else $"{Row.real row 2:F1}"
      $"{Row.int row 0} {String.length (Row.text row 1)} {score} {Array.length (Row.blob row 3)} {Row.count row}")?
  for line in rows do
    println line
  let values =
    Db.query db "select 1, 2.5, 'x', x'00ff', null" [] (fun row ->
      List.map (Row.value row) [ 0 .. 4 ])?
  for row in values do
    println (String.concat (List.map describe row))

  // SQLite's own bytes, read before the statement moves on
  let lengths =
    Db.query db "select name from users order by id" [] (fun row ->
      Span.length (unsafe (Row.textSpan row 0)))?
  println $"{lengths}"

  println "== refused"
  println (show (Db.exec db insert [ Text "ada"; Null; Null ]))
  println (show (Db.exec db insert [ Null; Null; Null ]))
  println (show (Db.exec db insert [ Text "one" ]))
  println (show (Db.exec db "select * from nowhere" []))
  println (show (Db.exec db "delete from users; delete from users" []))
  println (show (Db.exec db " ; " []))
  println (show (Db.exec db "" []))
  println (show (Db.exec db "select \"ada\"" []))

  println "== transactions"
  let kept =
    Db.transaction db (fun () ->
      let _ = Db.exec db insert [ Text "kept"; Null; Null ]?
      Ok 1)
  println (show kept)
  let undone =
    Db.transaction db (fun () ->
      let _ = Db.exec db insert [ Text "undone"; Null; Null ]?
      Db.exec db insert [ Text "ada"; Null; Null ])
  println (show undone)
  match Throw.catch (thrower db insert) with
  | Error why -> println why
  | Ok _ -> println "not thrown"
  println (names db)

  println "== a statement, stepped by hand"
  let made = Db.prepare db "select name from users where id > ? order by id"?
  use s = made
  Statement.bind s [ Int (i64 1) ]?
  let mutable more = true
  while more do
    match Statement.step s with
    | Row row -> println (String.replace (Row.text row 0) "\0" "<NUL>")
    | Done -> more <- false
    | Failed e ->
      println (Error.message e)
      more <- false
  Ok ()

let main () =
  match Db.connect ":memory:" with
  | Error e ->
    println (Error.message e)
    1
  | Ok db ->
    match run db with
    | Ok () -> ()
    | Error e -> println $"failed: {Error.message e}"
    println "== typed queries"
    match typed db with
    | Ok () -> ()
    | Error e -> println $"failed: {Error.message e}"
    println "== closed"
    let kept = Db.prepare db "select 1"
    dispose db
    dispose db
    println (show (Db.exec db "select 1" []))
    match kept with
    | Ok s ->
      // the statement outlives its connection's close, and is finalized by hand
      (match Statement.step s with
        | Row row -> println $"row {Row.int row 0}"
        | _ -> println "no row")
      dispose s
      (match Statement.step s with
        | Failed e -> println (Error.message e)
        | _ -> println "stepped")
    | Error e -> println (Error.message e)
    match Db.connectWith { Db.defaults with readOnly = true } "/nonexistent/dir/x.db" with
    | Ok _ -> println "opened"
    | Error e -> println $"error: {Error.message e}"
    0
