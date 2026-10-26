# Zig and Z#, through the C ABI

Two programs, one each way, each on an OS and on a microcontroller (a Cortex-M4 under QEMU):

- **Z# calling Zig** (this folder): `cryptokit/` is a Zig package that puts its standard
  library's cryptography (BLAKE3, Ed25519 signatures, CRC-32) behind `export fn`s and builds as a
  static library. `main.zs` declares the functions as `extern`s, and `zs.toml` links the archive
  built for the target.
- **Zig calling Z#** (`calls-zs/`): `build.zig` builds `shapes.zs` with `zs build --lib`,
  translates its header into a Zig module and links the archive, into a program (`main.zig`) and
  into a firmware with its own startup (`firmware.zig`).

## Running

```sh
cd examples/zig/cryptokit
zig build -Doptimize=ReleaseFast                       # the Zig library for this machine
zig build -Doptimize=ReleaseSmall -Dtarget=thumb-freestanding-eabihf -Dcpu=cortex_m4+vfp4d16sp \
  --prefix zig-out/cortex-m4                           # and for a Cortex-M4
cd ..
zs run                       # the Z# program, here
zs run --target cortex-m4    # the same program on the chip, under QEMU (qemu-system-arm)
```

```text
crc32  A5483BA3
blake3 8af58fde790b256dc00a8c7f99a39fae3d688adbd7ffd1cd9621354665440c81
public e4030998cfd5ad1723c169f956aa0b9eb8619b5992bd612c2af428ebc79f8df0
signed, verifies: true
tampered, verifies: false
```

```sh
cd calls-zs
zig build run      # the program, here (zs on PATH, or -Dzs=/path/to/zs)
zig build qemu     # the firmware, on a Cortex-M4 under QEMU
```

```text
area 4
middle 1 1
2 3 5 7 11 13 17 19 23 29
10 primes
```

## What crosses, and how

| | C | Zig | Z# |
|---|---|---|---|
| bytes | `const uint8_t *p, size_t n` | `[*]const u8` and a length | a `span<u8>` in an `extern`: a string's bytes (`String.bytes`), an array, a `Buffer` |
| a result's bytes | `uint8_t *out, size_t out_len` | `[*]u8`, written | a `Buffer<u8>`, whose bytes C writes |
| a struct of floats | `Point`, by value | an `extern struct` | a `[<CLayout>]` record with `[<Export>]` functions |
| an array of structs | `Point *` and a length | `&points`, `points.len` | `ptr<Point>` and `int`, read with `unsafe Span.ofPtr` for the call |
| a function pointer | `void (*)(intptr_t)` | `fn (isize) callconv(.c) void` | `fnptr<int -> unit>`, called in `unsafe` |

- **On a chip:** the library builds for `thumb-freestanding-eabihf` (with the Cortex-M4F's FPU:
  `+vfp4d16sp`, whose registers carry float arguments in the hard-float convention) and links
  into the Z# image; `cryptokit` allocates nothing. Zig's firmware gives the Z# library its
  output and its stop by exporting `zs_write` and `zs_stop`.
- **Structs of bytes by value don't cross on 32-bit Arm:** Zig 0.17 passes a struct by value
  there as 8-byte pieces whatever its alignment, where the Arm convention (clang's, and Z#'s) passes
  one aligned to 4 or less as words, so a C or Z# caller and a Zig callee disagree about where it
  is. Float structs go in float registers and agree (`Point` above). Bytes as a pointer and a
  length, as C cryptography libraries take them, work everywhere.
- **Memory:** each side frees its own; `cryptokit` writes into buffers Z# owns.
