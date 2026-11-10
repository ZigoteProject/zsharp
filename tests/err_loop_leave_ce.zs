// break in a computation expression (proposal 0029): not supported, said where it's written
let inTask () =
  task {
    for x in [ 1; 2 ] do
      if x = 1 then break
  }

let main () = ()
