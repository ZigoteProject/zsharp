/// JSON helpers shared by the language server and the MCP server.
module Rpc

open System.Text.Json.Nodes

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

