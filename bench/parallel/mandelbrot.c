// The C version of mandelbrot.zs, with pthreads taking one row at a time: what the machine
// allows (bench/parallel/run.sh). Arguments: n, threads.
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
static int n; static atomic_int next; static long counts[64];
static int row(int y) {
  double ci = 3.0 * y / n - 1.5; int count = 0;
  for (int x = 0; x < n; x++) {
    double cr = 3.0 * x / n - 2.0, zr = 0, zi = 0; int i = 0;
    while (i < 50 && zr * zr + zi * zi <= 4.0) { double t = zr * zr - zi * zi + cr; zi = 2.0 * zr * zi + ci; zr = t; i++; }
    if (i == 50) count++;
  }
  return count;
}
static void *work(void *a) { long k = (long)a; for (int y; (y = atomic_fetch_add(&next, 1)) < n;) counts[k] += row(y); return 0; }
int main(int argc, char **argv) {
  n = atoi(argv[1]); int t = atoi(argv[2]); pthread_t th[64];
  for (long k = 0; k < t; k++) pthread_create(&th[k], 0, work, (void *)k);
  long total = 0; for (int k = 0; k < t; k++) { pthread_join(th[k], 0); total += counts[k]; }
  printf("%ld\n", total);
}
