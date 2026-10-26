//! textkit: two crates.io packages, `regex` and `sha2`, behind a C ABI for Z# (examples/rust).
//!
//! Strings cross as C strings (NUL-terminated UTF-8): Z# passes its strings as they are, and a
//! string Rust makes is given back to Rust with `tk_string_free` once Z# has copied it. A compiled
//! pattern is an opaque handle Z# frees with `tk_regex_free`; results are structs by value.
//! `textkit.h` declares the same functions for Z#'s `import c`. Without the `std` feature it's a
//! `no_std` crate for a chip (README.md).
#![cfg_attr(not(feature = "std"), no_std)]
extern crate alloc;

use alloc::boxed::Box;
use alloc::ffi::CString;
use alloc::format;
use alloc::string::{String, ToString};
use core::ffi::{CStr, c_char};
use core::ptr;

use regex::Regex;
use sha2::{Digest, Sha256};

// a chip, with no standard library: Rust allocates with C's malloc and free (the Z# runtime's
// heap there, or a firmware's C library's), and a panic is C's abort (a Z# panic, on the runtime's)
#[cfg(not(feature = "std"))]
mod bare {
    use core::alloc::{GlobalAlloc, Layout};

    unsafe extern "C" {
        fn malloc(n: usize) -> *mut u8;
        fn free(p: *mut u8);
        fn abort() -> !;
    }

    struct CHeap;

    unsafe impl GlobalAlloc for CHeap {
        unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
            // malloc's blocks are aligned to 8
            if layout.align() > 8 { core::ptr::null_mut() } else { unsafe { malloc(layout.size()) } }
        }

        unsafe fn dealloc(&self, p: *mut u8, _: Layout) {
            unsafe { free(p) }
        }
    }

    #[global_allocator]
    static HEAP: CHeap = CHeap;

    #[panic_handler]
    fn panic(_: &core::panic::PanicInfo) -> ! {
        unsafe { abort() }
    }
}

/// A compiled regular expression, opaque to C.
pub struct TkRegex(Regex);

/// A pattern compiled: the handle, or null with why in `error` (always a string to free, empty
/// when the pattern is valid).
#[repr(C)]
pub struct TkCompiled {
    pub regex: *mut TkRegex,
    pub error: *mut c_char,
}

/// Where a match is: byte offsets into the text, when one was found.
#[repr(C)]
pub struct TkMatch {
    pub found: bool,
    pub start: usize,
    pub stop: usize,
}

// a C string as text (empty when it's null or not UTF-8)
fn text<'a>(s: *const c_char) -> &'a str {
    if s.is_null() {
        return "";
    }
    unsafe { CStr::from_ptr(s) }.to_str().unwrap_or("")
}

// a string for C, which gives it back with tk_string_free
fn owned(s: String) -> *mut c_char {
    CString::new(s).map(CString::into_raw).unwrap_or(ptr::null_mut())
}

/// The pattern compiled (the `regex` crate's syntax), or why it isn't valid.
#[unsafe(no_mangle)]
pub extern "C" fn tk_regex_compile(pattern: *const c_char) -> TkCompiled {
    match Regex::new(text(pattern)) {
        Ok(r) => TkCompiled { regex: Box::into_raw(Box::new(TkRegex(r))), error: owned(String::new()) },
        Err(e) => TkCompiled { regex: ptr::null_mut(), error: owned(e.to_string()) },
    }
}

/// Gives back a compiled pattern.
#[unsafe(no_mangle)]
pub extern "C" fn tk_regex_free(re: *mut TkRegex) {
    if !re.is_null() {
        drop(unsafe { Box::from_raw(re) });
    }
}

/// The first match in the text at or after byte `from`.
#[unsafe(no_mangle)]
pub extern "C" fn tk_regex_find(re: *const TkRegex, text_: *const c_char, from: usize) -> TkMatch {
    let none = TkMatch { found: false, start: 0, stop: 0 };
    let t = text(text_);
    if re.is_null() || from > t.len() || !t.is_char_boundary(from) {
        return none;
    }
    match unsafe { &(*re).0 }.find_at(t, from) {
        Some(m) => TkMatch { found: true, start: m.start(), stop: m.end() },
        None => none,
    }
}

/// The text with every match replaced by `by`, where `$1` names a group: a string to give back.
#[unsafe(no_mangle)]
pub extern "C" fn tk_regex_replace(re: *const TkRegex, text_: *const c_char, by: *const c_char) -> *mut c_char {
    if re.is_null() {
        return owned(text(text_).to_string());
    }
    owned(unsafe { &(*re).0 }.replace_all(text(text_), text(by)).into_owned())
}

/// SHA-256 of the text's bytes, in lower-case hex: a string to give back.
#[unsafe(no_mangle)]
pub extern "C" fn tk_sha256_hex(text_: *const c_char) -> *mut c_char {
    let digest = Sha256::digest(text(text_).as_bytes());
    owned(digest.iter().map(|b| format!("{b:02x}")).collect())
}

/// Gives back a string this library made.
#[unsafe(no_mangle)]
pub extern "C" fn tk_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(unsafe { CString::from_raw(s) });
    }
}
