// Hashing, as a backup tool or a content-addressed store does it: m MiB of data, made of 4 KiB
// chunks that often repeat, is hashed whole with SHA-256 (FIPS 180-4, written here); each chunk
// is hashed on its own and named by its hex digest; the distinct names are counted in a hash set,
// and the chunk digests hashed into a root.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHUNK 4096

static int64_t next(int64_t seed) { return (seed * 1103515245 + 12345) % 2147483648; }

static const uint32_t k[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

static uint32_t rotr(uint32_t x, int n) { return (x >> n) | (x << (32 - n)); }

static void compress(uint32_t h[8], const uint8_t *block) {
  uint32_t w[64];
  for (int t = 0; t < 16; t++)
    w[t] = (uint32_t)block[4 * t] << 24 | (uint32_t)block[4 * t + 1] << 16 | (uint32_t)block[4 * t + 2] << 8 | block[4 * t + 3];
  for (int t = 16; t < 64; t++) {
    uint32_t s0 = rotr(w[t - 15], 7) ^ rotr(w[t - 15], 18) ^ (w[t - 15] >> 3);
    uint32_t s1 = rotr(w[t - 2], 17) ^ rotr(w[t - 2], 19) ^ (w[t - 2] >> 10);
    w[t] = w[t - 16] + s0 + w[t - 7] + s1;
  }
  uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
  for (int t = 0; t < 64; t++) {
    uint32_t t1 = hh + (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) + ((e & f) ^ (~e & g)) + k[t] + w[t];
    uint32_t t2 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
  }
  h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
}

static void sha256(const uint8_t *data, size_t n, uint8_t out[32]) {
  uint32_t h[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
  size_t at = 0;
  for (; at + 64 <= n; at += 64) compress(h, data + at);
  uint8_t tail[128] = {0};
  size_t rest = n - at, len = rest < 56 ? 64 : 128;
  memcpy(tail, data + at, rest);
  tail[rest] = 0x80;
  uint64_t bits = (uint64_t)n * 8;
  for (int i = 0; i < 8; i++) tail[len - 1 - i] = (uint8_t)(bits >> (8 * i));
  compress(h, tail);
  if (len == 128) compress(h, tail + 64);
  for (int i = 0; i < 32; i++) out[i] = (uint8_t)(h[i / 4] >> (24 - 8 * (i % 4)));
}

static void hex(const uint8_t d[32], char out[65]) {
  for (int i = 0; i < 32; i++) sprintf(out + 2 * i, "%02x", d[i]);
}

// a set of hex names: open addressing on FNV-1a
typedef struct { char (*names)[65]; size_t cap, size; } Set;

static uint64_t fnv1a(const char *s) {
  uint64_t h = 14695981039346656037ull;
  for (; *s; s++) h = (h ^ (unsigned char)*s) * 1099511628211ull;
  return h;
}

static void insert(Set *s, const char *name);

static void grow(Set *s) {
  Set bigger = {calloc(s->cap ? s->cap * 2 : 64, 65), s->cap ? s->cap * 2 : 64, 0};
  for (size_t i = 0; i < s->cap; i++)
    if (s->names[i][0]) insert(&bigger, s->names[i]);
  free(s->names);
  *s = bigger;
}

static void insert(Set *s, const char *name) {
  if (2 * (s->size + 1) > s->cap) grow(s);
  size_t j = fnv1a(name) & (s->cap - 1);
  for (; s->names[j][0]; j = (j + 1) & (s->cap - 1))
    if (strcmp(s->names[j], name) == 0) return;
  strcpy(s->names[j], name);
  s->size++;
}

int main(int argc, char **argv) {
  size_t size = (size_t)(argc > 1 ? atoi(argv[1]) : 64) * 1048576, chunks = size / CHUNK;
  uint8_t *data = malloc(size), d[32];
  char name[65];
  for (size_t c = 0; c < chunks; c++) {
    int64_t seed = 1 + (int64_t)(c * c % 251); // so chunks repeat, as blocks of real files do
    for (size_t i = c * CHUNK; i < (c + 1) * CHUNK; i++) {
      seed = next(seed);
      data[i] = (uint8_t)(seed >> 16 & 255);
    }
  }
  sha256(data, size, d);
  hex(d, name);
  printf("whole: %s\n", name);
  Set seen = {0};
  uint8_t *digests = malloc(chunks * 32);
  for (size_t c = 0; c < chunks; c++) {
    sha256(data + c * CHUNK, CHUNK, digests + 32 * c);
    hex(digests + 32 * c, name);
    insert(&seen, name);
  }
  printf("%zu chunks, %zu distinct\n", chunks, seen.size);
  sha256(digests, chunks * 32, d);
  hex(d, name);
  printf("root: %s\n", name);
  free(seen.names);
  free(digests);
  free(data);
  return 0;
}
