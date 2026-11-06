// A library that gives C no handles, only numbers, called on 8 threads at once
// (tests/cthreads_plain/main.c): what each call allocates (a list, strings) comes from its own
// thread's pool, as in a library with handles. Its runtime was built without threads, with one
// pool for them all and no lock: two threads took the same object, or linked a freed one twice.
[<Export "digits_total">]
let digitsTotal (n: int) : int = List.sum (List.init n (fun i -> String.length (string (i * 7919))))
