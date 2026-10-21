// Strings can span lines: the line breaks are part of the text. """…""" strings are raw:
// quotes and backslashes stay as written.
let banner = "first line
second line"

let json = """{ "name": "Z#", "path": "C:\new" }"""

let poem =
  """roses
  are red"""

let main () =
  println banner
  println json
  println poem
  println $"{String.length banner} {String.length json}"
  let s = "a
b" + "c"
  println s
  let n = 2
  println $"total {n * 10}
done"
  0
