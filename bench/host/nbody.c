// N-body (the Benchmarks Game): floating-point arithmetic over arrays updated in place.
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define PI 3.141592653589793
#define SOLAR_MASS (4 * PI * PI)
#define DAYS_PER_YEAR 365.24

static double x[5] = {0, 4.84143144246472090, 8.34336671824457987, 12.8943695621391310, 15.3796971148509165};
static double y[5] = {0, -1.16032004402742839, 4.12479856412430479, -15.1111514016986312, -25.9193146099879641};
static double z[5] = {0, -0.103622044471123109, -0.403523417114321381, -0.223307578892655734, 0.179258772950371181};
static double vx[5] = {0, 0.00166007664274403694, -0.00276742510726862411, 0.00296460137564761618, 0.00268067772490389322};
static double vy[5] = {0, 0.00769901118419740425, 0.00499852801234917238, 0.00237847173959480950, 0.00162824170038242295};
static double vz[5] = {0, -0.0000690460016972063023, 0.0000230417297573763929, -0.0000296589568540237556, -0.0000951592254519715870};
static double m[5] = {1, 0.000954791938424326609, 0.000285885980666130812, 0.0000436624404335156298, 0.0000515138902046611451};

static double energy(void) {
    double e = 0;
    for (int i = 0; i < 5; i++) {
        e += 0.5 * m[i] * (vx[i] * vx[i] + vy[i] * vy[i] + vz[i] * vz[i]);
        for (int j = i + 1; j < 5; j++) {
            double dx = x[i] - x[j], dy = y[i] - y[j], dz = z[i] - z[j];
            e -= m[i] * m[j] / sqrt(dx * dx + dy * dy + dz * dz);
        }
    }
    return e;
}

int main(int argc, char **argv) {
    long steps = argc > 1 ? atol(argv[1]) : 1000000;
    for (int i = 0; i < 5; i++) {
        vx[i] *= DAYS_PER_YEAR; vy[i] *= DAYS_PER_YEAR; vz[i] *= DAYS_PER_YEAR;
        m[i] *= SOLAR_MASS;
    }
    double px = 0, py = 0, pz = 0;
    for (int i = 0; i < 5; i++) { px += vx[i] * m[i]; py += vy[i] * m[i]; pz += vz[i] * m[i]; }
    vx[0] = -px / SOLAR_MASS; vy[0] = -py / SOLAR_MASS; vz[0] = -pz / SOLAR_MASS;
    printf("%ld\n", (long)(energy() * 1000000000.0));
    double dt = 0.01;
    for (long s = 0; s < steps; s++) {
        for (int i = 0; i < 5; i++)
            for (int j = i + 1; j < 5; j++) {
                double dx = x[i] - x[j], dy = y[i] - y[j], dz = z[i] - z[j];
                double d2 = dx * dx + dy * dy + dz * dz;
                double mag = dt / (d2 * sqrt(d2));
                double mi = m[i] * mag, mj = m[j] * mag;
                vx[i] -= dx * mj; vy[i] -= dy * mj; vz[i] -= dz * mj;
                vx[j] += dx * mi; vy[j] += dy * mi; vz[j] += dz * mi;
            }
        for (int i = 0; i < 5; i++) { x[i] += dt * vx[i]; y[i] += dt * vy[i]; z[i] += dt * vz[i]; }
    }
    printf("%ld\n", (long)(energy() * 1000000000.0));
    return 0;
}
