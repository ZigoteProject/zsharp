// N-body (the Benchmarks Game): floating-point arithmetic over arrays updated in place.
const PI: f64 = 3.141592653589793;
const SOLAR_MASS: f64 = 4.0 * PI * PI;
const DAYS_PER_YEAR: f64 = 365.24;

struct System { x: [f64; 5], y: [f64; 5], z: [f64; 5], vx: [f64; 5], vy: [f64; 5], vz: [f64; 5], m: [f64; 5] }

fn energy(s: &System) -> f64 {
    let mut e = 0.0;
    for i in 0..5 {
        e += 0.5 * s.m[i] * (s.vx[i] * s.vx[i] + s.vy[i] * s.vy[i] + s.vz[i] * s.vz[i]);
        for j in i + 1..5 {
            let (dx, dy, dz) = (s.x[i] - s.x[j], s.y[i] - s.y[j], s.z[i] - s.z[j]);
            e -= s.m[i] * s.m[j] / (dx * dx + dy * dy + dz * dz).sqrt();
        }
    }
    e
}

fn main() {
    let steps: i64 = std::env::args().nth(1).and_then(|a| a.parse().ok()).unwrap_or(1000000);
    // the sun, Jupiter, Saturn, Uranus, Neptune
    let mut s = System {
        x: [0.0, 4.84143144246472090, 8.34336671824457987, 12.8943695621391310, 15.3796971148509165],
        y: [0.0, -1.16032004402742839, 4.12479856412430479, -15.1111514016986312, -25.9193146099879641],
        z: [0.0, -0.103622044471123109, -0.403523417114321381, -0.223307578892655734, 0.179258772950371181],
        vx: [0.0, 0.00166007664274403694, -0.00276742510726862411, 0.00296460137564761618, 0.00268067772490389322],
        vy: [0.0, 0.00769901118419740425, 0.00499852801234917238, 0.00237847173959480950, 0.00162824170038242295],
        vz: [0.0, -0.0000690460016972063023, 0.0000230417297573763929, -0.0000296589568540237556, -0.0000951592254519715870],
        m: [1.0, 0.000954791938424326609, 0.000285885980666130812, 0.0000436624404335156298, 0.0000515138902046611451],
    };
    for i in 0..5 {
        s.vx[i] *= DAYS_PER_YEAR;
        s.vy[i] *= DAYS_PER_YEAR;
        s.vz[i] *= DAYS_PER_YEAR;
        s.m[i] *= SOLAR_MASS;
    }
    // the sun moves so that the total momentum is zero
    let (mut px, mut py, mut pz) = (0.0, 0.0, 0.0);
    for i in 0..5 {
        px += s.vx[i] * s.m[i];
        py += s.vy[i] * s.m[i];
        pz += s.vz[i] * s.m[i];
    }
    s.vx[0] = -px / SOLAR_MASS;
    s.vy[0] = -py / SOLAR_MASS;
    s.vz[0] = -pz / SOLAR_MASS;
    println!("{}", (energy(&s) * 1000000000.0) as i64);
    let dt = 0.01;
    for _ in 0..steps {
        for i in 0..5 {
            for j in i + 1..5 {
                let (dx, dy, dz) = (s.x[i] - s.x[j], s.y[i] - s.y[j], s.z[i] - s.z[j]);
                let d2 = dx * dx + dy * dy + dz * dz;
                let mag = dt / (d2 * d2.sqrt());
                let (mi, mj) = (s.m[i] * mag, s.m[j] * mag);
                s.vx[i] -= dx * mj;
                s.vy[i] -= dy * mj;
                s.vz[i] -= dz * mj;
                s.vx[j] += dx * mi;
                s.vy[j] += dy * mi;
                s.vz[j] += dz * mi;
            }
        }
        for i in 0..5 {
            s.x[i] += dt * s.vx[i];
            s.y[i] += dt * s.vy[i];
            s.z[i] += dt * s.vz[i];
        }
    }
    println!("{}", (energy(&s) * 1000000000.0) as i64);
}
