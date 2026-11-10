/// The csv provider (proposal 0001): a file's header and rows as a `Row` record, with parse and
/// print functions, as `zs provide csv <file>` prints. A column is `int` when every cell is one,
/// else `f64`, else `bool`, else `string`; an empty cell somewhere makes it an option. The
/// module reads rows itself (a cell in quotes may hold the separator, a quote doubled and a line
/// break), so it needs Core only; reading the file is the program's.

/// The cells of every row: a cell in quotes may hold the separator, a quote doubled, and a line
/// break; `\r\n` ends a row as `\n` does; a last line without a line break is a row. The same
/// reader is written into the module.
let cells (separator: string) (text: string) : list<list<string>> =
  let n = String.length text
  let sepLen = String.length separator
  let quote = u8 34
  let startsAt (i: int) =
    let mutable k = 0
    while k < sepLen && i + k < n && String.byte text (i + k) = String.byte separator k do
      k <- k + 1
    k = sepLen
  let rows: ref<list<list<string>>> = ref []
  let row: ref<list<string>> = ref []
  let cell = ref ""
  let mutable from = 0
  let mutable i = 0
  let mutable quoted = false
  let endCell () =
    row.Value <- cell.Value :: row.Value
    cell.Value <- ""
  let endRow () =
    rows.Value <- List.rev row.Value :: rows.Value
    row.Value <- []
  while i < n do
    let b = String.byte text i
    if quoted then
      if b = quote then
        if i + 1 < n && String.byte text (i + 1) = quote then
          // a doubled quote: one, made so when the run ends (a copy per quote would be quadratic)
          i <- i + 2
        else
          // the run, each quote in it one of a doubled pair
          cell.Value <- cell.Value + String.replace (String.sub text from (i - from)) "\"\"" "\""
          quoted <- false
          i <- i + 1
          from <- i
      else
        i <- i + 1
    else if b = quote && from = i && cell.Value = "" then
      quoted <- true
      i <- i + 1
      from <- i
    else if sepLen > 0 && startsAt i then
      cell.Value <- cell.Value + String.sub text from (i - from)
      endCell ()
      i <- i + sepLen
      from <- i
    else if b = u8 10 then
      let piece = String.sub text from (i - from)
      let line =
        if String.endsWith "\r" piece then String.sub piece 0 (String.length piece - 1) else piece
      cell.Value <- cell.Value + line
      endCell ()
      endRow ()
      i <- i + 1
      from <- i
    else
      i <- i + 1
  // the last cell and row, when the text doesn't end with a line break (a run in quotes left
  // open read as if closed there)
  if from < n || cell.Value <> "" || not (List.isEmpty row.Value) then
    let rest = String.sub text from (n - from)
    cell.Value <- cell.Value + (if quoted then String.replace rest "\"\"" "\"" else rest)
    endCell ()
    endRow ()
  List.rev rows.Value

// each element with its position, from i
let rec private index (i: int) (xs: list<'a>) : list<int * 'a> =
  match xs with
  | [] -> []
  | x :: rest -> (i, x) :: index (i + 1) rest

/// A column: its header, its cells' type and whether a cell is empty somewhere.
type Column = { header: string; kind: string; optional: bool }

let private kinds : Set<string> = Set.ofList [ "int"; "f64"; "bool"; "string" ]

/// The type every non-empty cell has: int, f64, bool, else string.
let private kindOf (values: list<string>) : string =
  let present = List.filter (fun (v: string) -> v <> "") values
  let isInt (v: string) =
    let r: option<int> = Int.parse v
    Option.isSome r
  let isFloat (v: string) =
    let r: option<f64> = Float.parse v
    Option.isSome r
  let isBool (v: string) = v = "true" || v = "false"
  if List.isEmpty present then "string"
  else if List.forall isInt present then "int"
  else if List.forall isFloat present then "f64"
  else if List.forall isBool present then "bool"
  else "string"

/// The options `zs provide csv` takes.
let options : list<string> = [ "separator"; "hasHeaders"; "types" ]

/// The pairs of a `types` option: `volume:f64,note:string`, a column and its type.
let private overridesOf (types: string) : result<list<string * string>, string> =
  let one (item: string) : result<string * string, string> =
    match String.indexOf ":" item with
    | None -> Error ("types: '" + item + "' isn't column:type, as volume:f64")
    | Some i ->
      let t = String.trim (String.sub item (i + 1) (String.length item - i - 1))
      if Set.contains t kinds then Ok(String.sub item 0 i, t)
      else Error ("types: '" + t + "' isn't a column's type (int, f64, bool or string)")
  let rec go (items: list<string>) (acc: list<string * string>) =
    match items with
    | [] -> Ok(List.rev acc)
    | item :: rest ->
      match one (String.trim item) with
      | Ok p -> go rest (p :: acc)
      | Error e -> Error e
  if types = "" then Ok [] else go (String.split "," types) []

// the reader above, as the module's own (Core only, so a microcontroller build has it)
let private readerText (separator: string) : list<string> =
  [ "let private separator = " + Names.literal separator
    ""
    "/// The cells of every row: a cell in quotes may hold the separator, a quote doubled, and a line"
    "/// break; \\r\\n ends a row as \\n does; a last line without a line break is a row."
    "let private cells (text: string) : list<list<string>> ="
    "  let n = String.length text"
    "  let sepLen = String.length separator"
    "  let quote = u8 34"
    "  let startsAt (i: int) ="
    "    let mutable k = 0"
    "    while k < sepLen && i + k < n && String.byte text (i + k) = String.byte separator k do"
    "      k <- k + 1"
    "    k = sepLen"
    "  let rows: ref<list<list<string>>> = ref []"
    "  let row: ref<list<string>> = ref []"
    "  let cell = ref \"\""
    "  let mutable from = 0"
    "  let mutable i = 0"
    "  let mutable quoted = false"
    "  let endCell () ="
    "    row.Value <- cell.Value :: row.Value"
    "    cell.Value <- \"\""
    "  let endRow () ="
    "    rows.Value <- List.rev row.Value :: rows.Value"
    "    row.Value <- []"
    "  while i < n do"
    "    let b = String.byte text i"
    "    if quoted then"
    "      if b = quote then"
    "        if i + 1 < n && String.byte text (i + 1) = quote then"
    "          i <- i + 2"
    "        else"
    "          cell.Value <- cell.Value + String.replace (String.sub text from (i - from)) \"\\\"\\\"\" \"\\\"\""
    "          quoted <- false"
    "          i <- i + 1"
    "          from <- i"
    "      else"
    "        i <- i + 1"
    "    else if b = quote && from = i && cell.Value = \"\" then"
    "      quoted <- true"
    "      i <- i + 1"
    "      from <- i"
    "    else if sepLen > 0 && startsAt i then"
    "      cell.Value <- cell.Value + String.sub text from (i - from)"
    "      endCell ()"
    "      i <- i + sepLen"
    "      from <- i"
    "    else if b = u8 10 then"
    "      let piece = String.sub text from (i - from)"
    "      let line ="
    "        if String.endsWith \"\\r\" piece then String.sub piece 0 (String.length piece - 1) else piece"
    "      cell.Value <- cell.Value + line"
    "      endCell ()"
    "      endRow ()"
    "      i <- i + 1"
    "      from <- i"
    "    else"
    "      i <- i + 1"
    "  if from < n || cell.Value <> \"\" || not (List.isEmpty row.Value) then"
    "    let rest = String.sub text from (n - from)"
    "    cell.Value <- cell.Value + (if quoted then String.replace rest \"\\\"\\\"\" \"\\\"\" else rest)"
    "    endCell ()"
    "    endRow ()"
    "  List.rev rows.Value"
    ""
    "let private readInt (column: string) (cell: string) : result<int, string> ="
    "  let v: option<int> = Int.parse cell"
    "  match v with"
    "  | Some v -> Ok v"
    "  | None -> Error (column + \": expected an integer, got \\\"\" + cell + \"\\\"\")"
    ""
    "let private readFloat (column: string) (cell: string) : result<f64, string> ="
    "  let v: option<f64> = Float.parse cell"
    "  match v with"
    "  | Some v -> Ok v"
    "  | None -> Error (column + \": expected a number, got \\\"\" + cell + \"\\\"\")"
    ""
    "let private readBool (column: string) (cell: string) : result<bool, string> ="
    "  if cell = \"true\" then Ok true"
    "  else if cell = \"false\" then Ok false"
    "  else Error (column + \": expected true or false, got \\\"\" + cell + \"\\\"\")"
    ""
    "let private readText (column: string) (cell: string) : result<string, string> = Ok cell"
    ""
    "// an empty cell is None"
    "let private readOptional (read: string -> string -> result<'a, string>) (column: string) (cell: string) : result<option<'a>, string> ="
    "  if cell = \"\" then Ok None"
    "  else"
    "    match read column cell with"
    "    | Ok v -> Ok(Some v)"
    "    | Error e -> Error e"
    ""
    "// a cell as the file writes it: in quotes when it holds the separator, a quote or a line break"
    "let private quoted (s: string) : string ="
    "  if String.contains separator s || String.contains \"\\\"\" s || String.contains \"\\n\" s || String.contains \"\\r\" s then"
    "    \"\\\"\" + String.replace s \"\\\"\" \"\\\"\\\"\" + \"\\\"\""
    "  else s" ]

/// The module for the rows in `text`, read from `file`, with the options given: `separator`
/// (`,`), `hasHeaders` (`true`; `false` names the columns col1, col2, …), `types` overrides
/// columns' types by name. Error when the rows don't fit, or an option isn't right.
let provide (file: string) (text: string) (opts: list<string * string>) : result<string, string> =
  let opt (name: string) (dflt: string) =
    match List.tryFind (fun (n, _) -> n = name) opts with
    | Some(_, v) -> v
    | None -> dflt
  let separator = opt "separator" ","
  let hasHeaders = opt "hasHeaders" "true"
  if separator = "" then Error "separator: can't be empty"
  else if hasHeaders <> "true" && hasHeaders <> "false" then Error ("hasHeaders: '" + hasHeaders + "' isn't true or false")
  else
    match overridesOf (opt "types" "") with
    | Error e -> Error e
    | Ok overrides ->
      // a blank line isn't a row
      let rows = List.filter (fun (r: list<string>) -> r <> [ "" ]) (cells separator text)
      let (headers, data) =
        if hasHeaders = "true" then
          match rows with
          | [] -> ([], [])
          | h :: rest -> (h, rest)
        else
          let width = List.fold (fun w (r: list<string>) -> if List.length r > w then List.length r else w) 0 rows
          let rec names (i: int) = if i > width then [] else ("col" + string i) :: names (i + 1)
          (names 1, rows)
      let width = List.length headers
      if width = 0 then Error (file + ": no header line" + (if hasHeaders = "true" then "" else ": no rows"))
      else
        let tooWide = List.tryFind (fun (r: list<string>) -> List.length r > width) data
        match tooWide with
        | Some r -> Error (file + ": a row has " + string (List.length r) + " cells, the header " + string width)
        | None ->
          // each row's cells as an array, so a cell is found in one step however wide the file
          let cellsOf = List.map (fun (r: list<string>) -> Array.ofList r) data
          let at (i: int) (r: array<string>) = if i < Array.length r then r.[i] else ""
          let column (ih: int * string) : Column =
            let (i, h) = ih
            let values = List.map (at i) cellsOf
            let kind =
              match List.tryFind (fun (c, _) -> c = h) overrides with
              | Some(_, t) -> t
              | None -> kindOf values
            { header = h; kind = kind; optional = List.exists (fun (v: string) -> v = "") values }
          let columns = List.map column (index 0 headers)
          let rec twice (seen: Set<string>) (cs: list<Column>) : option<Column> =
            match cs with
            | [] -> None
            | c :: rest -> if Set.contains c.header seen then Some c else twice (Set.add c.header seen) rest
          match (List.tryFind (fun (c: Column) -> c.header = "") columns, twice Set.empty columns, Names.unnamed headers) with
          | (Some _, _, _) -> Error (file + ": a column has no name (hasHeaders = false names them col1, col2, …)")
          | (_, Some c, _) -> Error (file + ": two columns are named '" + c.header + "'")
          | (_, _, Some e) -> Error (file + ": " + e)
          | _ ->
            let fieldOf (c: Column) = Names.fieldName c.header
            let typeOf (c: Column) = if c.optional then "option<" + c.kind + ">" else c.kind
            let fields = List.map (fun (c: Column) -> fieldOf c + ": " + typeOf c + (if c.optional then " = None" else "")) columns
            let reader (c: Column) =
              let plain =
                match c.kind with
                | "int" -> "readInt"
                | "f64" -> "readFloat"
                | "bool" -> "readBool"
                | _ -> "readText"
              if c.optional then "readOptional " + plain else plain
            let binds =
              List.map (fun (ic: int * Column) ->
                let (i, c) = ic
                "        let! f" + string i + " = " + reader c + " " + Names.literal c.header + " (at " + string i + ")") (index 0 columns)
            let built = String.join "; " (List.map (fun (ic: int * Column) -> fieldOf (snd ic) + " = f" + string (fst ic)) (index 0 columns))
            let shown (ic: int * Column) =
              let (i, c) = ic
              let value = "r." + fieldOf c
              if c.optional then
                let inner = if c.kind = "string" then "quoted v" else "string v"
                "(match " + value + " with\n        | Some v -> " + inner + "\n        | None -> \"\")"
              else if c.kind = "string" then "quoted " + value
              else "string " + value
            let headerLiteral = String.join "; " (List.map (fun (c: Column) -> Names.literal c.header) columns)
            let headerLine = String.join separator headers
            let header = [ Names.oneLine ("// provided by csv 0.1 from " + file); Names.oneLine ("// input: " + file); "" ]
            let declaration =
              [ Names.oneLine ("/// From \"" + file + "\": ") + Names.clip 100 headerLine
                "type Row = { " + String.join "; " fields + " }"
                "" ]
            let rowText =
              List.concat [ [ "let private header : list<string> = [ " + headerLiteral + " ]"
                            ""
                            "// one row's cells as a Row, a cell missing at the end empty"
                            "let private row (n: int) (cs: list<string>) : result<Row, string> ="
                            "  let at (i: int) = if i < List.length cs then List.item i cs else \"\""
                            "  let r ="
                            "    if List.length cs > " + string width + " then Error (string (List.length cs) + \" cells, \" + string " + string width + " + \" columns\")"
                            "    else"
                            "      result {" ]
                          binds
                          [ "        return { " + built + " }"
                            "      }"
                            "  match r with"
                            "  | Ok v -> Ok v"
                            "  | Error e -> Error (\"row \" + string n + \": \" + e)"
                            "" ] ]
            let parseText =
              if hasHeaders = "true" then
                [ "/// Parses rows of this shape, the header line first."
                  "let parse (text: string) : result<list<Row>, string> ="
                  "  // a blank line isn't a row"
                  "  match List.filter (fun (r: list<string>) -> r <> [ \"\" ]) (cells text) with"
                  "  | [] -> Error \"no header line\""
                  "  | first :: rest ->"
                  "    if first <> header then"
                  "      Error (\"expected the header \" + String.join separator header + \", got \" + String.join separator first)"
                  "    else"
                  "      let rec go (n: int) (rows: list<list<string>>) (acc: list<Row>) : result<list<Row>, string> ="
                  "        match rows with"
                  "        | [] -> Ok(List.rev acc)"
                  "        | r :: more ->"
                  "          match row n r with"
                  "          | Ok v -> go (n + 1) more (v :: acc)"
                  "          | Error e -> Error e"
                  "      go 2 rest []"
                  "" ]
              else
                [ "/// Parses rows of this shape (the file has no header line)."
                  "let parse (text: string) : result<list<Row>, string> ="
                  "  let rec go (n: int) (rows: list<list<string>>) (acc: list<Row>) : result<list<Row>, string> ="
                  "    match rows with"
                  "    | [] -> Ok(List.rev acc)"
                  "    | r :: more ->"
                  "      match row n r with"
                  "      | Ok v -> go (n + 1) more (v :: acc)"
                  "      | Error e -> Error e"
                  "  // a blank line isn't a row"
                  "  go 1 (List.filter (fun (r: list<string>) -> r <> [ \"\" ]) (cells text)) []"
                  "" ]
            let printText =
              [ (if hasHeaders = "true" then "/// Prints rows, the header line first." else "/// Prints rows, with no header line.")
                "let print (rows: list<Row>) : string ="
                "  let line (r: Row) ="
                "    String.join separator [ " + String.join "\n      " (List.map shown (index 0 columns)) + " ]"
                (if hasHeaders = "true" then "  String.join \"\\n\" (String.join separator header :: List.map line rows) + \"\\n\""
                 else "  String.join \"\\n\" (List.map line rows) + \"\\n\"") ]
            Ok(String.join "\n" (List.concat [ header; declaration; readerText separator; [ "" ]; rowText; parseText; printText ]) + "\n")
