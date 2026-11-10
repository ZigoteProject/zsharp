// [<NoAlloc>] and a ref's value overwritten: the old value is dropped there, which may free it
[<NoAlloc>]
let clear (r: ref<list<int>>) = r.Value <- []

let main () =
  let r = ref [ 1; 2 ]
  clear r
  println $"{List.length r.Value}"
  0
