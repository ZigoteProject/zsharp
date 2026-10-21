// Spectral norm (the Benchmarks Game): floating-point loops over arrays.
func a(_ i: Int, _ j: Int) -> Double {
  let ij = i + j
  return 1.0 / Double(ij * (ij + 1) / 2 + i + 1)
}

func multiplyAv(_ v: [Double]) -> [Double] {
  (0..<v.count).map { i in
    var s = 0.0
    for j in 0..<v.count { s += a(i, j) * v[j] }
    return s
  }
}

func multiplyAtv(_ v: [Double]) -> [Double] {
  (0..<v.count).map { i in
    var s = 0.0
    for j in 0..<v.count { s += a(j, i) * v[j] }
    return s
  }
}

func multiplyAtAv(_ v: [Double]) -> [Double] { multiplyAtv(multiplyAv(v)) }

let n = CommandLine.arguments.dropFirst().first.flatMap { Int($0) } ?? 1000
var u = [Double](repeating: 1.0, count: n)
var v = [Double](repeating: 0.0, count: n)
for _ in 0..<10 {
  v = multiplyAtAv(u)
  u = multiplyAtAv(v)
}
var vBv = 0.0, vv = 0.0
for i in 0..<n {
  vBv += u[i] * v[i]
  vv += v[i] * v[i]
}
print(Int((vBv / vv).squareRoot() * 1000000000.0))
