//! A Rust firmware for a Cortex-M4 calling a Z# library (../stats/stats.zs) through the C ABI,
//! as ../stats/src/main.rs does on an OS: cortex-m-rt starts the chip, and the Z# library's output
//! and stop are the firmware's (zs_write and zs_stop), here the debugger's console.
#![no_std]
#![no_main]

use core::ffi::c_char;
use core::fmt::Write;

use cortex_m_rt::entry;
use cortex_m_semihosting::{debug, hio, hprintln};

/// stats.zs's Summary, a [<CLayout>] record: C's layout (Z#'s int is the chip's word, isize here).
#[repr(C)]
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

/// The Z# library's output (println, a panic's message): the debugger's console.
#[unsafe(no_mangle)]
pub extern "C" fn zs_write(p: *const u8, n: usize) {
    if let Ok(mut out) = hio::hstdout() {
        let _ = out.write_all(unsafe { core::slice::from_raw_parts(p, n) });
    }
}

/// The Z# library's stop, after a panic.
#[unsafe(no_mangle)]
pub extern "C" fn zs_stop(_code: i32) -> ! {
    debug::exit(debug::EXIT_FAILURE);
    loop {}
}

#[entry]
fn main() -> ! {
    let xs = [3.5, 1.0, 4.0, 1.5, 9.0, 2.5];
    let s = unsafe { zs_summary(xs.as_ptr(), xs.len() as isize) };
    hprintln!("{} numbers, mean {:.3}, from {} to {}", s.count, s.mean, s.low, s.high);
    hprintln!("median {}", unsafe { zs_median(xs.as_ptr(), xs.len() as isize) });
    hprintln!("{} words", unsafe { zs_words(c"the quick  brown fox".as_ptr()) });
    debug::exit(debug::EXIT_SUCCESS);
    loop {}
}

#[panic_handler]
fn panic(info: &core::panic::PanicInfo) -> ! {
    if let Ok(mut out) = hio::hstdout() {
        let _ = writeln!(out, "{info}");
    }
    debug::exit(debug::EXIT_FAILURE);
    loop {}
}
