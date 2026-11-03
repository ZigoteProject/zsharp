/// The svd provider (proposal 0001): a microcontroller's SVD file (the vendor's description of
/// its peripherals) as a module per peripheral, each register a `[<Bits>]` record whose defaults
/// are its reset value, with a module of the same name holding its address and the access the
/// file allows (`read`, `write`, `modify`), as `zs provide svd <file>` prints. A field is a
/// `bool` when one bit wide, else a `u8`, `u16` or `u32` with `[<Width n>]`; a peripheral derived
/// from another gets its own copy of the types; a register array (`dim`) becomes numbered
/// registers. Enumerated values are read as integers for now.

/// A register's field: its name, description, lowest bit and width.
type Field = { name: string; description: string; offset: int; width: int }

/// A register: its name, description, offset from the peripheral's base, size in bits, access
/// (read-only, write-only or read-write), reset value and fields.
type Register = { name: string; description: string; offset: int; size: int; access: string; reset: int; fields: list<Field> }

/// A peripheral: its name, description, base address and registers.
type Peripheral = { name: string; description: string; baseAddress: int; registers: list<Register> }

/// A number as an SVD writes it: 0x1F, #0101 or 0b0101, or decimal.
let number (s: string) : option<int> =
  let t = String.trim s
  let n = String.length t
  if n = 0 then None
  else if n > 2 && (String.startsWith "0x" t || String.startsWith "0X" t) then Int.parseRadix 16 (String.sub t 2 (n - 2))
  else if n > 1 && String.startsWith "#" t then Int.parseRadix 2 (String.replace (String.sub t 1 (n - 1)) "x" "0")
  else if n > 2 && (String.startsWith "0b" t || String.startsWith "0B" t) then Int.parseRadix 2 (String.sub t 2 (n - 2))
  else Int.parse t

let private text (name: string) (e: Xml.Element) : string = Option.defaultValue "" (Xml.childText name e)

let private numberIn (name: string) (dflt: int) (e: Xml.Element) : int =
  match Xml.childText name e with
  | Some s -> Option.defaultValue dflt (number s)
  | None -> dflt

// one line of a description: the vendor's line breaks and runs of spaces collapsed
let private oneLine (s: string) : string =
  let ws = List.filter (fun (w: string) -> w <> "") (String.split " " (String.replace (String.replace (String.replace s "\n" " ") "\r" " ") "\t" " "))
  String.join " " ws

// a name's words (split at _ and anything that isn't a letter or digit) in PascalCase, each
// word's rest in lower case: GPIOA is Gpioa, ADC_Common AdcCommon, CR1 Cr1
let private pascal (name: string) : string =
  let n = String.length name
  let mutable out = ""
  let mutable i = 0
  let mutable newWord = true
  while i < n do
    let b = String.byte name i
    let c = String.sub name i 1
    let isLetter = (b >= u8 65 && b <= u8 90) || (b >= u8 97 && b <= u8 122)
    let isDigit = b >= u8 48 && b <= u8 57
    if isLetter || isDigit then
      out <- out + (if newWord then String.toUpper c else String.toLower c)
      newWord <- isDigit && false
    else
      newWord <- true
    i <- i + 1
  Names.typeName out

// a field's name: lower case, in backticks when it isn't a name
let private fieldName (name: string) : string = Names.fieldName (String.toLower name)

// the indexes a dim's names take: dimIndex as "0-3" or "A,B,C", else 0 .. dim-1
let private dimIndexes (dim: int) (index: string) : list<string> =
  let rec range (a: int) (b: int) = if a > b then [] else string a :: range (a + 1) b
  if index = "" then range 0 (dim - 1)
  else if String.contains "," index then List.map String.trim (String.split "," index)
  else
    match String.indexOf "-" index with
    | Some i ->
      let a: option<int> = Int.parse (String.sub index 0 i)
      let b: option<int> = Int.parse (String.sub index (i + 1) (String.length index - i - 1))
      match (a, b) with
      | (Some a, Some b) -> range a b
      | _ -> range 0 (dim - 1)
    | None -> range 0 (dim - 1)

let private fieldOf (e: Xml.Element) : option<Field> =
  let name = text "name" e
  if name = "" then None
  else
    // bitOffset and bitWidth, or bitRange [msb:lsb], or lsb and msb
    let (offset, width) =
      match (Xml.childText "bitOffset" e, Xml.childText "bitRange" e, Xml.childText "lsb" e) with
      | (Some o, _, _) -> (Option.defaultValue 0 (number o), numberIn "bitWidth" 1 e)
      | (None, Some r, _) ->
        let inner = String.replace (String.replace r "[" "") "]" ""
        match String.indexOf ":" inner with
        | Some i ->
          let msb = Option.defaultValue 0 (number (String.sub inner 0 i))
          let lsb = Option.defaultValue 0 (number (String.sub inner (i + 1) (String.length inner - i - 1)))
          (lsb, msb - lsb + 1)
        | None -> (0, 1)
      | (None, None, Some l) ->
        let lsb = Option.defaultValue 0 (number l)
        (lsb, numberIn "msb" lsb e - lsb + 1)
      | _ -> (0, 1)
    Some { name = name; description = oneLine (text "description" e); offset = offset; width = max 1 width }

// a register element, expanded by its dim when it has one; the defaults are the peripheral's
let private registersOf (size: int) (access: string) (reset: int) (e: Xml.Element) : list<Register> =
  let name = text "name" e
  let fields =
    match Xml.child "fields" e with
    | Some fs -> List.choose fieldOf (Xml.children "field" fs)
    | None -> []
  let one (n: string) (offset: int) : Register =
    { name = n
      description = oneLine (text "description" e)
      offset = offset
      size = numberIn "size" size e
      access = Option.defaultValue access (Xml.childText "access" e)
      reset = numberIn "resetValue" reset e
      fields = List.sortBy (fun (f: Field) -> f.offset) fields }
  let offset = numberIn "addressOffset" 0 e
  match Xml.childText "dim" e with
  | Some d when Option.defaultValue 0 (number d) > 1 ->
    let dim = Option.defaultValue 1 (number d)
    let step = numberIn "dimIncrement" (size / 8) e
    let indexes = dimIndexes dim (text "dimIndex" e)
    let rec go (i: int) (ix: list<string>) =
      match ix with
      | [] -> []
      | k :: rest -> one (String.replace name "%s" k) (offset + i * step) :: go (i + 1) rest
    go 0 indexes
  | _ -> [ one (String.replace name "%s" "") offset ]

/// The peripherals of a device, derived ones with their own registers.
let peripherals (root: Xml.Element) : result<list<Peripheral>, string> =
  if Xml.nameOf root <> "device" then Error $"the root element is <{Xml.nameOf root}>, not <device>"
  else
    let size = numberIn "size" 32 root
    let access = Option.defaultValue "read-write" (Xml.childText "access" root)
    let reset = numberIn "resetValue" 0 root
    let elements =
      match Xml.child "peripherals" root with
      | Some ps -> Xml.children "peripheral" ps
      | None -> []
    // each as written, with what it derives from
    let own (e: Xml.Element) : Peripheral * option<string> =
      let pSize = numberIn "size" size e
      let pAccess = Option.defaultValue access (Xml.childText "access" e)
      let pReset = numberIn "resetValue" reset e
      let registers =
        match Xml.child "registers" e with
        | Some rs -> List.collect (registersOf pSize pAccess pReset) (Xml.children "register" rs)
        | None -> []
      ({ name = text "name" e; description = oneLine (text "description" e); baseAddress = numberIn "baseAddress" 0 e; registers = registers }, Xml.attr "derivedFrom" e)
    let all = List.map own elements
    let resolve (pd: Peripheral * option<string>) : result<Peripheral, string> =
      let (p, from) = pd
      match from with
      | None -> Ok p
      | Some baseName ->
        match List.tryFind (fun (bd: Peripheral * option<string>) -> (fst bd).name = baseName) all with
        | Some(b, _) ->
          Ok { p with
                 description = (if p.description = "" then b.description else p.description)
                 registers = (if List.isEmpty p.registers then b.registers else p.registers) }
        | None -> Error $"{p.name} is derived from {baseName}, which isn't in the file"
    let rec go (ps: list<Peripheral * option<string>>) (acc: list<Peripheral>) =
      match ps with
      | [] -> Ok(List.rev acc)
      | pd :: rest ->
        match resolve pd with
        | Ok p -> go rest (p :: acc)
        | Error e -> Error e
    go all []

/// The options `zs provide svd` takes.
let options : list<string> = [ "only" ]

// a register's record and module
let private registerText (p: Peripheral) (r: Register) : list<string> =
  let typeName = pascal r.name
  let bits = if r.size = 8 then 8 else 32
  let reads = r.access <> "write-only"
  let writes = r.access <> "read-only"
  let mask (w: int) = if w >= 63 then -1 else (1 <<< w) - 1
  let valueOf (f: Field) = (r.reset >>> f.offset) &&& mask f.width
  // fields in order, each placed by [<Bit n>] where a gap or an overlap precedes it; one
  // overlapping an earlier field is left out, named in a comment
  let rec place (fs: list<Field>) (next: int) (acc: list<string>) (skipped: list<string>) =
    match fs with
    | [] -> (List.rev acc, List.rev skipped)
    | f :: rest ->
      if f.offset < next || f.offset + f.width > bits then place rest next acc (f.name :: skipped)
      else
        let natural = if f.width = 1 then 1 else if f.width <= 8 then 8 else if f.width <= 16 then 16 else 32
        let ty = if f.width = 1 then "bool" else if f.width <= 8 then "u8" else if f.width <= 16 then "u16" else "u32"
        let v = valueOf f
        let dflt = if f.width = 1 then (if v <> 0 then "true" else "false") else ty + " " + string v
        let placed = List.append (if f.offset <> next then [ $"Bit {f.offset}" ] else []) (if f.width > 1 && f.width < natural then [ $"Width {f.width}" ] else [])
        let attrs = if List.isEmpty placed then "" else "[<" + String.join "; " placed + ">] "
        let doc = if f.description = "" then "" else "/// " + f.description + "\n      "
        place rest (f.offset + f.width) ((doc + attrs + fieldName f.name + ": " + ty + " = " + dflt) :: acc) skipped
  let (fieldLines, skipped) = place r.fields 0 [] []
  let fieldLines = if List.isEmpty fieldLines then [ $"value: u{bits} = u{bits} {r.reset &&& mask bits}" ] else fieldLines
  let address = p.baseAddress + r.offset
  let conv = string bits
  List.concat [ [ $"  /// {r.description} ({r.name}, offset 0x{r.offset:x}, {r.access}, reset 0x{r.reset:x})"
        $"  [<Bits {bits}>]"
        $"  type {typeName} ="
        "    { " + String.join "\n      " fieldLines + " }" ]
      (if List.isEmpty skipped then [] else [ "  // left out, overlapping a field before it: " + String.join ", " skipped ])
      [ ""
        $"  module {typeName} ="
        $"    let private address = usize 0x{address:x}" ]
      (if reads then [ "    /// The register's value."; $"    let read () : {typeName} = Bits.ofU{conv} (Mmio.read{conv} address)" ] else [])
      (if writes then [ "    /// Writes a value."; $"    let write (r: {typeName}) = Mmio.write{conv} address (Bits.toU{conv} r)" ] else [])
      (if reads && writes then [ "    /// Reads, changes and writes."; $"    let modify (f: {typeName} -> {typeName}) = write (f (read ()))" ] else [])
      [ "" ] ]

/// The module for the device in `text`, read from `file`: a module per peripheral, or those
/// `only = "GPIOA,RCC"` names. Error when the file isn't an SVD, or names a peripheral it
/// doesn't have.
let provide (file: string) (text: string) (opts: list<string * string>) : result<string, string> =
  let only =
    match List.tryFind (fun (n, _) -> n = "only") opts with
    | Some(_, v) when String.trim v <> "" -> List.map (fun (s: string) -> String.toUpper (String.trim s)) (String.split "," v)
    | _ -> []
  match Xml.parse text with
  | Error e -> Error (file + ": " + e)
  | Ok root ->
    match peripherals root with
    | Error e -> Error (file + ": " + e)
    | Ok ps ->
      let chosen = if List.isEmpty only then ps else List.filter (fun (p: Peripheral) -> List.contains (String.toUpper p.name) only) ps
      let missing = List.filter (fun (n: string) -> not (List.exists (fun (p: Peripheral) -> String.toUpper p.name = n) ps)) only
      if not (List.isEmpty missing) then Error ("only: " + String.join ", " missing + " isn't a peripheral of " + Option.defaultValue "" (Xml.childText "name" root) + " (" + String.join ", " (List.map (fun (p: Peripheral) -> p.name) ps) + ")")
      else
        let peripheral (p: Peripheral) : list<string> =
          let registers =
            // a register of a size the runtime has no access for is left out, named
            let (ok, odd) = List.partition (fun (r: Register) -> r.size = 32 || r.size = 8) p.registers
            List.concat [ (if List.isEmpty odd then [] else [ "  // left out, neither 32 nor 8 bits wide: " + String.join ", " (List.map (fun (r: Register) -> r.name) odd) ])
                List.collect (registerText p) ok ]
          List.concat [ [ $"/// {p.description} ({p.name}, base 0x{p.baseAddress:x})"
                $"module {pascal p.name} =" ]
              (if List.isEmpty registers then [ "  let private baseAddress = usize 0x" + $"{p.baseAddress:x}"; "" ] else registers) ]
        let header = [ "// provided by svd 0.1 from " + file; "// input: " + file; "" ]
        Ok(String.join "\n" (List.append header (List.collect peripheral chosen)))
