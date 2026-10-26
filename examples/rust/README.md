# Rust and Z#, through the C ABI

Two programs, one each way, each on an OS and on a microcontroller (a Cortex-M4 under QEMU):

- **Z# calling Rust** (this folder): `textkit/` is a Rust crate that wraps two crates.io packages,
  [`regex`](https://crates.io/crates/regex) and [`sha2`](https://crates.io/crates/sha2), behind
  `extern "C"` functions, built as a static library. `Textkit.zs` reads its header
  (`textkit/textkit.h`) with `import c` and gives it Z#'s shape: a `Regex` that `use` gives back to
  Rust, a `result` for a bad pattern, Z# strings for Rust's. `zs.toml` links the archive built for
  the target (`[c.host]`, `[c.cortex-m4]`).
- **Rust calling Z#** (`stats/`, and `stats-mcu/` for the chip): a Rust program whose `build.rs`
  builds `stats/stats.zs` with `zs build --lib` and links the archive; `src/main.rs` declares what
  the generated header (`libzstats.h`) declares. On the chip it's a `no_std` firmware started by
  two more crates.io packages, `cortex-m-rt` and `cortex-m-semihosting`.

## Running

```sh
cd examples/rust
cargo build --release --manifest-path textkit/Cargo.toml   # the Rust library
zs run                                                     # the Z# program, linked with it

# on the chip: the crate without the standard library, then the program under QEMU
cargo build --release --manifest-path textkit/Cargo.toml --no-default-features --target thumbv7em-none-eabihf
zs run --target cortex-m4

cd stats
cargo run --release              # needs zs on PATH, or ZS=/path/to/zs
cd ../stats-mcu
cargo run --release              # the firmware, under QEMU (cargo's runner)
```

```text
error at bytes 0..32: 2026-10-26 08:12 ERROR disk full
error at bytes 67..101: 2026-10-27 09:01 ERROR fan stopped
disk full (on 2026-10-26 at 08:12)
2026-10-26 08:15 INFO backup done
fan stopped (on 2026-10-27 at 09:01)
rejected: error: unclosed group
sha256 of "abc": ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
```

```text
6 numbers, mean 3.583, from 1 to 9
median 3
4 words
```

## What crosses, and how

| | C | Rust | Z# |
|---|---|---|---|
| a string | `const char *` | `*const c_char`, read with `CStr` | `cstr`: a Z# string passes as its bytes |
| a string Rust made | `char *` | `CString::into_raw`, given back with `tk_string_free` | copied by `String.ofCStr`, then given back |
| an object | `TkRegex *` (opaque) | `Box::into_raw`, freed by `tk_regex_free` | `cptr` in a record with a `Dispose` impl: `use` gives it back |
| a struct | `TkMatch`, by value | `#[repr(C)]` | a `[<CLayout>]` record (`import c` makes it) |
| a slice, to Z# | `const double *` and a length | `as_ptr()`, `len()` | `ptr<f64>` and `int`, read with `unsafe Span.ofPtr` for the call |
| a struct, from Z# | `Summary`, by value | `#[repr(C)]` | a `[<CLayout>]` record with `[<Export>]` functions |

- **Panics:** the crate is built with `panic = "abort"`, since a Rust panic must not unwind
  through Z#'s frames. A panic in a Z# library stops the process (`zs_set_panic_hook` runs first).
- **Memory:** each side frees its own. Rust's strings and boxes go back to Rust; Z#'s reference
  counts never see them, and Rust never sees Z#'s objects (a `cstr` argument is lent for the call).
- **Z#'s `int`** is the machine word: `isize` in Rust.

## On a chip

- **The crate without `std`:** `--no-default-features` builds it `#![no_std]`. It allocates with
  C's `malloc` and `free`, which the Z# runtime gives a chip (from the Z# heap), and its panic is
  C's `abort`, a Z# panic there. `regex` and `sha2` both build so; `regex` needs atomic
  compare-and-swap for its `Arc`, which a Cortex-M4 has and a Cortex-M0+ doesn't.
- **The heap:** compiling a Unicode-aware pattern takes about 300 KB, so `zs.toml` gives the chip's
  build 512K (`[target.cortex-m4] heap`); the runtime's default is 64K. The run ends with the
  runtime's report, `live=0`: Rust gave back everything it took.
- **A Z# library in a Rust firmware** (`stats-mcu`): `zs build --lib --target cortex-m4` makes an
  archive with the runtime and no startup; the firmware (`cortex-m-rt`'s) defines `zs_write` and
  `zs_stop`, where the library's output and its stop go.

## Other platforms

The same on Linux and Windows (cargo's `--print native-static-libs` lists what a Rust static
library needs from the system; add them to `[c.host]`'s `link` when the link asks for one).
