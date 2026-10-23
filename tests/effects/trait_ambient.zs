// A trait method's function argument may perform: the method performs what it's given (0025),
// so Throw reaches the catch around the call.
trait Visit<'c> =
  abstract each : 'c -> (int -> unit) -> unit

type Bag = { items: list<int> }

impl Visit<Bag> =
  let each b f = List.iter f b.items

let sum (b: Bag) =
  let total = ref 0
  Visit.each b (fun x -> total.Value <- total.Value + x)
  total.Value

let firstNegative (b: Bag) : result<int, string> =
  Throw.catch (fun () ->
    Visit.each b (fun x -> if x < 0 then Throw.throw $"negative: {x}")
    List.length b.items)

let main () =
  let b = { items = [ 1; 2; -3; 4 ] }
  println $"{sum b} {firstNegative b} {firstNegative { items = [ 1 ] }}"
  0
