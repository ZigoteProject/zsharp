// Binary trees (the Benchmarks Game): allocating and walking many small trees, with an
// indirect enum (reference counted).
indirect enum Tree {
  case leaf
  case node(Tree, Tree)
}

func make(_ d: Int) -> Tree { d == 0 ? .node(.leaf, .leaf) : .node(make(d - 1), make(d - 1)) }

func check(_ t: Tree) -> Int {
  switch t {
  case .leaf: return 0
  case let .node(l, r): return 1 + check(l) + check(r)
  }
}

let n = CommandLine.arguments.dropFirst().first.flatMap { Int($0) } ?? 16
let maxDepth = max(6, n)
let stretch = maxDepth + 1
print("stretch tree of depth \(stretch)\t check: \(check(make(stretch)))")
let longLived = make(maxDepth)
var d = 4
while d <= maxDepth {
  let iterations = 1 << (maxDepth - d + 4)
  var total = 0
  for _ in 0..<iterations { total += check(make(d)) }
  print("\(iterations)\t trees of depth \(d)\t check: \(total)")
  d += 2
}
print("long lived tree of depth \(maxDepth)\t check: \(check(longLived))")
