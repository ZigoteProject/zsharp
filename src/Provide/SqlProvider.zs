/// The sql provider (proposal 0001): a schema's `CREATE TABLE`s as a record per table, with the
/// table's name and columns in a module of the same name, as `zs provide sql <file>` prints.
/// SQLite's dialect first, and the common subset of Postgres's types: `INTEGER` is `int`,
/// `REAL` `f64`, `TEXT` `string`, `BLOB` `array<u8>`, `BOOLEAN` `bool`; a column is an option
/// unless `NOT NULL` or in the primary key. With `queries = "queries.sql"`, a file of named
/// queries (`-- name: GetUser :one` before each, as sqlc writes them) gives a module per query:
/// its text with `?` for each parameter, the parameters' names in order, a `Params` record typed
/// from the columns they're compared with (or inserted into), and a `Row` record for what it
/// selects, typed from the schema (`SELECT *` is the table's record). Joins, aliases and
/// expressions are read as far as the columns can be named; what can't be typed is a `string`.

/// A column: its name, its Z# type, and whether it can be null.
type Column = { name: string; ty: string; nullable: bool }

/// A table: its name and its columns in order.
type Table = { name: string; columns: list<Column> }

// the text without comments: -- to the line's end, and /* … */; the pieces kept joined once, and
// each comment's end found in the text itself (a copy per comment would be quadratic)
let private stripComments (s: string) : string =
  let n = String.length s
  let kept = Buffer.empty
  let mutable from = 0
  let mutable i = 0
  while i < n do
    if i + 1 < n && String.byte s i = u8 45 && String.byte s (i + 1) = u8 45 then
      Buffer.push (String.sub s from (i - from)) kept
      while i < n && String.byte s i <> u8 10 do
        i <- i + 1
      from <- i
    else if i + 1 < n && String.byte s i = u8 47 && String.byte s (i + 1) = u8 42 then
      Buffer.push (String.sub s from (i - from)) kept
      let k = String.indexOfFrom s "*/" (i + 2)
      i <- (if k < 0 then n else k + 2)
      from <- i
    else
      i <- i + 1
  Buffer.push (String.sub s from (n - from)) kept
  String.concat (Array.toList (Buffer.toArray kept))

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

/// A named query: its name, its kind (`one`, `many` or `exec`), its text with `?` for each
/// parameter, its parameters (name and type) in order, and its row's columns (name and type).
type Query = { name: string; kind: string; sql: string; parameters: list<string * string>; row: list<string * string> }

// the first table named after a keyword (FROM, INTO, UPDATE, JOIN), without an alias
let private tableAfter (keyword: string) (ws: list<string>) : list<string * string> =
  // every "KEYWORD table [AS alias]" in the statement: the table and the name it's known by
  let rec go (rest: list<string>) (acc: list<string * string>) =
    match rest with
    | k :: t :: more when upper k = keyword && not (Set.contains (upper t) constraintWords) ->
      let table = unquote (List.last (String.split "." t))
      match more with
      | a :: alias :: tail when upper a = "AS" -> go tail ((table, unquote alias) :: acc)
      | alias :: tail when not (List.contains (upper alias) [ "WHERE"; "SET"; "ON"; "JOIN"; "LEFT"; "RIGHT"; "INNER"; "OUTER"; "CROSS"; "GROUP"; "ORDER"; "LIMIT"; "VALUES"; "(" ]) && not (String.startsWith "(" alias) && String.length alias > 0 && Names.isIdent alias -> go tail ((table, unquote alias) :: acc)
      | _ -> go more ((table, table) :: acc)
    | _ :: more -> go more acc
    | [] -> List.rev acc
  go ws []

// a column's type in a table, or in the query's tables when unqualified
let private columnType (tables: list<Table>) (known: list<string * string>) (name: string) : option<Column> =
  let (qualifier, column) =
    match String.indexOf "." name with
    | Some i -> (Some(unquote (String.sub name 0 i)), unquote (String.sub name (i + 1) (String.length name - i - 1)))
    | None -> (None, unquote name)
  let candidates =
    match qualifier with
    | Some q ->
      match List.tryFind (fun (ta: string * string) -> snd ta = q || fst ta = q) known with
      | Some(t, _) -> List.filter (fun (x: Table) -> x.name = t) tables
      | None -> []
    | None -> List.filter (fun (x: Table) -> List.exists (fun (ta: string * string) -> fst ta = x.name) known) tables
  List.tryPick (fun (t: Table) -> List.tryFind (fun (c: Column) -> c.name = column) t.columns) candidates

let private typeText (c: Column) = if c.nullable then "option<" + c.ty + ">" else c.ty

// the parameters in a statement's words, in order: :name, $n, @name or ?, each typed by the
// column it follows an operator of (col = :p, col IN (:p)), else string; INSERT's VALUES by position
let private parametersOf (tables: list<Table>) (known: list<string * string>) (ws: list<string>) : list<string * string> =
  let isParam (w: string) = w = "?" || String.startsWith ":" w || String.startsWith "$" w || String.startsWith "@" w
  let nameOf (i: int) (w: string) =
    let bare = String.trim (String.replace (String.replace (String.replace w ")" "") "(" "") "," "")
    if bare = "?" || String.startsWith "$" bare then "p" + string (i + 1) else String.sub bare 1 (String.length bare - 1)
  // INSERT INTO t (a, b) VALUES (?, ?): the columns, in order
  let inserted =
    match ws with
    | i :: into :: _ when upper i = "INSERT" && upper into = "INTO" ->
      match String.indexOf "(" (String.join " " ws) with
      | Some k ->
        let text = String.join " " ws
        let close = Option.defaultValue (String.length text) (String.indexOf ")" (String.sub text k (String.length text - k)))
        List.map (fun (c: string) -> unquote (String.trim c)) (String.split "," (String.sub text (k + 1) (close - 1)))
      | None -> []
    | _ -> []
  let ops = [ "="; "<"; ">"; "<="; ">="; "<>"; "!="; "IN"; "LIKE"; "IS" ]
  let rec go (i: int) (before: list<string>) (rest: list<string>) (acc: list<string * string>) =
    match rest with
    | [] -> List.rev acc
    | w :: more ->
      // a word may hold several parameters: (?, ?) or :a,:b
      let pieces = List.filter isParam (List.map String.trim (String.split "," (String.replace (String.replace w "(" "") ")" "")))
      if List.isEmpty pieces then go i (w :: before) more acc
      else
        let typed (k: int) (piece: string) =
          let name = nameOf (i + k) piece
          let byColumn =
            match before with
            | op :: col :: _ when List.contains (upper op) ops -> columnType tables known col
            | _ -> None
          let byInsert = if List.length inserted > i + k then columnType tables known (List.item (i + k) inserted) else None
          match (byColumn, byInsert) with
          | (Some c, _) -> (name, typeText c)
          | (None, Some c) -> (name, typeText c)
          | _ -> (name, "string")
        let found = List.mapi typed pieces
        go (i + List.length pieces) (w :: before) more (List.append (List.rev found) acc)
  go 0 [] ws []

// the row a SELECT gives: its columns typed from the schema; * is a table's whole record
let private rowOf (tables: list<Table>) (known: list<string * string>) (ws: list<string>) : result<list<string * string>, string> =
  let text = String.join " " ws
  let upperText = upper text
  match (String.indexOf "SELECT " upperText, String.indexOf " FROM " upperText) with
  | (Some a, Some b) when b > a ->
    let items = List.map String.trim (splitTop (u8 44) (String.sub text (a + 7) (b - a - 7)))
    let one (item: string) : result<list<string * string>, string> =
      let parts = List.filter (fun (w: string) -> w <> "") (String.split " " item)
      let (expr, alias) =
        match List.rev parts with
        | alias :: a :: rest when upper a = "AS" -> (String.join " " (List.rev rest), Some(unquote alias))
        | alias :: rest when List.length rest > 0 && Names.isIdent alias && not (String.contains "." alias) && not (String.endsWith ")" (List.head rest)) && List.length rest = 1 && Names.isIdent (List.head rest) -> (List.head rest, Some(unquote alias))
        | _ -> (item, None)
      if expr = "*" || String.endsWith ".*" expr then
        let wanted = if expr = "*" then None else Some(unquote (String.sub expr 0 (String.length expr - 2)))
        let picked = List.filter (fun (ta: string * string) -> match wanted with | Some q -> snd ta = q || fst ta = q | None -> true) known
        Ok(List.collect (fun (ta: string * string) ->
          match List.tryFind (fun (t: Table) -> t.name = fst ta) tables with
          | Some t -> List.map (fun (c: Column) -> (c.name, typeText c)) t.columns
          | None -> []) picked)
      else
        match columnType tables known expr with
        | Some c -> Ok [ (Option.defaultValue (unquote (List.last (String.split "." expr))) alias, typeText c) ]
        | None ->
          let u = upper expr
          let counted = String.startsWith "COUNT(" u || String.startsWith "SUM(" u || String.startsWith "TOTAL(" u || String.startsWith "LENGTH(" u
          match alias with
          | Some a -> Ok [ (a, (if counted then "int" else "string")) ]
          | None -> if String.contains "(" expr then Error $"'{expr}' needs a name: write it AS name" else Error $"no column '{expr}' in {String.join ", " (List.map fst known)}"
    let rec go (items: list<string>) (acc: list<string * string>) =
      match items with
      | [] -> Ok(List.rev acc)
      | item :: rest ->
        match one item with
        | Ok cols -> go rest (List.append (List.rev cols) acc)
        | Error e -> Error e
    go items []
  | _ -> Ok []

/// The named queries of a file: `-- name: GetUser :one` (or `:many`, `:exec`), then the statement.
let queries (tables: list<Table>) (text: string) : result<list<Query>, string> =
  let lines = String.split "\n" text
  // each name line with the statement lines up to the next
  let rec groups (ls: list<string>) (current: option<string * string * list<string>>) (acc: list<string * string * string>) =
    let finish () =
      match current with
      | Some(n, k, body) -> (n, k, String.trim (String.join " " (List.rev body))) :: acc
      | None -> acc
    match ls with
    | [] -> List.rev (finish ())
    | l :: rest ->
      let t = String.trim l
      if String.startsWith "-- name:" t || String.startsWith "--name:" t then
        let spec = String.trim (String.sub t (Option.get (String.indexOf ":" t) + 1) (String.length t - Option.get (String.indexOf ":" t) - 1))
        let ws = List.filter (fun (w: string) -> w <> "") (String.split " " spec)
        let name = if List.isEmpty ws then "" else List.head ws
        let kind = if List.length ws > 1 && String.startsWith ":" (List.item 1 ws) then String.sub (List.item 1 ws) 1 (String.length (List.item 1 ws) - 1) else "many"
        groups rest (Some(name, kind, [])) (finish ())
      else if String.startsWith "--" t then groups rest current acc
      else
        match current with
        | Some(n, k, body) -> groups rest (Some(n, k, t :: body)) acc
        | None -> groups rest current acc
  let rec build (gs: list<string * string * string>) (acc: list<Query>) =
    match gs with
    | [] -> Ok(List.rev acc)
    | (name, kind, stmt) :: rest ->
      let stmt = String.trim (String.replace (stripComments stmt) ";" "")
      if not (Names.isIdent name) || not (String.toUpper (String.sub name 0 1) = String.sub name 0 1) then Error $"query '{name}': a name is a capitalized word, as GetUser"
      else if not (List.contains kind [ "one"; "many"; "exec" ]) then Error $"query {name}: ':{kind}' isn't :one, :many or :exec"
      else
        let ws = words stmt
        let known = List.concat [ tableAfter "FROM" ws; tableAfter "INTO" ws; tableAfter "UPDATE" ws; tableAfter "JOIN" ws ]
        let unknown = List.filter (fun (ta: string * string) -> not (List.exists (fun (t: Table) -> t.name = fst ta) tables)) known
        if List.isEmpty known then Error $"query {name}: no table after FROM, INTO or UPDATE"
        else if not (List.isEmpty unknown) then Error $"query {name}: no table '{fst (List.head unknown)}' in the schema ({String.join ", " (List.map (fun (t: Table) -> t.name) tables)})"
        else
          match rowOf tables known ws with
          | Error e -> Error $"query {name}: {e}"
          | Ok row ->
            let parameters = parametersOf tables known ws
            // the text with ? for each parameter
            // a word's parameters, each a ?: (:a, :b) is (?, ?)
            let placeholder (piece: string) =
              let b = String.trim (String.replace (String.replace piece "(" "") ")" "")
              if String.startsWith ":" b || String.startsWith "$" b || String.startsWith "@" b then String.replace piece b "?" else piece
            let sql = String.join " " (List.map (fun (w: string) -> String.join "," (List.map placeholder (String.split "," w))) ws)
            build rest ({ name = name; kind = kind; sql = sql; parameters = parameters; row = row } :: acc)
  build (groups lines None []) []

/// The options `zs provide sql` takes.
let options : list<string> = [ "types"; "queries" ]

/// The module for the schema in `text`, read from `file`: `types = "users.email:string"`
/// overrides a column's type by table and column, `queries = "queries.sql"` (a path beside the
/// schema, read by `readQueries`) adds a module per named query. Error when a statement doesn't
/// read, or no table is declared.
let provideWith (file: string) (text: string) (opts: list<string * string>) (queryText: option<string * string>) : result<string, string> =
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
    // a column's name is a field's
    let unnamed = Names.unnamed (List.collect (fun (t: Table) -> List.map (fun (c: Column) -> c.name) t.columns) ts)
    let queryModules =
      match (unnamed, queryText) with
      | (Some e, _) -> Error (file + ": " + e)
      | (None, None) -> Ok []
      | (None, Some(qfile, qtext)) ->
        match queries ts qtext with
        | Error e -> Error (qfile + ": " + e)
        | Ok qs ->
          let literal = Names.literal
          let one (q: Query) : list<string> =
            let field (nt: string * string) = Names.fieldName (fst nt) + ": " + snd nt + (if String.startsWith "option<" (snd nt) then " = None" else "")
            List.concat [ [ Names.oneLine ("/// From \"" + qfile + "\": " + q.name + " (:" + q.kind + "): " + q.sql)
                  "module " + q.name + " ="
                  "  /// The query, with ? where each parameter goes, in order."
                  "  let sql = " + literal q.sql
                  "  /// :one, :many or :exec: what it gives."
                  "  let kind = " + literal q.kind
                  "  /// Its parameters' names, in order."
                  "  let parameters = [ " + String.join "; " (List.map (fun (nt: string * string) -> literal (fst nt)) q.parameters) + " ]" ]
                (if List.isEmpty q.parameters then [] else [ "  /// Its parameters, typed from the columns they meet."; "  type Params = { " + String.join "; " (List.map field q.parameters) + " }" ])
                (if List.isEmpty q.row then [] else [ "  /// A row it gives."; "  type Row = { " + String.join "; " (List.map field q.row) + " }" ])
                [ "" ] ]
          // a parameter's or a column's name is a field's
          match Names.unnamed (List.collect (fun (q: Query) -> List.append (List.map fst q.parameters) (List.map fst q.row)) qs) with
          | Some e -> Error (qfile + ": " + e)
          | None -> Ok(List.collect one qs)
    match queryModules with
    | Error e -> Error e
    | Ok queryLines ->
      let decl (t: Table) : list<string> =
        let typeName = Names.typeName t.name
        let field (c: Column) =
          let ty =
            match List.tryFind (fun (k, _) -> k = t.name + "." + c.name) overrides with
            | Some(_, over) -> over
            | None -> c.ty
          if c.nullable then Names.fieldName c.name + ": option<" + ty + "> = None" else Names.fieldName c.name + ": " + ty
        let literal = Names.literal
        [ Names.oneLine ("/// From \"" + file + "\": " + t.name + " (" + String.join ", " (List.map (fun (c: Column) -> c.name) t.columns) + ")")
          "type " + typeName + " = { " + String.join "; " (List.map field t.columns) + " }"
          ""
          "module " + typeName + " ="
          "  /// The table's name."
          "  let table = " + literal t.name
          "  /// Its columns, in order."
          "  let columns = [ " + String.join "; " (List.map (fun (c: Column) -> literal c.name) t.columns) + " ]"
          "" ]
      let inputs = List.append [ Names.oneLine ("// input: " + file) ] (match queryText with | Some(q, _) -> [ Names.oneLine ("// input: " + q) ] | None -> [])
      let header = List.concat [ [ Names.oneLine ("// provided by sql 0.1 from " + file) ]; inputs; [ "" ] ]
      Ok(String.join "\n" (List.concat [ header; List.collect decl ts; queryLines ]))

/// As `provideWith`, the `queries` option's file read from beside the schema: `file` is the
/// schema's path as the import wrote it, relative to `dir` (the importing file's directory).
let provide (dir: string) (file: string) (text: string) (opts: list<string * string>) : result<string, string> =
  match List.tryFind (fun (n, _) -> n = "queries") opts with
  | Some(_, q) when q <> "" ->
    let schemaDir = Path.getDirectoryName (Path.combine dir file)
    let path = Path.combine schemaDir q
    match Input.read path with
    | Ok qtext -> provideWith file text opts (Some(q, qtext))
    | Error "not found" -> Error $"queries: {q} not found beside {file}"
    | Error why -> Error $"queries: {q} {why}"
  | _ -> provideWith file text opts None
