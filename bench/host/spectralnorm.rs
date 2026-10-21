// Spectral norm (the Benchmarks Game): floating-point loops over arrays.
fn a(i: usize, j: usize) -> f64 {
    1.0 / ((i + j) * (i + j + 1) / 2 + i + 1) as f64
}

fn multiply_av(v: &[f64]) -> Vec<f64> {
    (0..v.len()).map(|i| v.iter().enumerate().map(|(j, vj)| a(i, j) * vj).sum()).collect()
}

fn multiply_atv(v: &[f64]) -> Vec<f64> {
    (0..v.len()).map(|i| v.iter().enumerate().map(|(j, vj)| a(j, i) * vj).sum()).collect()
}

fn multiply_atav(v: &[f64]) -> Vec<f64> {
    multiply_atv(&multiply_av(v))
}

fn main() {
    let n: usize = std::env::args().nth(1).and_then(|a| a.parse().ok()).unwrap_or(1000);
    let mut u = vec![1.0; n];
    let mut v = vec![0.0; n];
    for _ in 0..10 {
        v = multiply_atav(&u);
        u = multiply_atav(&v);
    }
    let vbv: f64 = u.iter().zip(&v).map(|(a, b)| a * b).sum();
    let vv: f64 = v.iter().map(|b| b * b).sum();
    println!("{}", ((vbv / vv).sqrt() * 1000000000.0) as i64);
}
