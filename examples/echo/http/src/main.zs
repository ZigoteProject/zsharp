// An echo server over HTTP, on packages/http: a POST's body comes back as it was sent, with its
// Content-Type; any other request gets its method and path. Usage: echo-http [port] (8080 by
// default).
//   curl -d 'hello' localhost:8080/
open Http

let echo (req: Request) : Task<Response> =
  task {
    match req.method with
    | Post ->
      let kind = Option.defaultValue "application/octet-stream" (Request.header "content-type" req)
      return Response.bytes 200 kind req.body
    | m -> return Response.text 200 $"{Method.name m} {req.path}\n"
  }

let main () =
  let port =
    match Environment.args () with
    | p :: _ -> Option.defaultValue 8080 (String.parseInt p)
    | [] -> 8080
  match Server.listen { Server.defaults with port = port } with
  | Error e ->
    eprintln (Error.message e)
    1
  | Ok made ->
    use listening = made
    eprintln $"echoing on http://127.0.0.1:{listening.port}"
    match Task.run (Server.run listening echo) with
    | Ok () -> 0
    | Error e ->
      eprintln (Error.message e)
      1
