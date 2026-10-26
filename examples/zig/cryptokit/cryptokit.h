// cryptokit: Zig's standard library cryptography behind a C ABI (src/cryptokit.zig, the same
// declarations). Bytes are a pointer and a length; a result is written to the bytes at out.
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// CRC-32 (ISO-HDLC, zlib's) of the n bytes at p
uint32_t ck_crc32(const uint8_t *p, size_t n);

// BLAKE3 of the n bytes at p, into the 32 bytes at out
void ck_blake3(const uint8_t *p, size_t n, uint8_t *out, size_t out_len);

// the public key of the key pair the 32-byte seed makes, into the 32 bytes at out
void ck_public_key(const uint8_t *seed, size_t seed_len, uint8_t *out, size_t out_len);

// the message signed with the key pair the 32-byte seed makes, into the 64 bytes at out
void ck_sign(const uint8_t *seed, size_t seed_len, const uint8_t *message, size_t message_len, uint8_t *out, size_t out_len);

// whether the 64-byte signature is the message's by the 32-byte public key
bool ck_verify(const uint8_t *key, size_t key_len, const uint8_t *message, size_t message_len, const uint8_t *signature, size_t signature_len);
