// The C version of blur.zs, with AVX (x86-64) or NEON (aarch64) intrinsics: the same two
// images, blurred one into the other.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if defined(__AVX2__) || defined(__FMA__)
#include <immintrin.h>
typedef __m256 vec;
#define W 8
#define splat _mm256_set1_ps
#define load _mm256_loadu_ps
#define store _mm256_storeu_ps
#define add _mm256_add_ps
#define mul _mm256_mul_ps
#else
#include <arm_neon.h>
typedef float32x4_t vec;
#define W 4
#define splat vdupq_n_f32
#define load vld1q_f32
#define store vst1q_f32
#define add vaddq_f32
#define mul vmulq_f32
#endif
// src blurred into out, whose border stays as it was
static void blur(const float *src, float *out, int w, int h) {
  vec ninth = splat(1.0f / 9.0f);
  for (int y = 1; y < h - 1; y++) {
    const float *up = src + (y - 1) * w, *row = src + y * w, *down = src + (y + 1) * w;
    int x = 1;
    for (; x + 8 <= w - 1; x += 8)
      for (int k = 0; k < 8; k += W) {
        int i = x + k;
        vec a = add(add(load(up + i - 1), load(up + i)), load(up + i + 1));
        vec b = add(add(load(row + i - 1), load(row + i)), load(row + i + 1));
        vec c = add(add(load(down + i - 1), load(down + i)), load(down + i + 1));
        store(out + y * w + i, mul(add(add(a, b), c), ninth));
      }
    for (; x < w - 1; x++)
      out[y * w + x] = (up[x - 1] + up[x] + up[x + 1] + row[x - 1] + row[x] + row[x + 1] + down[x - 1] + down[x] + down[x + 1]) / 9.0f;
  }
}
int main(void) {
  int w = 2048, h = 2048;
  float *img = malloc(sizeof(float) * w * h), *tmp = malloc(sizeof(float) * w * h);
  for (int i = 0; i < w * h; i++) img[i] = (float)((i * 7919) % 256);
  memcpy(tmp, img, sizeof(float) * w * h);
  for (int r = 0; r < 20; r++) {
    blur(img, tmp, w, h);
    float *t = img; img = tmp; tmp = t;
  }
  double total = 0;
  for (int i = 0; i < w * h; i++) total += img[i];
  printf("sum %.17g\n", total);
}
