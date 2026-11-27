// Notes over HTTP, kept in SQLite (proposal 0032's packages together):
//   GET /notes          every note, as JSON
//   POST /notes         the body is a new note's text; answers with it and its id
//   DELETE /notes/<id>  removes one
//   GET /crash          a request whose handling has a bug: that request fails, the server goes on
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

/// What a request asks for.
type Asked =
  | Every
  | New of string
  | Gone of string
  | Unknown

// what the request asks for, from what it sent: the part of a request's work that a bug in it
// is most likely in (here, one put there to be found)
let asked (m: Method) (path: string) (body: string) : Asked =
  match m, path with
  | Get, "/notes" -> Every
  | Post, "/notes" -> New body
  | Delete, p when String.startsWith "/notes/" p -> Gone(String.sub p 7 (String.length p - 7))
  | Get, "/crash" -> panic "a bug in this request"
  | _ -> Unknown

// A request's own work runs as a contained job: a panic in it is this request's failure (a
// 500), and the server and its other requests go on. What crosses into a job must be Share:
// the request's method, path and body are; the database's connection isn't (it's a C library's,
// and stays whole whatever a request does), so the job says what's asked and the answer is
// made outside it.
let route (db: Db) (req: Request) : Task<Response> =
  task {
    let m = req.method
    let path = req.path
    let body = Request.text req
    match Contained.run (fun () -> asked m path body) with
    | Error bug -> return Response.text 500 bug.message
    | Ok Every -> return notes db
    | Ok(New text) -> return add db text
    | Ok(Gone id) -> return remove db id
    | Ok Unknown -> return Response.text 404 "not found"
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
