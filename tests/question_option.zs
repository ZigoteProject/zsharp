// ? on an option: in a function (or a lambda) returning an option, `x?` is the value in a Some,
// or returns None at once
let digit (c: char) = if c >= '0' && c <= '9' then Some(int c - int '0') else None

let number (s: string) =
  let cs = String.chars s
  let a = digit (List.item 0 cs)?
  let b = digit (List.item 1 cs)?
  Some(a * 10 + b)

// ? as a statement: only whether it's there
let both (xs: list<int>) =
  List.tryHead xs?
  Some(List.last xs)

let main () =
  println $"{number "42"} {number "4x"}"
  println $"{both [ 1; 2; 3 ]} {both []}"
  // in a local function: its own result decides
  let firstDoubled (xs: list<int>) =
    let x = List.tryHead xs?
    Some(2 * x)

  println $"{firstDoubled [ 5 ]} {firstDoubled []}"
  0
