// Shortest paths: Dijkstra's algorithm over a w x w grid whose cells cost 1 to 9 to enter, from
// the top-left corner to every cell, with the standard library's BinaryHeap.
use std::cmp::Reverse;
use std::collections::BinaryHeap;

fn next(seed: i64) -> i64 {
    (seed * 1103515245 + 12345) % 2147483648
}

fn main() {
    let w: i64 = std::env::args().nth(1).and_then(|a| a.parse().ok()).unwrap_or(1000);
    let cells = (w * w) as usize;
    let mut seed = 3;
    let cost: Vec<i64> = (0..cells)
        .map(|_| {
            seed = next(seed);
            1 + seed / 65536 % 9
        })
        .collect();
    let mut dist = vec![cells as i64 * 10; cells];
    dist[0] = 0;
    let mut heap = BinaryHeap::new();
    heap.push(Reverse((0i64, 0usize)));
    let mut settled = 0;
    while let Some(Reverse((d, cell))) = heap.pop() {
        if d != dist[cell] {
            continue; // stale: the cell was reached cheaper since
        }
        settled += 1;
        let (x, y) = ((cell as i64) % w, (cell as i64) / w);
        for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
            if nx < 0 || nx >= w || ny < 0 || ny >= w {
                continue;
            }
            let near = (ny * w + nx) as usize;
            let nd = d + cost[near];
            if nd < dist[near] {
                dist[near] = nd;
                heap.push(Reverse((nd, near)));
            }
        }
    }
    println!("{} cells settled", settled);
    println!("to the far corner: {}", dist[cells - 1]);
    println!("all distances: {}", dist.iter().sum::<i64>());
}
