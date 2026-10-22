// The C version of dot.zs, with AVX (x86-64) or NEON (aarch64) intrinsics.
#include <stdio.h>
#include <stdlib.h>
#if defined(__AVX2__) || defined(__FMA__)
#include <immintrin.h>
static float dot(const float *a, const float *b, int n) {
  __m256 acc0 = _mm256_setzero_ps(), acc1 = _mm256_setzero_ps();
  int i = 0;
  for (; i + 16 <= n; i += 16) {
    acc0 = _mm256_fmadd_ps(_mm256_loadu_ps(a + i), _mm256_loadu_ps(b + i), acc0);
    acc1 = _mm256_fmadd_ps(_mm256_loadu_ps(a + i + 8), _mm256_loadu_ps(b + i + 8), acc1);
  }
  __m256 s = _mm256_add_ps(acc0, acc1);
  __m128 h = _mm_add_ps(_mm256_castps256_ps128(s), _mm256_extractf128_ps(s, 1));
  h = _mm_add_ps(h, _mm_movehl_ps(h, h));
  h = _mm_add_ss(h, _mm_shuffle_ps(h, h, 1));
  float total = _mm_cvtss_f32(h);
  for (; i < n; i++) total += a[i] * b[i];
  return total;
}
#else
#include <arm_neon.h>
static float dot(const float *a, const float *b, int n) {
  float32x4_t acc0 = vdupq_n_f32(0), acc1 = vdupq_n_f32(0), acc2 = vdupq_n_f32(0), acc3 = vdupq_n_f32(0);
  int i = 0;
  for (; i + 16 <= n; i += 16) {
    acc0 = vfmaq_f32(acc0, vld1q_f32(a + i), vld1q_f32(b + i));
    acc1 = vfmaq_f32(acc1, vld1q_f32(a + i + 4), vld1q_f32(b + i + 4));
    acc2 = vfmaq_f32(acc2, vld1q_f32(a + i + 8), vld1q_f32(b + i + 8));
    acc3 = vfmaq_f32(acc3, vld1q_f32(a + i + 12), vld1q_f32(b + i + 12));
  }
  float total = vaddvq_f32(vaddq_f32(vaddq_f32(acc0, acc2), vaddq_f32(acc1, acc3)));
  for (; i < n; i++) total += a[i] * b[i];
  return total;
}
#endif
int main(void) {
  int n = 4096;
  float *a = malloc(n * sizeof(float)), *b = malloc(n * sizeof(float));
  for (int i = 0; i < n; i++) { a[i] = (i % 7) * 0.25f; b[i] = (i % 5) * 0.5f; }
  float s = 0;
  for (int r = 0; r < 200000; r++) s += dot(a, b, n);
  printf("%g\n", s);
}
