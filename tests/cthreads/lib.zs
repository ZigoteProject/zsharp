// Handles C uses on its own threads (tests/cthreads/main.c): a Share value's (a list) may be
// used on any of them, its objects marked shared and its count atomic; a ref's belongs to the
// thread that made it, and C using it on another panics, naming its type.
[<Export "numbers">]
let numbers (n: int) : list<int> = List.init n (fun i -> i + 1)

[<Export "numbers_sum">]
let sum (xs: list<int>) : int = List.sum xs

[<Export "numbers_more">]
let more (x: int) (xs: list<int>) : list<int> = x :: xs

[<Export "counter">]
let counter () : ref<int> = ref 0

[<Export "counter_add">]
let add (c: ref<int>) (n: int) : int =
  c.Value <- c.Value + n
  c.Value
