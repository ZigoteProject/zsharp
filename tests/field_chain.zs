// A field read after `.Value` (Value.index reads as one qualified name, and is two fields), and
// type arguments closed by a run of four `>`.
type Place = { index: int; name: string }

type Holder = { cell: ref<Place> }

let nested : list<list<list<list<int>>>> = [ [ [ [ 1; 2 ] ]; [ [ 3 ] ] ] ]

let main () =
  let h = { cell = ref { index = 7; name = "seven" } }
  println $"{h.cell.Value.index} {h.cell.Value.name.Length}"
  h.cell.Value <- { index = 8; name = "eight" }
  println $"{h.cell.Value.index} {List.length (List.head nested)}"
