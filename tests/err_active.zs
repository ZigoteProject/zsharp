let (|Even|Odd|) n = if n % 2 = 0 then Even else Odd

let f n =
  match n with
  | Even -> 1

let main () = f 2
