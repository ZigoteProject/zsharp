/// The sql provider (proposal 0001): a schema's `CREATE TABLE`s as a record per table, with the
/// table's name and columns in a module of the same name, as `zs provide sql <file>` prints.
/// SQLite's dialect first, and the common subset of Postgres's types: `INTEGER` is `int`,
/// `REAL` `f64`, `TEXT` `string`, `BLOB` `array<u8>`, `BOOLEAN` `bool`; a column is an option
/// unless `NOT NULL` or in the primary key. Typed queries wait for a SQL parser (the proposal's
/// open question).

/// A column: its name, its Z# type, and whether it can be null.
type Column = { name: string; ty: string; nullable: bool }

/// A table: its name and its columns in order.
type Table = { name: string; columns: list<Column> }

// the text without comments: -- to the line's end, and /* … */
let private stripComments (s: string) : string =
  let n = String.length s
  let mutable out = ""
  let mutable from = 0
  let mutable i = 0
  while i < n do
    if i + 1 < n && String.byte s i = u8 45 && String.byte s (i + 1) = u8 45 then
      out <- out + String.sub s from (i - from)
      while i < n && String.byte s i <> u8 10 do
        i <- i + 1
      from <- i
    else if i + 1 < n && String.byte s i = u8 47 && String.byte s (i + 1) = u8 42 then
      out <- out + String.sub s from (i - from)
      match String.indexOf "*/" (String.sub s i (n - i)) with
      | Some k -> i <- i + k + 2
      | None -> i <- n
      from <- i
    else
      i <- i + 1
  out + String.sub s from (n - from)

// the pieces of `s` split at `sep` outside parentheses and quotes
let private splitTop (sep: u8) (s: string) : list<string> =
  let n = String.length s
  let pieces = ref []
  let mutable depth = 0
  let mutable quote = u8 0
  let mutable from = 0
  let mutable i = 0
  while i < n do
    let b = String.byte s i
    if quote <> u8 0 then
      if b = quote then quote <- u8 0
    else if b = u8 39 || b = u8 34 || b = u8 96 then quote <- b
    else if b = u8 40 then depth <- depth + 1
    else if b = u8 41 then depth <- depth - 1
    else if b = sep && depth = 0 then
      pieces.Value <- String.sub s from (i - from) :: pieces.Value
      from <- i + 1
    i <- i + 1
  List.rev (String.sub s from (n - from) :: pieces.Value)

// words separated by spaces, each parenthesized run one word with its parentheses
let private words (s: string) : list<string> =
  List.filter (fun (w: string) -> w <> "") (List.map String.trim (splitTop (u8 32) (String.replace (String.replace (String.replace s "\n" " ") "\t" " ") "\r" " ")))

// a name without its quotes: "users", `users`, [users], users
let private unquote (w: string) : string =
  let n = String.length w
  if n >= 2 then
    let a = String.byte w 0
    let z = String.byte w (n - 1)
    if (a = u8 34 && z = u8 34) || (a = u8 96 && z = u8 96) || (a = u8 91 && z = u8 93) || (a = u8 39 && z = u8 39) then String.sub w 1 (n - 2) else w
  else w

let private upper (w: string) = String.toUpper w

let private constraintWords : Set<string> =
  Set.ofList [ "PRIMARY"; "NOT"; "NULL"; "UNIQUE"; "CHECK"; "DEFAULT"; "REFERENCES"; "COLLATE"; "GENERATED"; "CONSTRAINT"; "AUTOINCREMENT"; "AUTO_INCREMENT"; "ON" ]

/// The Z# type for a SQL type's first word, `string` for one not known.
let typeOf (sqlType: string) : string =
  // the type's name without a length: VARCHAR(255) is VARCHAR
  let t =
    match String.indexOf "(" sqlType with
    | Some i -> String.sub sqlType 0 i
    | None -> sqlType
  match upper t with
  | "INT" -> "int"
  | "INTEGER" -> "int"
  | "SMALLINT" -> "int"
  | "BIGINT" -> "int"
  | "TINYINT" -> "int"
  | "MEDIUMINT" -> "int"
  | "INT2" -> "int"
  | "INT4" -> "int"
  | "INT8" -> "int"
  | "SERIAL" -> "int"
  | "BIGSERIAL" -> "int"
  | "REAL" -> "f64"
  | "FLOAT" -> "f64"
  | "FLOAT4" -> "f64"
  | "FLOAT8" -> "f64"
  | "DOUBLE" -> "f64"
  | "NUMERIC" -> "f64"
  | "DECIMAL" -> "f64"
  | "BLOB" -> "array<u8>"
  | "BYTEA" -> "array<u8>"
  | "BOOL" -> "bool"
  | "BOOLEAN" -> "bool"
  | _ -> "string"

// a column definition's words: its name, type and whether it allows null
let private column (ws: list<string>) : option<Column> =
  match ws with
  | [] -> None
  | name :: rest ->
    let rec typeWords (acc: list<string>) (more: list<string>) =
      match more with
      | w :: tail when not (Set.contains (upper w) constraintWords) -> typeWords (List.append acc [ w ]) tail
      | _ -> (acc, more)
    let (tyWords, constraints) = typeWords [] rest
    let text = upper (String.join " " constraints)
    let notNull = String.contains "NOT NULL" text || String.contains "PRIMARY KEY" text
    let ty = if List.isEmpty tyWords then "string" else typeOf (List.head tyWords)
    Some { name = unquote name; ty = ty; nullable = not notNull }

/// The tables of a schema's `CREATE TABLE` statements, in order.
let tables (text: string) : result<list<Table>, string> =
  let statements = List.map String.trim (splitTop (u8 59) (stripComments text))
  let table (stmt: string) : result<option<Table>, string> =
    let ws = words stmt
    match ws with
    | create :: tableWord :: rest when upper create = "CREATE" && (upper tableWord = "TABLE" || upper tableWord = "TEMP" || upper tableWord = "TEMPORARY") ->
      // CREATE [TEMP] TABLE [IF NOT EXISTS] name (…)
      let rest1 = if upper tableWord <> "TABLE" then List.tail rest else rest
      let rest2 =
        match rest1 with
        | i :: n :: e :: tail when upper i = "IF" && upper n = "NOT" && upper e = "EXISTS" -> tail
        | _ -> rest1
      match rest2 with
      | [] -> Error "CREATE TABLE without a name"
      | first :: tail ->
        // the name and the body may touch: users(id …)
        let (name, body) =
          match String.indexOf "(" first with
          | Some i -> (String.sub first 0 i, String.join " " (String.sub first i (String.length first - i) :: tail))
          | None -> (first, String.join " " tail)
        let tableName = unquote (List.head (String.split "." name) |> fun h -> if List.length (String.split "." name) > 1 then List.item 1 (String.split "." name) else h)
        if not (String.startsWith "(" body) then Error $"CREATE TABLE {tableName}: expected its columns in parentheses"
        else
          let inner =
            match String.lastIndexOf ")" body with
            | Some k -> String.sub body 1 (k - 1)
            | None -> String.sub body 1 (String.length body - 1)
          let items = List.map words (splitTop (u8 44) inner)
          let isConstraint (ws: list<string>) =
            match ws with
            | w :: _ -> List.contains (upper w) [ "PRIMARY"; "FOREIGN"; "UNIQUE"; "CHECK"; "CONSTRAINT"; "KEY"; "INDEX" ]
            | [] -> true
          let columns = List.choose column (List.filter (fun ws -> not (isConstraint ws)) items)
          // PRIMARY KEY (a, b) at the table's level: those columns aren't null
          let keyed =
            List.collect (fun (ws: list<string>) ->
              let text = upper (String.join " " ws)
              if String.startsWith "PRIMARY KEY" text || String.startsWith "CONSTRAINT" text && String.contains "PRIMARY KEY" text then
                match String.indexOf "(" (String.join " " ws) with
                | Some i ->
                  let joined = String.join " " ws
                  let inside = String.sub joined (i + 1) (String.length joined - i - 1)
                  let upTo = match String.indexOf ")" inside with | Some k -> String.sub inside 0 k | None -> inside
                  List.map (fun (c: string) -> unquote (String.trim c)) (String.split "," upTo)
                | None -> []
              else []) (List.filter isConstraint items)
          let columns = List.map (fun (c: Column) -> if List.contains c.name keyed then { c with nullable = false } else c) columns
          if List.isEmpty columns then Error $"CREATE TABLE {tableName}: no columns" else Ok(Some { name = tableName; columns = columns })
    | _ -> Ok None
  let rec go (stmts: list<string>) (acc: list<Table>) =
    match stmts with
    | [] -> Ok(List.rev acc)
    | s :: rest ->
      match table s with
      | Error e -> Error e
      | Ok(Some t) -> go rest (t :: acc)
      | Ok None -> go rest acc
  go statements []

/// The options `zs provide sql` takes.
let options : list<string> = [ "types" ]

/// The module for the schema in `text`, read from `file`: `types = "users.email:string"`
/// overrides a column's type by table and column. Error when a statement doesn't read, or no
/// table is declared.
let provide (file: string) (text: string) (opts: list<string * string>) : result<string, string> =
  let overrides =
    match List.tryFind (fun (n, _) -> n = "types") opts with
    | Some(_, v) when v <> "" ->
      List.choose (fun (item: string) ->
        match String.indexOf ":" item with
        | Some i -> Some(String.trim (String.sub item 0 i), String.trim (String.sub item (i + 1) (String.length item - i - 1)))
        | None -> None) (String.split "," v)
    | _ -> []
  match tables text with
  | Error e -> Error (file + ": " + e)
  | Ok [] -> Error (file + ": no CREATE TABLE")
  | Ok ts ->
    let decl (t: Table) : list<string> =
      let typeName = Names.typeName t.name
      let field (c: Column) =
        let ty =
          match List.tryFind (fun (k, _) -> k = t.name + "." + c.name) overrides with
          | Some(_, over) -> over
          | None -> c.ty
        if c.nullable then Names.fieldName c.name + ": option<" + ty + "> = None" else Names.fieldName c.name + ": " + ty
      let literal (s: string) = "\"" + String.replace s "\"" "\\\"" + "\""
      [ "/// From \"" + file + "\": " + t.name + " (" + String.join ", " (List.map (fun (c: Column) -> c.name) t.columns) + ")"
        "type " + typeName + " = { " + String.join "; " (List.map field t.columns) + " }"
        ""
        "module " + typeName + " ="
        "  /// The table's name."
        "  let table = " + literal t.name
        "  /// Its columns, in order."
        "  let columns = [ " + String.join "; " (List.map (fun (c: Column) -> literal c.name) t.columns) + " ]"
        "" ]
    let header = [ "// provided by sql 0.1 from " + file; "// input: " + file; "" ]
    Ok(String.join "\n" (List.append header (List.collect decl ts)))
