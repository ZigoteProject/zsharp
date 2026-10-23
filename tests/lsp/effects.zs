effect Log =
  abstract log : string -> unit

let greet name =
  Log.log $"hello {name}"

let main () =
  handle greet "you" with
  | Log.log s, k ->
    println s
    k ()
  0

effect Gen<'a> =
  abstract gen : 'a -> unit

// a clause performing its own effect goes to the next handler out
let doubled f =
  handle f () with
  | Gen.gen x, k ->
    Gen.gen (x * 2)
    k ()

let safe () = Throw.catch (fun () -> Throw.throw "no")
