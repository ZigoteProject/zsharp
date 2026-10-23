// XXH3's 128-bit hash (xxHash 0.8.3, compiled from c/xxhash.c): fast, and not for security.

/// XXH128_hash_t: the hash's two 64-bit halves, as XXH3_128bits gives them.
[<CLayout>]
type Hash128 = { low64: u64; high64: u64 }

extern XXH3_128bits : span<u8> -> Hash128

/// XXH3's 128-bit hash of the bytes, as its high and low 64-bit halves.
let hash128 (bytes: span<u8>) : u64 * u64 =
  let h = XXH3_128bits bytes
  (h.high64, h.low64)

/// The 128-bit hash as 32 hex digits, high half first (xxhsum -H2's form).
let hex (bytes: span<u8>) : string =
  let (high, low) = hash128 bytes
  $"{high:x16}{low:x16}"

[<Test>]
let knownHashes () =
  // XXH128_canonicalFromHash's form (what xxhsum -H2 prints), from c/xxhash.h in C
  assert (hex (String.bytes "") = "99aa06d3014798d86001c324468d497f")
  assert (hex (String.bytes "abc") = "06b05ab6733a618578af5f94892f3950")
