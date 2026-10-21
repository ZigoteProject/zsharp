// Binary trees (the Benchmarks Game): allocating and walking many small trees, with Box.
struct Node {
    children: Option<(Box<Node>, Box<Node>)>,
}

fn make(d: i32) -> Box<Node> {
    Box::new(Node { children: if d == 0 { None } else { Some((make(d - 1), make(d - 1))) } })
}

fn check(t: &Node) -> i64 {
    match &t.children {
        Some((l, r)) => 1 + check(l) + check(r),
        None => 1,
    }
}

fn main() {
    let n: i32 = std::env::args().nth(1).and_then(|a| a.parse().ok()).unwrap_or(16);
    let max_depth = n.max(6);
    let stretch = max_depth + 1;
    println!("stretch tree of depth {}\t check: {}", stretch, check(&make(stretch)));
    let long_lived = make(max_depth);
    let mut d = 4;
    while d <= max_depth {
        let iterations = 1i64 << (max_depth - d + 4);
        let mut total = 0;
        for _ in 0..iterations {
            total += check(&make(d));
        }
        println!("{}\t trees of depth {}\t check: {}", iterations, d, total);
        d += 2;
    }
    println!("long lived tree of depth {}\t check: {}", max_depth, check(&long_lived));
}
