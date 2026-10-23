// zs fmt's reflow (0019): each line over 100 columns broken on the syntax tree; tests/fmt/reflow.zs
// is what it gives
type Item = { name: string; price: int }

let report (items: list<Item>) =
  items
  |> List.filter (fun i -> i.price > 100)
  |> List.map (fun i -> $"{i.name}: {i.price}")
  |> String.join "\n" // the expensive ones

let collatz n =
  let rec down n steps =
    if n = 1 || steps > 1000 then
      steps
    else if n % 2 = 0 then
      down (n / 2) (steps + 1)
    else
      down (3 * n + 1) (steps + 1)
  down n 0

let main () =
  let items =
    [ { name = "lamp"; price = 120 }
      { name = "chair"; price = 80 }
      { name = "desk"; price = 300 } ]
  let (total, count, label, currency) =
    (List.sumBy (fun i -> i.price) items, List.length items, "total", "usd")
  println (report items)
  println $"{label}: {total} {currency} over {count} items, and a string long enough that it stays as it is written"
  match List.tryHead items with
  | Some i when i.price > 100 -> println i.name
  | Some i -> println $"cheap {i.name}"
  | None -> ()
  0
