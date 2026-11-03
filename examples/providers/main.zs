// Type providers (proposal 0001): the types of a JSON sample, a CSV file and a SQL schema,
// declared from the files at compile time, so the code is checked against their shape. Each
// import is a module: `zs provide json weather.json` prints the same one, to keep in place of
// the import.
//   zs run examples/providers/main.zs        (reads weather.json and stocks.csv beside it)
module Weather = import json "weather.json"
module Stocks = import csv ("stocks.csv", separator = ";")
module Db = import sql "schema.sql"

let report (w: Weather.Root) =
  // every field is typed from the sample: temp is an f64, readings a list of records, wind an
  // option (the sample has null), and "first-name" a field in backticks
  let values = List.map (fun (r: Weather.Reading) -> r.value) w.readings
  $"{w.city}: {w.temp} degrees, {List.length w.readings} readings {values}, wind {w.wind}, by {w.``first-name``}"

let main () =
  match File.readAllText "weather.json" |> Result.bind Weather.parse with
  | Ok w -> println (report w)
  | Error e -> println $"weather.json: {e}"
  // a document that lost a key: the error names the place
  match Weather.parse "{\"city\": \"Oslo\"}" with
  | Ok _ -> println "unexpected"
  | Error e -> println $"doesn't fit: {e}"
  match File.readAllText "stocks.csv" |> Result.bind Stocks.parse with
  | Ok rows ->
    for r in rows do
      let note =
        match r.note with
        | Some n -> ", " + n
        | None -> ""
      println $"{r.date}: {r.``open``} -> {r.close}, {r.volume} traded{note}"
    // rows written back the way the file writes them
    print (Stocks.print (List.filter (fun (r: Stocks.Row) -> r.active) rows))
  | Error e -> println $"stocks.csv: {e}"
  // a schema's tables: a record each, with the table's name and columns beside it
  let ada: Db.Users = { id = 1; name = "Ada"; ``signed-up`` = "2026-11-03"; active = true }
  let columns = String.join ", " Db.Users.columns
  println $"insert into {Db.Users.table} ({columns}): {ada.name}, email {ada.email}"
  0
