// Notes over HTTP, kept in SQLite (proposal 0032's packages together):
//   GET /notes          every note, as JSON
//   POST /notes         the body is a new note's text; answers with it and its id
//   DELETE /notes/<id>  removes one
// Usage: service [port] [database]   (port 8080 and notes.db by default)
//   curl -d 'buy milk' localhost:8080/notes; curl localhost:8080/notes
open Http
open Sqlite

[<Derive(ToJson)>]
type Note = { id: int; text: string }

let failed (e: Sqlite.Error) : Response = Response.text 500 (Sqlite.Error.message e)

let notes (db: Db) : Response =
  let read (row: Row) = { id = int (Row.int row 0); text = Row.text row 1 }
  match Db.query db "select id, text from notes order by id" [] read with
  | Ok found -> Response.json 200 (Json.print (toJson found))
  | Error e -> failed e

let add (db: Db) (text: string) : Response =
  if String.isEmpty (String.trim text) then
    Response.text 400 "a note needs some text"
  else
    let inserted =
      Db.query db "insert into notes (text) values (?) returning id" [ Text text ] (fun row ->
        Row.int row 0)
    match inserted with
    | Ok [ id ] -> Response.json 201 (Json.print (toJson { id = int id; text = text }))
    | Ok _ -> Response.text 500 "no id"
    | Error e -> failed e

let remove (db: Db) (id: string) : Response =
  match String.parseInt id with
  | None -> Response.text 400 "not a note's number"
  | Some n ->
    match Db.exec db "delete from notes where id = ?" [ Int (i64 n) ] with
    | Ok 0 -> Response.text 404 "no such note"
    | Ok _ -> Response.empty 204
    | Error e -> failed e

let route (db: Db) (req: Request) : Task<Response> =
  task {
    match req.method, req.path with
    | Get, "/notes" -> return notes db
    | Post, "/notes" -> return add db (Request.text req)
    | Delete, path when String.startsWith "/notes/" path ->
      return remove db (String.sub path 7 (String.length path - 7))
    | _ -> return Response.text 404 "not found"
  }

let main () =
  let args = Environment.args ()
  let port =
    match args with
    | p :: _ -> Option.defaultValue 8080 (String.parseInt p)
    | [] -> 8080
  let path =
    match args with
    | _ :: file :: _ -> file
    | _ -> "notes.db"
  match Db.connect path with
  | Error e ->
    println (Sqlite.Error.message e)
    1
  | Ok opened ->
    use db = opened
    match Db.exec db "create table if not exists notes (id integer primary key, text text not null)" [] with
    | Error e ->
      println (Sqlite.Error.message e)
      1
    | Ok _ ->
      match Server.listen { Server.defaults with port = port } with
      | Error e ->
        println (Http.Error.message e)
        1
      | Ok made ->
        use listening = made
        eprintln $"listening on http://127.0.0.1:{listening.port}"
        match Task.run (Server.run listening (route db)) with
        | Ok () -> 0
        | Error e ->
          println (Http.Error.message e)
          1
