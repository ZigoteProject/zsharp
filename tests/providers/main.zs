// Provided modules in use (0001): Weather.zs and Stocks.zs beside this file are what
// `zs provide json weather.json` and `zs provide csv stocks.csv --separator=;` printed, with no
// import line; the samples are read at run time as the program's own files
let main () =
  match File.readAllText "weather.json" with
  | Error e -> println e
  | Ok text ->
    match Weather.parse text with
    | Error e -> println $"weather: {e}"
    | Ok w ->
      let notes = List.map (fun (r: Weather.Reading) -> Option.defaultValue "-" r.note) w.readings
      println $"{w.city} {w.temp} {w.humidity}: {List.length w.readings} readings, values {List.map (fun (r: Weather.Reading) -> r.value) w.readings}, notes {notes}"
      println $"station {w.station.name} ({w.station.id}), backup {w.backup.name}, wind {w.wind}, tags {List.length w.tags}, mixed {w.mixed}, {w.``first-name``}"
      // the document again: the same text, read back the same
      let again = Weather.print w
      match Weather.parse again with
      | Ok w2 -> println $"printed and read back: {w2.city = w.city && List.length w2.readings = 3}"
      | Error e -> println $"read back: {e}"
  // a document that no longer fits: an error naming the place
  match Weather.parse "{\"city\": \"Oslo\", \"temp\": \"warm\"}" with
  | Ok _ -> println "unexpected"
  | Error e -> println $"doesn't fit: {e}"
  match File.readAllText "stocks.csv" with
  | Error e -> println e
  | Ok text ->
    match Stocks.parse text with
    | Error e -> println $"stocks: {e}"
    | Ok rows ->
      for r in rows do
        println $"{r.date} {r.``open``} -> {r.close} x{r.volume} {r.active} {r.note}"
      let back = Stocks.print rows
      match Stocks.parse back with
      | Ok rows2 ->
        println $"printed and read back: {List.length rows2 = List.length rows && (List.item 1 rows2).note = (List.item 1 rows).note}"
      | Error e -> println $"read back: {e}"
  // rows that don't fit: the row and the column
  match Stocks.parse "date;open;close;volume;note;active\n2026-10-23;1;2;many;;true\n" with
  | Ok _ -> println "unexpected"
  | Error e -> println $"doesn't fit: {e}"
  match Stocks.parse "date;open\n" with
  | Ok _ -> println "unexpected"
  | Error e -> println $"doesn't fit: {e}"
  0
