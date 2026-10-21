// Spectral norm (the Benchmarks Game): floating-point loops over arrays.
const std = @import("std");
const common = @import("common.zig");

fn a(i: usize, j: usize) f64 {
    return 1.0 / @as(f64, @floatFromInt((i + j) * (i + j + 1) / 2 + i + 1));
}

fn multiplyAv(v: []const f64, av: []f64) void {
    for (av, 0..) |*out, i| {
        var s: f64 = 0;
        for (v, 0..) |vj, j| s += a(i, j) * vj;
        out.* = s;
    }
}

fn multiplyAtv(v: []const f64, atv: []f64) void {
    for (atv, 0..) |*out, i| {
        var s: f64 = 0;
        for (v, 0..) |vj, j| s += a(j, i) * vj;
        out.* = s;
    }
}

fn multiplyAtAv(v: []const f64, atav: []f64, tmp: []f64) void {
    multiplyAv(v, tmp);
    multiplyAtv(tmp, atav);
}

pub fn main(init: std.process.Init) void {
    const n: usize = @intCast(common.start(init, 1000));
    const u = common.gpa.alloc(f64, n) catch @panic("out of memory");
    const v = common.gpa.alloc(f64, n) catch @panic("out of memory");
    const tmp = common.gpa.alloc(f64, n) catch @panic("out of memory");
    defer common.gpa.free(u);
    defer common.gpa.free(v);
    defer common.gpa.free(tmp);
    @memset(u, 1);
    for (0..10) |_| {
        multiplyAtAv(u, v, tmp);
        multiplyAtAv(v, u, tmp);
    }
    var vbv: f64 = 0;
    var vv: f64 = 0;
    for (u, v) |ui, vi| {
        vbv += ui * vi;
        vv += vi * vi;
    }
    common.print("{d}\n", .{@as(i64, @intFromFloat(@sqrt(vbv / vv) * 1000000000.0))});
}
