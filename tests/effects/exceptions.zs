// Typed exceptions: the Throw effect, caught into a result where it's handled (phase 10)

type ParseError =
  | NotADigit of char
  | Empty

let digit (c: char) : int / Throw<ParseError> =
  if c >= '0' && c <= '9' then int c - int '0' else Throw.throw (NotADigit c)

// a throw from inside a loop: nothing after it runs
let number (s: string) =
  if String.length s = 0 then Throw.throw Empty
  let mutable n = 0
  for c in s do n <- n * 10 + digit c
  n

let sumAll (xs: list<string>) = List.fold (fun acc s -> acc + number s) 0 xs

// from deep inside nested loops and a local function
let search (target: int) =
  let rec row i =
    for j in 0 .. 9 do
      if i * 10 + j = target then Throw.throw (i, j)
  for i in 0 .. 9 do row i
  (-1, -1)

let main () =
  let a = Throw.catch (fun () -> number "1234")
  let b = Throw.catch (fun () -> number "12x4")
  let c = Throw.catch (fun () -> number "")
  println $"{a} {b} {c}"
  let d = Throw.catch (fun () -> sumAll [ "1"; "20"; "300" ])
  let e = Throw.catch (fun () -> sumAll [ "1"; "2o"; "300" ])
  println $"{d} {e}"
  println $"{Throw.recover (fun e -> e) (fun () -> search 57)} {Throw.recover (fun e -> e) (fun () -> search 570)}"
  // results and options into throws, and back
  let parsed = Throw.catch (fun () -> Throw.ofResult (Ok 5) + Throw.ofOption "missing" None)
  println $"{parsed}"
  // a handler's clause that throws: the outer handler takes it
  let r =
    Throw.catch (fun () ->
      handle number "" with
      | Throw.throw e, _ -> Throw.throw ("wrapped: " + string e))
  println $"{r}"
  0
