// F#: a `let mutable` can't be captured by a closure; use a ref cell
let main () =
  let mutable total = 0
  [ 1; 2; 3 ] |> List.iter (fun x -> total <- total + x)
  total
