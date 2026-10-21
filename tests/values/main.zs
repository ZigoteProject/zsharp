// Top-level values: constants are inlined at each use (a literal one takes the type each use
// needs); other values are computed once at startup, in module order, and freed at exit.
open Config

type Point = { x: int; y: int }

let mask = 0xFF
let width = 8
let area = width * width
let greeting = "hello"
let origin = { x = 0; y = 0 }
let flags: u8 = 0b1010_0000
let limit = if width > 4 then 100 else 10
let none: option<int> = None

// computed at startup
let squares = Array.init 5 (fun i -> i * i)
let names = [ "ada"; "alan"; greeting ]
let total = Array.sum squares
let counter = ref 0

let bump () =
  counter.Value <- counter.Value + 1
  counter.Value

let main () =
  let small: u8 = mask
  let big: int = mask * 1000
  println $"{small} {big} {area} {flags} {limit} {none} {origin.x}"
  println $"{squares.[4]} {total} {List.length names} {List.head names} {Config.port} {defaultHost}"
  println $"{bump ()} {bump ()} {counter.Value}"
  let width = 100 // a local doesn't change what the constant area means
  println $"{width} {area} {(mask: int) + 1} {(3: u8)}"
  0
