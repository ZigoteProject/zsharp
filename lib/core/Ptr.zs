/// Raw C pointers: `ptr<T>` points at C data (a number, a `bool`, a `[<CLayout>]` record or
/// another pointer), for C libraries that hand out or take memory. Reading, writing, pointer
/// arithmetic and casts are unsafe: they compile only inside `unsafe`, as calls through a C
/// function pointer (`fnptr<A -> R>`) do. Its functions are built into the compiler.
module Ptr
