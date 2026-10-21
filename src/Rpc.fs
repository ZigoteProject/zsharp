/// JSON helpers shared by the language server and the MCP server.
module Rpc

open System
open System.IO
open System.Text.Json.Nodes

/// Standard input, possibly with bytes already read put back in front (protocol detection).
type PrefixedStream(prefix: byte[], inner: Stream) =
    inherit Stream()
    let mutable pos = 0
    override _.CanRead = true
    override _.CanSeek = false
    override _.CanWrite = false
    override _.Length = raise (NotSupportedException())

    override _.Position
        with get () = raise (NotSupportedException())
        and set _ = raise (NotSupportedException())

    override _.Flush() = ()
    override _.Seek(_, _) = raise (NotSupportedException())
    override _.SetLength _ = raise (NotSupportedException())
    override _.Write(_, _, _) = raise (NotSupportedException())

    override _.Read(buffer: byte[], offset: int, count: int) =
        if pos < prefix.Length then
            let n = min count (prefix.Length - pos)
            Array.blit prefix pos buffer offset n
            pos <- pos + n
            n
        else
            inner.Read(buffer, offset, count)

/// The servers read their messages from here.
let mutable input: Stream = Console.OpenStandardInput()

let obj (kvs: (string * JsonNode) list) : JsonNode =
    let o = JsonObject()

    for k, v in kvs do
        o[k] <- v

    o

let str (s: string) : JsonNode = JsonValue.Create s
let num (n: int) : JsonNode = JsonValue.Create n
let bool (b: bool) : JsonNode = JsonValue.Create b

let arr (xs: JsonNode seq) : JsonNode =
    let a = JsonArray()

    for x in xs do
        a.Add x

    a

let getStr (n: JsonNode) = n.GetValue<string>()
let getInt (n: JsonNode) = n.GetValue<int>()

