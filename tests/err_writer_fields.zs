// a fixed Writer is made only by Bytes.writer, which is unsafe: its memory is private
let main () =
  let w = Bytes.Fixed { at = Ptr.null; capacity = 9; length = 0 }
  0
