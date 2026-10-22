let main () =
  let p: ptr<int> = unsafe (Ptr.alloc 1)
  let s = Span.ofPtr p 1
  0
