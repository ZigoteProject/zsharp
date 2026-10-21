(* Spectral norm (the Benchmarks Game): floating-point loops over arrays. *)
let a i j = 1.0 /. float_of_int (((i + j) * (i + j + 1) / 2) + i + 1)

let multiply_av n v =
  Array.init n (fun i ->
      let s = ref 0.0 in
      for j = 0 to n - 1 do
        s := !s +. a i j *. v.(j)
      done;
      !s)

let multiply_atv n v =
  Array.init n (fun i ->
      let s = ref 0.0 in
      for j = 0 to n - 1 do
        s := !s +. a j i *. v.(j)
      done;
      !s)

let multiply_atav n v = multiply_atv n (multiply_av n v)

let () =
  let n = if Array.length Sys.argv > 1 then int_of_string Sys.argv.(1) else 1000 in
  let u = ref (Array.make n 1.0) and v = ref (Array.make n 0.0) in
  for _ = 1 to 10 do
    v := multiply_atav n !u;
    u := multiply_atav n !v
  done;
  let vbv = ref 0.0 and vv = ref 0.0 in
  for i = 0 to n - 1 do
    vbv := !vbv +. !u.(i) *. !v.(i);
    vv := !vv +. !v.(i) *. !v.(i)
  done;
  Printf.printf "%d\n" (int_of_float (sqrt (!vbv /. !vv) *. 1000000000.0))
