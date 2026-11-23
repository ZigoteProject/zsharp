// HashMap on a map nothing else refers to: a lookup allocates nothing, a remove nothing (its
// bucket rebuilt in its own cells), an update of a present key or an add of a new one a cell,
// the entry's; on a map something else still refers to, add and remove leave that one as it was;
// and a long run of adds, updates and removes gives the entries Map does
let main () =
  let keys = Array.init 1000 (fun i -> $"key{i}")
  let others = Array.init 1000 (fun i -> $"other{i}")
  let mutable m = HashMap.empty
  for k in keys do
    m <- HashMap.add k 0 m
  let mutable found = 0
  let a0 = Runtime.allocations ()
  for k in keys do
    if Option.isSome (HashMap.tryFind k m) then found <- found + 1
  for k in others do
    if HashMap.containsKey k m then found <- found + 1
  let a1 = Runtime.allocations ()
  for k in keys do
    m <- HashMap.add k 1 m
  let a2 = Runtime.allocations ()
  for k in keys do
    m <- HashMap.remove k m
  let a3 = Runtime.allocations ()
  for k in keys do
    m <- HashMap.add k 2 m
  let a4 = Runtime.allocations ()
  println $"2,000 lookups: {a1 - a0} allocations, {found} found"
  println $"1,000 updates: {a2 - a1} allocations; 1,000 removes: {a3 - a2}; 1,000 adds: {a4 - a3}"
  let shared = m
  let updated = HashMap.add keys.[0] 9 shared
  let added = HashMap.add "new" 7 shared
  let removed = HashMap.remove keys.[1] shared
  let missed = HashMap.remove "absent" shared
  println $"{HashMap.tryFind keys.[0] shared} {HashMap.tryFind keys.[0] updated} {HashMap.tryFind "new" shared} {HashMap.tryFind "new" added} {HashMap.tryFind keys.[1] shared} {HashMap.tryFind keys.[1] removed}"
  println $"{HashMap.count shared} {HashMap.count updated} {HashMap.count added} {HashMap.count removed} {HashMap.count missed}"
  // 20,000 steps over 500 keys, a third of them removes
  let mutable h = HashMap.empty
  let mutable t = Map.empty
  let mutable seed = 7
  for _ in 1 .. 20000 do
    seed <- (seed * 75 + 74) % 65537
    let k = seed % 500
    if seed / 7 % 3 = 0 then
      h <- HashMap.remove k h
      t <- Map.remove k t
    else
      h <- HashMap.add k seed h
      t <- Map.add k seed t
  println $"{List.sort (HashMap.toList h) = Map.toList t} {HashMap.count h} {Map.count t}"
  0
