(* N-body (the Benchmarks Game): floating-point arithmetic over arrays updated in place. *)
let pi = 3.141592653589793
let solar_mass = 4.0 *. pi *. pi
let days_per_year = 365.24

(* the sun, Jupiter, Saturn, Uranus, Neptune *)
let x = [| 0.0; 4.84143144246472090; 8.34336671824457987; 12.8943695621391310; 15.3796971148509165 |]
let y = [| 0.0; -1.16032004402742839; 4.12479856412430479; -15.1111514016986312; -25.9193146099879641 |]
let z = [| 0.0; -0.103622044471123109; -0.403523417114321381; -0.223307578892655734; 0.179258772950371181 |]
let vx = [| 0.0; 0.00166007664274403694; -0.00276742510726862411; 0.00296460137564761618; 0.00268067772490389322 |]
let vy = [| 0.0; 0.00769901118419740425; 0.00499852801234917238; 0.00237847173959480950; 0.00162824170038242295 |]
let vz = [| 0.0; -0.0000690460016972063023; 0.0000230417297573763929; -0.0000296589568540237556; -0.0000951592254519715870 |]
let m = [| 1.0; 0.000954791938424326609; 0.000285885980666130812; 0.0000436624404335156298; 0.0000515138902046611451 |]

let energy () =
  let e = ref 0.0 in
  for i = 0 to 4 do
    e := !e +. 0.5 *. m.(i) *. (vx.(i) *. vx.(i) +. vy.(i) *. vy.(i) +. vz.(i) *. vz.(i));
    for j = i + 1 to 4 do
      let dx = x.(i) -. x.(j) and dy = y.(i) -. y.(j) and dz = z.(i) -. z.(j) in
      e := !e -. m.(i) *. m.(j) /. sqrt (dx *. dx +. dy *. dy +. dz *. dz)
    done
  done;
  !e

let () =
  let steps = if Array.length Sys.argv > 1 then int_of_string Sys.argv.(1) else 1000000 in
  for i = 0 to 4 do
    vx.(i) <- vx.(i) *. days_per_year;
    vy.(i) <- vy.(i) *. days_per_year;
    vz.(i) <- vz.(i) *. days_per_year;
    m.(i) <- m.(i) *. solar_mass
  done;
  (* the sun moves so that the total momentum is zero *)
  let px = ref 0.0 and py = ref 0.0 and pz = ref 0.0 in
  for i = 0 to 4 do
    px := !px +. vx.(i) *. m.(i);
    py := !py +. vy.(i) *. m.(i);
    pz := !pz +. vz.(i) *. m.(i)
  done;
  vx.(0) <- -. !px /. solar_mass;
  vy.(0) <- -. !py /. solar_mass;
  vz.(0) <- -. !pz /. solar_mass;
  Printf.printf "%d\n" (int_of_float (energy () *. 1000000000.0));
  let dt = 0.01 in
  for _ = 1 to steps do
    for i = 0 to 4 do
      for j = i + 1 to 4 do
        let dx = x.(i) -. x.(j) and dy = y.(i) -. y.(j) and dz = z.(i) -. z.(j) in
        let d2 = dx *. dx +. dy *. dy +. dz *. dz in
        let mag = dt /. (d2 *. sqrt d2) in
        let mi = m.(i) *. mag and mj = m.(j) *. mag in
        vx.(i) <- vx.(i) -. dx *. mj;
        vy.(i) <- vy.(i) -. dy *. mj;
        vz.(i) <- vz.(i) -. dz *. mj;
        vx.(j) <- vx.(j) +. dx *. mi;
        vy.(j) <- vy.(j) +. dy *. mi;
        vz.(j) <- vz.(j) +. dz *. mi
      done
    done;
    for i = 0 to 4 do
      x.(i) <- x.(i) +. dt *. vx.(i);
      y.(i) <- y.(i) +. dt *. vy.(i);
      z.(i) <- z.(i) +. dt *. vz.(i)
    done
  done;
  Printf.printf "%d\n" (int_of_float (energy () *. 1000000000.0))
