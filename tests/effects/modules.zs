// Effects across modules: Tokens yields and throws, this module handles (phase 10)

let main () =
  let words = Seq.toList (Seq(fun () -> Tokens.words "to be  or not"))
  println $"{words}"
  let good = Throw.catch (fun () -> Tokens.sum "1 22 333")
  let bad = Throw.catch (fun () -> Tokens.sum "1 two 3")
  println $"{good} {bad}"
  // Tokens.each, purely and with an effect
  Tokens.each (fun w -> print (w + " ")) [ "pure"; "instance" ]
  println ""
  let shouted =
    Seq.toList (Seq(fun () -> Tokens.each (fun w -> Yield.yield (String.toUpper w)) [ "a"; "b" ]))
  println $"{shouted}"
  0
