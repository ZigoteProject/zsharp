//! cryptokit: Zig's standard library cryptography behind a C ABI (cryptokit.h declares the same
//! functions). Bytes cross as a pointer and a length, as C cryptography libraries pass them:
//! Z#'s span (an array, a Buffer, a string's bytes) is exactly that, and a Buffer is where a
//! result is written. Nothing allocates, so it runs on a chip as on an OS.
//!
//! Why not structs of bytes by value: Zig 0.17 passes a struct by value on 32-bit Arm as 8-byte
//! pieces whatever its alignment, where AAPCS (clang's, and Z#'s) passes one aligned to 4 or less
//! as words, so C and Zig disagree about where such an argument is on a Cortex-M.
const std = @import("std");
const Ed25519 = std.crypto.sign.Ed25519;
const Blake3 = std.crypto.hash.Blake3;

// n bytes at p, which must be `want` long
fn exactly(comptime want: usize, p: [*]const u8, n: usize, comptime what: []const u8) *const [want]u8 {
    if (n != want) @panic("cryptokit: " ++ what ++ " is not " ++ std.fmt.comptimePrint("{d}", .{want}) ++ " bytes");
    return p[0..want];
}

/// CRC-32 (ISO-HDLC, zlib's) of the n bytes at p.
export fn ck_crc32(p: [*]const u8, n: usize) u32 {
    return std.hash.Crc32.hash(p[0..n]);
}

/// BLAKE3 of the n bytes at p, into the 32 bytes at out.
export fn ck_blake3(p: [*]const u8, n: usize, out: [*]u8, out_len: usize) void {
    _ = exactly(32, out, out_len, "a digest");
    Blake3.hash(p[0..n], out[0..32], .{});
}

// the key pair a 32-byte seed makes
fn pair(seed: [*]const u8, seed_len: usize) Ed25519.KeyPair {
    return Ed25519.KeyPair.generateDeterministic(exactly(32, seed, seed_len, "a seed").*) catch @panic("cryptokit: a seed that makes no key pair");
}

/// The public key of the key pair the 32-byte seed makes, into the 32 bytes at out.
export fn ck_public_key(seed: [*]const u8, seed_len: usize, out: [*]u8, out_len: usize) void {
    _ = exactly(32, out, out_len, "a public key");
    out[0..32].* = pair(seed, seed_len).public_key.toBytes();
}

/// The message signed with the key pair the 32-byte seed makes, into the 64 bytes at out.
export fn ck_sign(seed: [*]const u8, seed_len: usize, message: [*]const u8, message_len: usize, out: [*]u8, out_len: usize) void {
    _ = exactly(64, out, out_len, "a signature");
    const signature = pair(seed, seed_len).sign(message[0..message_len], null) catch @panic("cryptokit: signing failed");
    out[0..64].* = signature.toBytes();
}

/// Whether the 64-byte signature is the message's by the 32-byte public key.
export fn ck_verify(key: [*]const u8, key_len: usize, message: [*]const u8, message_len: usize, signature: [*]const u8, signature_len: usize) bool {
    if (key_len != 32 or signature_len != 64) return false;
    const public_key = Ed25519.PublicKey.fromBytes(key[0..32].*) catch return false;
    Ed25519.Signature.fromBytes(signature[0..64].*).verify(message[0..message_len], public_key) catch return false;
    return true;
}
