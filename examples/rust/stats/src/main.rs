//! Rust calling a Z# library (stats.zs) through the C ABI: a slice goes as a pointer and a
//! length (read as a span in Z#), a C struct comes back by value, a C string goes as Z#'s cstr.
use std::ffi::{CString, c_char};

/// stats.zs's Summary, a [<CLayout>] record: C's layout (Z#'s int is the word, isize here).
#[repr(C)]
#[derive(Debug)]
struct Summary {
    count: isize,
    mean: f64,
    low: f64,
    high: f64,
}

unsafe extern "C" {
    fn zs_summary(xs: *const f64, n: isize) -> Summary;
    fn zs_median(xs: *const f64, n: isize) -> f64;
    fn zs_words(text: *const c_char) -> isize;
}

fn main() {
    let xs = [3.5, 1.0, 4.0, 1.5, 9.0, 2.5];
    let s = unsafe { zs_summary(xs.as_ptr(), xs.len() as isize) };
    println!("{} numbers, mean {:.3}, from {} to {}", s.count, s.mean, s.low, s.high);
    println!("median {}", unsafe { zs_median(xs.as_ptr(), xs.len() as isize) });
    let text = CString::new("the quick  brown fox").unwrap();
    println!("{} words", unsafe { zs_words(text.as_ptr()) });
}
