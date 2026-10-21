// Std needs an operating system: built for a microcontroller, using it is a compile error
let main () = File.readAllText "x" |> ignore
