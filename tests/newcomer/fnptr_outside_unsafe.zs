// C: calling a C function pointer; in Z# that's inside `unsafe`, since C's convention isn't checked
extern get_handler : unit -> fnptr<int -> int>

let main () =
  let f = get_handler ()
  f 3
