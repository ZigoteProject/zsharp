// effects on a microcontroller: a generator and a typed exception
let evens n = seq { for i in 1 .. n do if i % 2 = 0 then yield i }

let check (x: int) : int / Throw<string> = if x > 6 then Throw.throw "too big" else x

let main () =
  println $"{Seq.toList (Seq.take 3 (evens 100))} {Seq.sum (evens 10)}"
  let r = Throw.catch (fun () -> Seq.fold (fun acc x -> acc + check x) 0 (evens 10))
  println $"{r}"
  0
