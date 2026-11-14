// A negative number isn't a descriptor to wait for: a panic, where the event loop doubled its
// table's size without end
let main () =
  println "before"
  Task.run (Task.waitFor (List.length (Environment.args ()) - 5) false)
  0
