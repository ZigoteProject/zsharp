// Provided modules by import (0001): `module X = import …` names one, a bare import opens a
// hidden one; each is a file in .zs-cache/providers, written from the sample beside this file
module Weather = import json "weather.json"
import csv ("stocks.csv", separator = ";")

let main () =
  let doc =
    "{\"city\": \"Bergen\", \"temp\": 12, \"humidity\": 90, \"readings\": [{\"at\": \"now\", \"value\": 1}], \"wind\": null, \"station\": {\"id\": 1, \"name\": \"Florida\"}, \"backup\": {\"id\": 2, \"name\": \"Nesttun\"}, \"tags\": [\"wet\"], \"mixed\": [], \"first-name\": \"Ida\"}"
  match Weather.parse doc with
  | Ok w ->
    println $"{w.city} {w.temp} {w.station.name} {w.``first-name``} {w.tags} {List.length w.readings}"
  | Error e -> println e
  // the record provided for an array's objects, by its name
  let r: Weather.Reading = { at = "later"; value = 2.5; note = Some "windy" }
  println (Weather.print { city = "Oslo"
      temp = 3.0
      humidity = 50
      readings = [ r ]
      wind = None
      station = { id = 3; name = "Blindern" }
      backup = { id = 4; name = "Ski" }
      tags = []
      mixed = []
      ``first-name`` = "Ada" })
  // the bare import: Row, parse and print are in scope
  match parse "date;open;close;volume;note;active\n2026-10-20;1.5;2;3;;true\n" with
  | Ok rows ->
    for row in rows do
      println $"{row.date} {row.``open``} {row.volume} {row.active} {row.note}"
    let text = print rows
    println text
  | Error e -> println e
  0
