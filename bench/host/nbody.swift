// N-body (the Benchmarks Game): floating-point arithmetic over arrays updated in place.
let pi = 3.141592653589793
let solarMass = 4.0 * pi * pi
let daysPerYear = 365.24

struct System {
  // the sun, Jupiter, Saturn, Uranus, Neptune
  var x = [0.0, 4.84143144246472090, 8.34336671824457987, 12.8943695621391310, 15.3796971148509165]
  var y = [0.0, -1.16032004402742839, 4.12479856412430479, -15.1111514016986312, -25.9193146099879641]
  var z = [0.0, -0.103622044471123109, -0.403523417114321381, -0.223307578892655734, 0.179258772950371181]
  var vx = [0.0, 0.00166007664274403694, -0.00276742510726862411, 0.00296460137564761618, 0.00268067772490389322]
  var vy = [0.0, 0.00769901118419740425, 0.00499852801234917238, 0.00237847173959480950, 0.00162824170038242295]
  var vz = [0.0, -0.0000690460016972063023, 0.0000230417297573763929, -0.0000296589568540237556, -0.0000951592254519715870]
  var m = [1.0, 0.000954791938424326609, 0.000285885980666130812, 0.0000436624404335156298, 0.0000515138902046611451]

  func energy() -> Double {
    var e = 0.0
    for i in 0..<5 {
      e += 0.5 * m[i] * (vx[i] * vx[i] + vy[i] * vy[i] + vz[i] * vz[i])
      for j in i + 1..<5 {
        let dx = x[i] - x[j], dy = y[i] - y[j], dz = z[i] - z[j]
        e -= m[i] * m[j] / (dx * dx + dy * dy + dz * dz).squareRoot()
      }
    }
    return e
  }

  mutating func advance(_ dt: Double) {
    for i in 0..<5 {
      for j in i + 1..<5 {
        let dx = x[i] - x[j], dy = y[i] - y[j], dz = z[i] - z[j]
        let d2 = dx * dx + dy * dy + dz * dz
        let mag = dt / (d2 * d2.squareRoot())
        let mi = m[i] * mag, mj = m[j] * mag
        vx[i] -= dx * mj; vy[i] -= dy * mj; vz[i] -= dz * mj
        vx[j] += dx * mi; vy[j] += dy * mi; vz[j] += dz * mi
      }
    }
    for i in 0..<5 {
      x[i] += dt * vx[i]; y[i] += dt * vy[i]; z[i] += dt * vz[i]
    }
  }
}

let steps = CommandLine.arguments.dropFirst().first.flatMap { Int($0) } ?? 1000000
var s = System()
for i in 0..<5 {
  s.vx[i] *= daysPerYear; s.vy[i] *= daysPerYear; s.vz[i] *= daysPerYear
  s.m[i] *= solarMass
}
// the sun moves so that the total momentum is zero
var px = 0.0, py = 0.0, pz = 0.0
for i in 0..<5 {
  px += s.vx[i] * s.m[i]; py += s.vy[i] * s.m[i]; pz += s.vz[i] * s.m[i]
}
s.vx[0] = -px / solarMass; s.vy[0] = -py / solarMass; s.vz[0] = -pz / solarMass
print(Int(s.energy() * 1000000000.0))
for _ in 0..<steps { s.advance(0.01) }
print(Int(s.energy() * 1000000000.0))
