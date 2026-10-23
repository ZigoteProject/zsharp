// A dependency's modules are behind its name: Alpha.Util and Beta.Util (here Util, opened); and
// a dependency with C code (cwords' [c] section).
open Beta

let main () =
  println (Alpha.describe ())
  println (describe ())
  println $"{Alpha.Util.name} / {Util.name} / {Alpha.Shapes.Square.area 4}"
  println $"{Cwords.vowels "education"} {Cwords.scaledRoot 2.25}"
  0
