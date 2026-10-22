// The C version of nbody.zs, with pthreads taking 16 bodies at a time and a barrier between
// steps: what the machine allows (bench/parallel/run.sh). Arguments: n, threads.
#include <math.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
typedef struct { double x, y, z, vx, vy, vz, m; } body;
static int n, T; static body *b; static double (*acc)[3]; static atomic_int next; static pthread_barrier_t bar;
static void accel(int i) {
  double ax = 0, ay = 0, az = 0;
  for (int j = 0; j < n; j++) if (j != i) {
    double dx = b[j].x - b[i].x, dy = b[j].y - b[i].y, dz = b[j].z - b[i].z, d2 = dx * dx + dy * dy + dz * dz + 0.01, f = b[j].m / (d2 * sqrt(d2));
    ax += dx * f; ay += dy * f; az += dz * f;
  }
  acc[i][0] = ax; acc[i][1] = ay; acc[i][2] = az;
}
static void *work(void *a) {
  for (int s = 0; s < 10; s++) {
    for (int i; (i = atomic_fetch_add(&next, 16)) < n;) for (int k = i; k < i + 16 && k < n; k++) accel(k);
    pthread_barrier_wait(&bar);
    if (a == 0) { for (int i = 0; i < n; i++) { b[i].vx += acc[i][0] * 0.001; b[i].vy += acc[i][1] * 0.001; b[i].vz += acc[i][2] * 0.001; b[i].x += b[i].vx * 0.001; b[i].y += b[i].vy * 0.001; b[i].z += b[i].vz * 0.001; } atomic_store(&next, 0); }
    pthread_barrier_wait(&bar);
  }
  return 0;
}
int main(int argc, char **argv) {
  n = atoi(argv[1]); T = atoi(argv[2]); b = calloc(n, sizeof(body)); acc = calloc(n, sizeof *acc);
  int side = 1; while (side * side * side < n) side++;
  for (int i = 0; i < n; i++) b[i] = (body){i % side + 0.1 * (i % 5), i / side % side, i / (side * side), 0, 0, 0, 1.0 + i % 3};
  pthread_barrier_init(&bar, 0, T); pthread_t th[64];
  for (long k = 0; k < T; k++) pthread_create(&th[k], 0, work, (void *)k);
  for (int k = 0; k < T; k++) pthread_join(th[k], 0);
  double e = 0; for (int i = 0; i < n; i++) e += 0.5 * b[i].m * (b[i].vx * b[i].vx + b[i].vy * b[i].vy + b[i].vz * b[i].vz);
  printf("%.10f\n", e);
}
