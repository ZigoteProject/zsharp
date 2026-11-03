// A provider from a package (0001): the dependency shout has a [provider] section, so the
// compiler builds its program once into .zs-cache/providers/bin and runs it for this import
import shout ("words.txt", prefix = "s_")

let main () =
  println $"{s_alpha} {s_beta}"
  0
