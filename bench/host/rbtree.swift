// A red-black tree (Okasaki's): inserting a million keys into a persistent tree, then looking
// each one up. The same algorithm as the Z# version, so ARC meets Perceus.
enum Color { case red, black }

indirect enum Tree {
  case empty
  case node(Color, Tree, Int, Tree)
}

func balance(_ c: Color, _ l: Tree, _ k: Int, _ r: Tree) -> Tree {
  switch (c, l, k, r) {
  case let (.black, .node(.red, .node(.red, a, x, b), y, c2), z, d),
       let (.black, .node(.red, a, x, .node(.red, b, y, c2)), z, d),
       let (.black, a, x, .node(.red, .node(.red, b, y, c2), z, d)),
       let (.black, a, x, .node(.red, b, y, .node(.red, c2, z, d))):
    return .node(.red, .node(.black, a, x, b), y, .node(.black, c2, z, d))
  default:
    return .node(c, l, k, r)
  }
}

func insert(_ k: Int, _ t: Tree) -> Tree {
  func ins(_ t: Tree) -> Tree {
    switch t {
    case .empty: return .node(.red, .empty, k, .empty)
    case let .node(c, l, x, r):
      return k < x ? balance(c, ins(l), x, r) : k > x ? balance(c, l, x, ins(r)) : t
    }
  }
  if case let .node(_, l, x, r) = ins(t) { return .node(.black, l, x, r) }
  return .empty
}

func contains(_ k: Int, _ t: Tree) -> Bool {
  var t = t
  while case let .node(_, l, x, r) = t {
    if k < x { t = l } else if k > x { t = r } else { return true }
  }
  return false
}

let n = CommandLine.arguments.dropFirst().first.flatMap { Int($0) } ?? 1000000
var t = Tree.empty
var seed = 42
for _ in 0..<n {
  seed = (seed * 1103515245 + 12345) % 2147483648
  t = insert(seed % n, t)
}
var found = 0
for i in 0..<n where contains(i, t) { found += 1 }
print(found)
