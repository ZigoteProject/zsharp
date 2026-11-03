// Hashing, as a backup tool or a content-addressed store does it: m MiB of data, made of 4 KiB
// chunks that often repeat, is hashed whole with SHA-256 (FIPS 180-4, written here: the
// standard library has none); each chunk is hashed on its own and named by its hex digest; the
// distinct names are counted in a HashSet, and the chunk digests hashed into a root.
use std::collections::HashSet;
use std::fmt::Write;

const CHUNK: usize = 4096;

const K: [u32; 64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

fn next(seed: i64) -> i64 {
    (seed * 1103515245 + 12345) % 2147483648
}

fn compress(h: &mut [u32; 8], block: &[u8]) {
    let mut w = [0u32; 64];
    for t in 0..16 {
        w[t] = u32::from_be_bytes(block[4 * t..4 * t + 4].try_into().unwrap());
    }
    for t in 16..64 {
        let s0 = w[t - 15].rotate_right(7) ^ w[t - 15].rotate_right(18) ^ (w[t - 15] >> 3);
        let s1 = w[t - 2].rotate_right(17) ^ w[t - 2].rotate_right(19) ^ (w[t - 2] >> 10);
        w[t] = w[t - 16].wrapping_add(s0).wrapping_add(w[t - 7]).wrapping_add(s1);
    }
    let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut hh] = *h;
    for t in 0..64 {
        let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
        let ch = (e & f) ^ (!e & g);
        let t1 = hh.wrapping_add(s1).wrapping_add(ch).wrapping_add(K[t]).wrapping_add(w[t]);
        let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
        let t2 = s0.wrapping_add((a & b) ^ (a & c) ^ (b & c));
        hh = g;
        g = f;
        f = e;
        e = d.wrapping_add(t1);
        d = c;
        c = b;
        b = a;
        a = t1.wrapping_add(t2);
    }
    for (x, y) in h.iter_mut().zip([a, b, c, d, e, f, g, hh]) {
        *x = x.wrapping_add(y);
    }
}

fn sha256(data: &[u8]) -> [u8; 32] {
    let mut h: [u32; 8] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
    let mut blocks = data.chunks_exact(64);
    for block in &mut blocks {
        compress(&mut h, block);
    }
    let rest = blocks.remainder();
    let len = if rest.len() < 56 { 64 } else { 128 };
    let mut tail = [0u8; 128];
    tail[..rest.len()].copy_from_slice(rest);
    tail[rest.len()] = 0x80;
    tail[len - 8..len].copy_from_slice(&(data.len() as u64 * 8).to_be_bytes());
    compress(&mut h, &tail[..64]);
    if len == 128 {
        compress(&mut h, &tail[64..]);
    }
    let mut out = [0u8; 32];
    for (i, x) in h.iter().enumerate() {
        out[4 * i..4 * i + 4].copy_from_slice(&x.to_be_bytes());
    }
    out
}

fn hex(d: &[u8]) -> String {
    let mut s = String::with_capacity(64);
    for b in d {
        write!(s, "{:02x}", b).unwrap();
    }
    s
}

fn main() {
    let mib: usize = std::env::args().nth(1).and_then(|a| a.parse().ok()).unwrap_or(64);
    let size = mib * 1048576;
    let mut data = vec![0u8; size];
    for (c, block) in data.chunks_exact_mut(CHUNK).enumerate() {
        let mut seed = 1 + (c * c % 251) as i64; // so chunks repeat, as blocks of real files do
        for b in block {
            seed = next(seed);
            *b = (seed >> 16 & 255) as u8;
        }
    }
    println!("whole: {}", hex(&sha256(&data)));
    let mut seen = HashSet::new();
    let mut digests = Vec::with_capacity(size / CHUNK * 32);
    for block in data.chunks_exact(CHUNK) {
        let d = sha256(block);
        seen.insert(hex(&d));
        digests.extend_from_slice(&d);
    }
    println!("{} chunks, {} distinct", size / CHUNK, seen.len());
    println!("root: {}", hex(&sha256(&digests)));
}
