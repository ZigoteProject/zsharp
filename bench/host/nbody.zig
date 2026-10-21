// N-body (the Benchmarks Game): floating-point arithmetic over arrays updated in place.
const std = @import("std");
const common = @import("common.zig");

const pi = 3.141592653589793;
const solar_mass = 4.0 * pi * pi;
const days_per_year = 365.24;

// the sun, Jupiter, Saturn, Uranus, Neptune
var x = [5]f64{ 0, 4.84143144246472090, 8.34336671824457987, 12.8943695621391310, 15.3796971148509165 };
var y = [5]f64{ 0, -1.16032004402742839, 4.12479856412430479, -15.1111514016986312, -25.9193146099879641 };
var z = [5]f64{ 0, -0.103622044471123109, -0.403523417114321381, -0.223307578892655734, 0.179258772950371181 };
var vx = [5]f64{ 0, 0.00166007664274403694, -0.00276742510726862411, 0.00296460137564761618, 0.00268067772490389322 };
var vy = [5]f64{ 0, 0.00769901118419740425, 0.00499852801234917238, 0.00237847173959480950, 0.00162824170038242295 };
var vz = [5]f64{ 0, -0.0000690460016972063023, 0.0000230417297573763929, -0.0000296589568540237556, -0.0000951592254519715870 };
var m = [5]f64{ 1, 0.000954791938424326609, 0.000285885980666130812, 0.0000436624404335156298, 0.0000515138902046611451 };

fn energy() f64 {
    var e: f64 = 0;
    for (0..5) |i| {
        e += 0.5 * m[i] * (vx[i] * vx[i] + vy[i] * vy[i] + vz[i] * vz[i]);
        for (i + 1..5) |j| {
            const dx = x[i] - x[j];
            const dy = y[i] - y[j];
            const dz = z[i] - z[j];
            e -= m[i] * m[j] / @sqrt(dx * dx + dy * dy + dz * dz);
        }
    }
    return e;
}

pub fn main(init: std.process.Init) void {
    const steps = common.start(init, 1000000);
    for (0..5) |i| {
        vx[i] *= days_per_year;
        vy[i] *= days_per_year;
        vz[i] *= days_per_year;
        m[i] *= solar_mass;
    }
    // the sun moves so that the total momentum is zero
    var px: f64 = 0;
    var py: f64 = 0;
    var pz: f64 = 0;
    for (0..5) |i| {
        px += vx[i] * m[i];
        py += vy[i] * m[i];
        pz += vz[i] * m[i];
    }
    vx[0] = -px / solar_mass;
    vy[0] = -py / solar_mass;
    vz[0] = -pz / solar_mass;
    common.print("{d}\n", .{@as(i64, @intFromFloat(energy() * 1000000000.0))});
    const dt = 0.01;
    var s: i64 = 0;
    while (s < steps) : (s += 1) {
        for (0..5) |i| {
            for (i + 1..5) |j| {
                const dx = x[i] - x[j];
                const dy = y[i] - y[j];
                const dz = z[i] - z[j];
                const d2 = dx * dx + dy * dy + dz * dz;
                const mag = dt / (d2 * @sqrt(d2));
                const mi = m[i] * mag;
                const mj = m[j] * mag;
                vx[i] -= dx * mj;
                vy[i] -= dy * mj;
                vz[i] -= dz * mj;
                vx[j] += dx * mi;
                vy[j] += dy * mi;
                vz[j] += dz * mi;
            }
        }
        for (0..5) |i| {
            x[i] += dt * vx[i];
            y[i] += dt * vy[i];
            z[i] += dt * vz[i];
        }
    }
    common.print("{d}\n", .{@as(i64, @intFromFloat(energy() * 1000000000.0))});
}
