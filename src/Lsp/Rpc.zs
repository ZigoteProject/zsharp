/// What the language server and the MCP server share: JSON written as the F# compiler's servers
/// wrote it (System.Text.Json's defaults, which the servers' test transcripts hold), reading
/// fields of a message, and LSP's framing (`Content-Length` headers, then the JSON).

let private hex = "0123456789ABCDEF"

let private unit16 (u: int) : string =
  "\\u" + String.sub hex ((u >>> 12) &&& 15) 1 + String.sub hex ((u >>> 8) &&& 15) 1 + String.sub hex ((u >>> 4) &&& 15) 1 + String.sub hex (u &&& 15) 1

// a string literal: controls, `"`, `\`, the characters HTML gives meaning to (& ' + < > `) and
// everything outside ASCII escaped, the last as UTF-16
let private quote (s: string) : string =
  let out = Buffer.empty
  Buffer.push "\"" out
  let n = String.length s
  let mutable i = 0
  // the first byte not copied yet
  let from = ref 0
  let flush (upto: int) =
    if upto > from.Value then
      Buffer.push (String.sub s from.Value (upto - from.Value)) out
  while i < n do
    let b = int (String.byte s i)
    if b >= 128 then
      flush i
      let (c, next) = String.decodeAt s i
      let cp = int c
      if cp >= 65536 then
        let v = cp - 65536
        Buffer.push (unit16 (55296 + (v >>> 10))) out
        Buffer.push (unit16 (56320 + (v &&& 1023))) out
      else
        Buffer.push (unit16 cp) out
      i <- next
      from.Value <- i
    else if b < 32 || b = 127 || b = 34 || b = 92 || b = 38 || b = 39 || b = 43 || b = 60 || b = 62 || b = 96 then
      flush i
      let e =
        match b with
        | 92 -> "\\\\"
        | 10 -> "\\n"
        | 13 -> "\\r"
        | 9 -> "\\t"
        | 8 -> "\\b"
        | 12 -> "\\f"
        | _ -> unit16 b
      Buffer.push e out
      i <- i + 1
      from.Value <- i
    else
      i <- i + 1
  flush n
  Buffer.push "\"" out
  String.concat (Array.toList (Buffer.toArray out))

/// The document as the servers send it: compact, strings escaped as System.Text.Json does.
let rec write (j: Json) : string =
  match j with
  | JNull -> "null"
  | JBool b -> if b then "true" else "false"
  | JInt n -> $"{n}"
  | JNumber x -> $"{x}"
  | JString s -> quote s
  | JArray xs -> "[" + String.join "," (List.map write xs) + "]"
  | JObject kvs ->
    let field (kv: string * Json) =
      let (k, v) = kv
      quote k + ":" + write v
    "{" + String.join "," (List.map field kvs) + "}"

/// A number.
let num (n: int) : Json = JInt(i64 n)

/// A field of an object, or JNull.
let field (key: string) (j: Json) : Json =
  match j with
  | JObject kvs ->
    match List.tryFind (fun (k, _) -> k = key) kvs with
    | Some(_, v) -> v
    | None -> JNull
  | _ -> JNull

/// The field at a path of keys (JNull when one is missing).
let at (keys: list<string>) (j: Json) : Json = List.fold (fun v k -> field k v) j keys

/// A string's text ("" for anything else).
let text (j: Json) : string =
  match j with
  | JString s -> s
  | _ -> ""

/// A number's value (0 for anything else).
let intOf (j: Json) : int =
  match j with
  | JInt n -> int n
  | JNumber x -> int x
  | _ -> 0

/// A file URI's path (file:///a/b%20c → /a/b c).
let toPath (uri: string) : string =
  let p = if String.startsWith "file://" uri then String.sub uri 7 (String.length uri - 7) else uri
  let out = Buffer.empty
  let n = String.length p
  let mutable i = 0
  let hexValue (b: u8) =
    let c = int b
    if c >= 48 && c <= 57 then c - 48 else if c >= 65 && c <= 70 then c - 55 else if c >= 97 && c <= 102 then c - 87 else -1
  while i < n do
    let b = String.byte p i
    if b = u8 37 && i + 2 < n && hexValue (String.byte p (i + 1)) >= 0 && hexValue (String.byte p (i + 2)) >= 0 then
      Buffer.push (u8 (hexValue (String.byte p (i + 1)) * 16 + hexValue (String.byte p (i + 2)))) out
      i <- i + 3
    else
      Buffer.push b out
      i <- i + 1
  String.ofBytes (Buffer.toArray out)

/// A path's file URI, its characters outside the unreserved ones and `/` percent-encoded (as
/// .NET's Uri writes one).
let toUri (path: string) : string =
  let full = Path.getFullPath path
  let out = Buffer.empty
  for i in 0 .. String.length full - 1 do
    let b = int (String.byte full i)
    let plain = (b >= 97 && b <= 122) || (b >= 65 && b <= 90) || (b >= 48 && b <= 57) || String.contains (String.ofByte (u8 b)) "/-._~!$&'()*+,;=:@"
    if plain then Buffer.push (String.ofByte (u8 b)) out else Buffer.push ("%" + String.sub hex (b / 16) 1 + String.sub hex (b % 16) 1) out
  "file://" + String.concat (Array.toList (Buffer.toArray out))

/// One LSP message: `Content-Length: n` headers, a blank line, n bytes of JSON; None at the end
/// of the input. `first` is a header line already read (protocol detection read it).
let readMessage (r: IO.Reader) (first: option<string>) : option<Json> =
  let length = ref -1
  let header (l0: string) =
    let l = String.trimEnd l0
    if String.startsWith "content-length:" (String.toLower l) then
      let n : option<int> = Int.parse (String.trim (String.sub l 15 (String.length l - 15)))
      length.Value <- Option.defaultValue -1 n
  match first with
  | Some l -> header l
  | None -> ()
  let mutable reading = true
  let mutable eof = false
  while reading do
    match IO.Reader.readLine r with
    | Ok(Some l) -> if String.trimEnd l = "" then reading <- false else header l
    | _ ->
      reading <- false
      eof <- true
  if eof || length.Value < 0 then
    None
  else
    let buf = Buffer.create length.Value (u8 0)
    match IO.Reader.readExactly r buf length.Value with
    | Ok () ->
      match Json.parse (String.ofBytes (Buffer.toArray buf)) with
      | Ok j -> Some j
      | Error _ -> Some JNull
    | Error _ -> None

/// Sends one LSP message.
let send (w: IO.Writer) (msg: Json) : unit =
  let body = write msg
  IO.Writer.writeText w $"Content-Length: {String.length body}\r\n\r\n{body}" |> ignore
  IO.Writer.flush w |> ignore
