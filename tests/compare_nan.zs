// compare is a total order on floats (track G, defect 3): a NaN is after every number and equal
// to a NaN, so floats sort and key a Map; the operators stay IEEE 754's
let main () =
  let nan = 0.0 / 0.0
  println $"{compare nan 1.0} {compare 1.0 nan} {compare nan nan} {compare 1.0 2.0} {compare 2.0 1.0} {compare 0.0 -0.0}"
  println $"{nan = nan} {nan < 1.0} {nan > 1.0}"
  println $"{List.sort [ nan; 2.0; 1.0; nan; -1.0 ]}"
  println $"{Array.toList (Array.sort [| 3.0; nan; 1.0 |])}"
  let m = Map.empty |> Map.add nan "nan" |> Map.add 1.0 "one" |> Map.add nan "again"
  println $"{Map.count m} {Map.tryFind nan m} {Map.tryFind 1.0 m}"
  let f: f32 = 0.0 / 0.0
  println $"{compare f 1.0} {max 1.0 2.0}"
