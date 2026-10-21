// A red-black tree: inserting a million keys, then looking each one up. An in-place
// left-leaning red-black tree (Sedgewick) with Box, the usual way to write one in Rust.
struct Node {
    key: i64,
    l: Option<Box<Node>>,
    r: Option<Box<Node>>,
    red: bool,
}

fn is_red(n: &Option<Box<Node>>) -> bool {
    n.as_ref().is_some_and(|n| n.red)
}

fn rotate_left(mut h: Box<Node>) -> Box<Node> {
    let mut x = h.r.take().unwrap();
    h.r = x.l.take();
    x.red = h.red;
    h.red = true;
    x.l = Some(h);
    x
}

fn rotate_right(mut h: Box<Node>) -> Box<Node> {
    let mut x = h.l.take().unwrap();
    h.l = x.r.take();
    x.red = h.red;
    h.red = true;
    x.r = Some(h);
    x
}

fn flip(h: &mut Node) {
    h.red = !h.red;
    let l = h.l.as_mut().unwrap();
    l.red = !l.red;
    let r = h.r.as_mut().unwrap();
    r.red = !r.red;
}

fn insert(h: Option<Box<Node>>, k: i64) -> Box<Node> {
    let mut h = match h {
        None => return Box::new(Node { key: k, l: None, r: None, red: true }),
        Some(h) => h,
    };
    if k < h.key {
        h.l = Some(insert(h.l.take(), k));
    } else if k > h.key {
        h.r = Some(insert(h.r.take(), k));
    } else {
        return h;
    }
    if is_red(&h.r) && !is_red(&h.l) {
        h = rotate_left(h);
    }
    if is_red(&h.l) && is_red(&h.l.as_ref().unwrap().l) {
        h = rotate_right(h);
    }
    if is_red(&h.l) && is_red(&h.r) {
        flip(&mut h);
    }
    h
}

fn contains(mut t: &Option<Box<Node>>, k: i64) -> bool {
    while let Some(n) = t {
        if k < n.key {
            t = &n.l;
        } else if k > n.key {
            t = &n.r;
        } else {
            return true;
        }
    }
    false
}

fn main() {
    let n: i64 = std::env::args().nth(1).and_then(|a| a.parse().ok()).unwrap_or(1000000);
    let mut t = None;
    let mut seed: i64 = 42;
    for _ in 0..n {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        let mut root = insert(t, seed % n);
        root.red = false;
        t = Some(root);
    }
    let found = (0..n).filter(|&i| contains(&t, i)).count();
    println!("{}", found);
}
