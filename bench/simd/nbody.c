// The C version of nbody.zs, with AVX (x86-64) or NEON (aarch64) intrinsics.
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#if defined(__AVX2__) || defined(__FMA__)
#include <immintrin.h>
typedef __m256 vec;
#define W 8
#define splat _mm256_set1_ps
#define load _mm256_loadu_ps
#define sub _mm256_sub_ps
#define mul _mm256_mul_ps
#define div_ _mm256_div_ps
#define fma_(a, b, c) _mm256_fmadd_ps(a, b, c)
#define vsqrt _mm256_sqrt_ps
static float hsum(vec v) {
  __m128 h = _mm_add_ps(_mm256_castps256_ps128(v), _mm256_extractf128_ps(v, 1));
  h = _mm_add_ps(h, _mm_movehl_ps(h, h));
  return _mm_cvtss_f32(_mm_add_ss(h, _mm_shuffle_ps(h, h, 1)));
}
#else
#include <arm_neon.h>
typedef float32x4_t vec;
#define W 4
#define splat vdupq_n_f32
#define load vld1q_f32
#define sub vsubq_f32
#define mul vmulq_f32
#define div_ vdivq_f32
#define fma_(a, b, c) vfmaq_f32(c, a, b)
#define vsqrt vsqrtq_f32
static float hsum(vec v) { return vaddvq_f32(v); }
#endif
typedef struct { float *x, *y, *z, *vx, *vy, *vz, *m; } bodies;
static void step(bodies *b, int n, float dt) {
  vec eps = splat(0.01f), one = splat(1.0f);
  for (int i = 0; i < n; i++) {
    vec xi = splat(b->x[i]), yi = splat(b->y[i]), zi = splat(b->z[i]);
    vec ax = splat(0), ay = splat(0), az = splat(0);
    for (int j = 0; j < n; j += W) {
      vec dx = sub(load(b->x + j), xi), dy = sub(load(b->y + j), yi), dz = sub(load(b->z + j), zi);
      vec d2 = fma_(dx, dx, fma_(dy, dy, fma_(dz, dz, eps)));
      vec f = mul(load(b->m + j), div_(one, mul(d2, vsqrt(d2))));
      ax = fma_(dx, f, ax); ay = fma_(dy, f, ay); az = fma_(dz, f, az);
    }
    b->vx[i] += hsum(ax) * dt; b->vy[i] += hsum(ay) * dt; b->vz[i] += hsum(az) * dt;
  }
  for (int i = 0; i < n; i++) { b->x[i] += b->vx[i] * dt; b->y[i] += b->vy[i] * dt; b->z[i] += b->vz[i] * dt; }
}
int main(void) {
  int n = 1024;
  bodies b;
  float **f[] = {&b.x, &b.y, &b.z, &b.vx, &b.vy, &b.vz, &b.m};
  for (int k = 0; k < 7; k++) *f[k] = calloc(n, sizeof(float));
  for (int i = 0; i < n; i++) { b.x[i] = i % 16 + 0.1f * (i % 5); b.y[i] = i / 16 % 16; b.z[i] = i / 256; b.m[i] = 1.0f + i % 3; }
  for (int s = 0; s < 200; s++) step(&b, n, 0.001f);
  double e = 0;
  for (int i = 0; i < n; i++) e += 0.5 * b.m[i] * (double)(b.vx[i] * b.vx[i] + b.vy[i] * b.vy[i] + b.vz[i] * b.vz[i]);
  printf("kinetic energy %.10g\n", e);
}
