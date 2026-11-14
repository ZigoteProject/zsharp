// Task.waitFor takes any number: one that isn't an open descriptor is a panic, where the event
// loop sized its table by it (this one's callback landed outside the table)
let main () =
  println "before"
  Task.run (Task.waitFor (2305843009213694952 + List.length (Environment.args ())) false)
  0
