// Through dyn, a trait method's arguments must perform nothing: the table has no evidence to pass.
trait Visit<'c> =
  abstract each : 'c -> (int -> unit) -> unit

type Bag = { items: list<int> }

impl Visit<Bag> =
  let each b f = List.iter f b.items

let anyNegative (b: dyn Visit) : bool =
  Result.isError (Throw.catch (fun () ->
      Visit.each b (fun x -> if x < 0 then Throw.throw "negative")))

let main () =
  println $"{anyNegative { items = [ 1 ] }}"
  0
