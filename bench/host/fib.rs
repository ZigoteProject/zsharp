// Recursive Fibonacci: calls and integer arithmetic (release builds wrap on overflow).
fn fib(n: i64) -> i64 {
    if n < 2 { n } else { fib(n - 1) + fib(n - 2) }
}

fn main() {
    let n = std::env::args().nth(1).and_then(|a| a.parse().ok()).unwrap_or(32);
    println!("{}", fib(n));
}
