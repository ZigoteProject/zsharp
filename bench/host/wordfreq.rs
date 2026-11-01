// Word frequencies: a generated text of n words, split into lowercase words, counted in a
// HashMap and sorted by count, then word.
use std::collections::HashMap;

const VOCABULARY: i64 = 50000;
const SYLLABLES: [&str; 16] = ["ka", "lo", "mi", "ne", "ru", "sa", "to", "vi", "an", "el", "or", "us", "be", "di", "fu", "go"];

fn next(seed: i64) -> i64 {
    (seed * 1103515245 + 12345) % 2147483648
}

fn word(v: i64) -> String {
    let mut s = String::from(SYLLABLES[(v % 16) as usize]);
    let mut rest = v / 16;
    while rest > 0 {
        s.push_str(SYLLABLES[(rest % 16) as usize]);
        rest /= 16;
    }
    s
}

fn generate(n: usize) -> String {
    let words: Vec<String> = (0..VOCABULARY).map(word).collect();
    let mut out = String::new();
    let mut seed = 42;
    let mut capital = true;
    for _ in 0..n {
        seed = next(seed);
        let x = seed % VOCABULARY;
        let w = &words[(x * x / VOCABULARY) as usize];
        if capital {
            out.push((w.as_bytes()[0] - 32) as char);
            out.push_str(&w[1..]);
        } else {
            out.push_str(w);
        }
        seed = next(seed);
        capital = seed % 20 == 0;
        out.push_str(match seed % 20 {
            0 => ". ",
            1 => ", ",
            2 => "\n",
            _ => " ",
        });
    }
    out
}

fn main() {
    let n = std::env::args().nth(1).and_then(|a| a.parse().ok()).unwrap_or(1000000);
    let text = generate(n);
    let mut counts: HashMap<String, u64> = HashMap::new();
    let mut total = 0;
    for w in text.split(|c: char| !c.is_ascii_alphabetic()).filter(|w| !w.is_empty()) {
        *counts.entry(w.to_ascii_lowercase()).or_insert(0) += 1;
        total += 1;
    }
    let mut sorted: Vec<(&String, &u64)> = counts.iter().collect();
    sorted.sort_by(|a, b| b.1.cmp(a.1).then(a.0.cmp(b.0)));
    println!("{} words, {} distinct", total, counts.len());
    for (w, c) in sorted.iter().take(10) {
        println!("{} {}", w, c);
    }
}
