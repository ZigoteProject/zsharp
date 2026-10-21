// N-body (the Benchmarks Game): floating-point arithmetic over arrays updated in place.
let pi = 3.141592653589793
let solarMass = 4.0 * pi * pi
let daysPerYear = 365.24

let energy (x: array<f64>) (y: array<f64>) (z: array<f64>) (vx: array<f64>) (vy: array<f64>) (vz: array<f64>) (m: array<f64>) =
  let mutable e = 0.0
  for i in 0 .. 4 do
    e <- e + 0.5 * m.[i] * (vx.[i] * vx.[i] + vy.[i] * vy.[i] + vz.[i] * vz.[i])
    for j in i + 1 .. 4 do
      let dx = x.[i] - x.[j]
      let dy = y.[i] - y.[j]
      let dz = z.[i] - z.[j]
      e <- e - m.[i] * m.[j] / Math.sqrt (dx * dx + dy * dy + dz * dz)
  e

let main () =
  let steps =
    match Environment.args () with
    | a :: _ -> Option.defaultValue 1000000 (String.parseInt a)
    | [] -> 1000000
  // the sun, Jupiter, Saturn, Uranus, Neptune
  let mutable x = [| 0.0; 4.84143144246472090; 8.34336671824457987; 12.8943695621391310; 15.3796971148509165 |]
  let mutable y = [| 0.0; -1.16032004402742839; 4.12479856412430479; -15.1111514016986312; -25.9193146099879641 |]
  let mutable z = [| 0.0; -0.103622044471123109; -0.403523417114321381; -0.223307578892655734; 0.179258772950371181 |]
  let mutable vx = [| 0.0; 0.00166007664274403694; -0.00276742510726862411; 0.00296460137564761618; 0.00268067772490389322 |]
  let mutable vy = [| 0.0; 0.00769901118419740425; 0.00499852801234917238; 0.00237847173959480950; 0.00162824170038242295 |]
  let mutable vz = [| 0.0; -0.0000690460016972063023; 0.0000230417297573763929; -0.0000296589568540237556; -0.0000951592254519715870 |]
  let mutable m = [| 1.0; 0.000954791938424326609; 0.000285885980666130812; 0.0000436624404335156298; 0.0000515138902046611451 |]
  for i in 0 .. 4 do
    vx.[i] <- vx.[i] * daysPerYear
    vy.[i] <- vy.[i] * daysPerYear
    vz.[i] <- vz.[i] * daysPerYear
    m.[i] <- m.[i] * solarMass
  // the sun moves so that the total momentum is zero
  let mutable px = 0.0
  let mutable py = 0.0
  let mutable pz = 0.0
  for i in 0 .. 4 do
    px <- px + vx.[i] * m.[i]
    py <- py + vy.[i] * m.[i]
    pz <- pz + vz.[i] * m.[i]
  vx.[0] <- -px / solarMass
  vy.[0] <- -py / solarMass
  vz.[0] <- -pz / solarMass
  println $"{int (energy x y z vx vy vz m * 1000000000.0)}"
  let dt = 0.01
  for _ in 1 .. steps do
    for i in 0 .. 4 do
      for j in i + 1 .. 4 do
        let dx = x.[i] - x.[j]
        let dy = y.[i] - y.[j]
        let dz = z.[i] - z.[j]
        let d2 = dx * dx + dy * dy + dz * dz
        let mag = dt / (d2 * Math.sqrt d2)
        let mi = m.[i] * mag
        let mj = m.[j] * mag
        vx.[i] <- vx.[i] - dx * mj
        vy.[i] <- vy.[i] - dy * mj
        vz.[i] <- vz.[i] - dz * mj
        vx.[j] <- vx.[j] + dx * mi
        vy.[j] <- vy.[j] + dy * mi
        vz.[j] <- vz.[j] + dz * mi
    for i in 0 .. 4 do
      x.[i] <- x.[i] + dt * vx.[i]
      y.[i] <- y.[i] + dt * vy.[i]
      z.[i] <- z.[i] + dt * vz.[i]
  println $"{int (energy x y z vx vy vz m * 1000000000.0)}"
  0
