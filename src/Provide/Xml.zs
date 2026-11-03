/// A small XML reader for the data sources providers take (an SVD file): elements with their
/// attributes, children and text, the declaration, comments, doctype and CDATA read past, and
/// the five entities and numeric references decoded. Enough for what a vendor writes; not a
/// validating parser.

/// An element: its name, its attributes in order, its child elements in order, and the text
/// directly in it (its pieces joined, trimmed).
type Element = Element of name: string * attrs: list<string * string> * children: list<Element> * text: string

/// An element's name.
let nameOf (e: Element) : string =
  match e with
  | Element(n, _, _, _) -> n

/// An element's own text.
let textOf (e: Element) : string =
  match e with
  | Element(_, _, _, t) -> t

/// An element's child elements, in order.
let childrenOf (e: Element) : list<Element> =
  match e with
  | Element(_, _, cs, _) -> cs

/// The first child element with the name.
let child (name: string) (e: Element) : option<Element> = List.tryFind (fun (c: Element) -> nameOf c = name) (childrenOf e)

/// The child elements with the name, in order.
let children (name: string) (e: Element) : list<Element> = List.filter (fun (c: Element) -> nameOf c = name) (childrenOf e)

/// The text of the first child element with the name.
let childText (name: string) (e: Element) : option<string> = Option.map textOf (child name e)

/// An attribute's value.
let attr (name: string) (e: Element) : option<string> =
  match e with
  | Element(_, attrs, _, _) ->
    match List.tryFind (fun (n, _) -> n = name) attrs with
    | Some(_, v) -> Some v
    | None -> None

type private Reader = { s: string; n: int; pos: ref<int>; line: ref<int> }

let private peekAt (r: Reader) (i: int) : u8 = if i < r.n then String.byte r.s i else u8 0

let private startsAt (r: Reader) (i: int) (word: string) : bool =
  let w = String.length word
  let mutable k = 0
  while k < w && i + k < r.n && String.byte r.s (i + k) = String.byte word k do
    k <- k + 1
  k = w

let private isSpace (b: u8) = b = u8 32 || b = u8 9 || b = u8 10 || b = u8 13

let private isNameByte (b: u8) =
  (b >= u8 97 && b <= u8 122) || (b >= u8 65 && b <= u8 90) || (b >= u8 48 && b <= u8 57) || b = u8 95 || b = u8 45 || b = u8 46 || b = u8 58 || b >= u8 128

let private fail (r: Reader) (msg: string) : result<'a, string> = Error $"{r.line.Value}: {msg}"

// the position moved past i, lines counted
let private advanceTo (r: Reader) (i: int) =
  let mutable k = r.pos.Value
  while k < i && k < r.n do
    if String.byte r.s k = u8 10 then r.line.Value <- r.line.Value + 1
    k <- k + 1
  r.pos.Value <- i

let private skipSpace (r: Reader) =
  let mutable i = r.pos.Value
  while i < r.n && isSpace (String.byte r.s i) do
    i <- i + 1
  advanceTo r i

// past a run that ends with `close` (a comment, a declaration, CDATA): Error when it doesn't end
let private skipPast (r: Reader) (close: string) (what: string) : result<unit, string> =
  match String.indexOf close (String.sub r.s r.pos.Value (r.n - r.pos.Value)) with
  | Some k ->
    advanceTo r (r.pos.Value + k + String.length close)
    Ok ()
  | None -> fail r $"{what} isn't closed"

/// Text with its entities decoded: &lt; &gt; &amp; &quot; &apos; and &#n; or &#xn;.
let decode (s: string) : string =
  if not (String.contains "&" s) then s
  else
    let n = String.length s
    let mutable out = ""
    let mutable from = 0
    let mutable i = 0
    while i < n do
      if String.byte s i = u8 38 then
        match String.indexOf ";" (String.sub s i (n - i)) with
        | Some k when k <= 10 ->
          let name = String.sub s (i + 1) (k - 1)
          let replaced =
            match name with
            | "lt" -> Some "<"
            | "gt" -> Some ">"
            | "amp" -> Some "&"
            | "quot" -> Some "\""
            | "apos" -> Some "'"
            | _ ->
              if String.startsWith "#x" name then
                let v: option<int> = Int.parseRadix 16 (String.sub name 2 (String.length name - 2))
                Option.map (fun c -> String.ofChar (char c)) v
              else if String.startsWith "#" name then
                let v: option<int> = Int.parse (String.sub name 1 (String.length name - 1))
                Option.map (fun c -> String.ofChar (char c)) v
              else None
          match replaced with
          | Some t ->
            out <- out + String.sub s from (i - from) + t
            i <- i + k + 1
            from <- i
          | None -> i <- i + 1
        | _ -> i <- i + 1
      else
        i <- i + 1
    out + String.sub s from (n - from)

let private nameAt (r: Reader) : string =
  let start = r.pos.Value
  let mutable i = start
  while i < r.n && isNameByte (String.byte r.s i) do
    i <- i + 1
  advanceTo r i
  String.sub r.s start (i - start)

// name="value" pairs up to > or />
let private attributes (r: Reader) : result<list<string * string>, string> =
  let acc = ref []
  let mutable stop = None
  while Option.isNone stop do
    skipSpace r
    let b = peekAt r r.pos.Value
    if b = u8 62 || b = u8 47 || b = u8 0 then stop <- Some(Ok(List.rev acc.Value))
    else
      let n = nameAt r
      if n = "" then stop <- Some(fail r "expected an attribute's name")
      else
        skipSpace r
        if peekAt r r.pos.Value <> u8 61 then stop <- Some(fail r $"expected '=' after '{n}'")
        else
          advanceTo r (r.pos.Value + 1)
          skipSpace r
          let q = peekAt r r.pos.Value
          if q <> u8 34 && q <> u8 39 then stop <- Some(fail r $"expected a quoted value for '{n}'")
          else
            let start = r.pos.Value + 1
            let mutable i = start
            while i < r.n && String.byte r.s i <> q do
              i <- i + 1
            if i >= r.n then stop <- Some(fail r $"'{n}' has no closing quote")
            else
              acc.Value <- (n, decode (String.sub r.s start (i - start))) :: acc.Value
              advanceTo r (i + 1)
  Option.get stop

// an element, the reader at its '<'
let rec private element (r: Reader) (depth: int) : result<Element, string> =
  if depth > 200 then fail r "elements nest too deep"
  else
    advanceTo r (r.pos.Value + 1)
    let name = nameAt r
    if name = "" then fail r "expected an element's name after '<'"
    else
      match attributes r with
      | Error e -> Error e
      | Ok attrs ->
        if startsAt r r.pos.Value "/>" then
          advanceTo r (r.pos.Value + 2)
          Ok(Element(name, attrs, [], ""))
        else if peekAt r r.pos.Value <> u8 62 then fail r $"expected '>' to end <{name}>"
        else
          advanceTo r (r.pos.Value + 1)
          content r name attrs depth

// what's inside an element up to its end tag
and private content (r: Reader) (name: string) (attrs: list<string * string>) (depth: int) : result<Element, string> =
  let kids = ref []
  let texts = ref []
  let from = ref r.pos.Value
  let mutable stop = None
  let flush (upTo: int) =
    let piece = String.trim (String.sub r.s from.Value (upTo - from.Value))
    if piece <> "" then texts.Value <- decode piece :: texts.Value
  while Option.isNone stop do
    let i = r.pos.Value
    if i >= r.n then stop <- Some(fail r $"<{name}> isn't closed")
    else if String.byte r.s i <> u8 60 then advanceTo r (i + 1)
    else
      flush i
      if startsAt r i "</" then
        advanceTo r (i + 2)
        let closing = nameAt r
        skipSpace r
        if closing <> name then stop <- Some(fail r $"</{closing}> closes <{name}>")
        else if peekAt r r.pos.Value <> u8 62 then stop <- Some(fail r $"expected '>' after </{name}")
        else
          advanceTo r (r.pos.Value + 1)
          stop <- Some(Ok(Element(name, attrs, List.rev kids.Value, String.join " " (List.rev texts.Value))))
      else if startsAt r i "<!--" then
        match skipPast r "-->" "a comment" with
        | Error e -> stop <- Some(Error e)
        | Ok _ -> from.Value <- r.pos.Value
      else if startsAt r i "<![CDATA[" then
        let start = i + 9
        match String.indexOf "]]>" (String.sub r.s start (r.n - start)) with
        | Some k ->
          let piece = String.sub r.s start k
          if piece <> "" then texts.Value <- piece :: texts.Value
          advanceTo r (start + k + 3)
          from.Value <- r.pos.Value
        | None -> stop <- Some(fail r "CDATA isn't closed")
      else if startsAt r i "<?" then
        match skipPast r "?>" "a processing instruction" with
        | Error e -> stop <- Some(Error e)
        | Ok _ -> from.Value <- r.pos.Value
      else
        match element r (depth + 1) with
        | Error e -> stop <- Some(Error e)
        | Ok k ->
          kids.Value <- k :: kids.Value
          from.Value <- r.pos.Value
  Option.get stop

/// The document's root element, or where it went wrong (`line: message`).
let parse (text: string) : result<Element, string> =
  let r = { s = text; n = String.length text; pos = ref 0; line = ref 1 }
  let mutable found = None
  while Option.isNone found do
    skipSpace r
    let i = r.pos.Value
    if i >= r.n then found <- Some(fail r "no root element")
    else if startsAt r i "<?" then
      match skipPast r "?>" "the declaration" with
      | Error e -> found <- Some(Error e)
      | Ok _ -> ()
    else if startsAt r i "<!--" then
      match skipPast r "-->" "a comment" with
      | Error e -> found <- Some(Error e)
      | Ok _ -> ()
    else if startsAt r i "<!" then
      match skipPast r ">" "the doctype" with
      | Error e -> found <- Some(Error e)
      | Ok _ -> ()
    else if String.byte r.s i = u8 60 then found <- Some(element r 0)
    else found <- Some(fail r "expected '<'")
  Option.get found
