//! Zig calling a Z# library (shapes.zs) through the C ABI: build.zig translates the header that
//! zs build --lib wrote beside the archive (the module "shapes"), and links the archive.
const std = @import("std");
const zs = @import("shapes");

// a C function pointer Z# calls: each prime
fn onPrime(p: isize) callconv(.c) void {
    std.debug.print("{d} ", .{p});
}

pub fn main() void {
    var square = [_]zs.Point{ .{ .x = 0, .y = 0 }, .{ .x = 2, .y = 0 }, .{ .x = 2, .y = 2 }, .{ .x = 0, .y = 2 } };
    std.debug.print("area {d}\n", .{zs.zs_area(&square, square.len)});
    const m = zs.zs_middle(square[0], square[2]);
    std.debug.print("middle {d} {d}\n", .{ m.x, m.y });
    const n = zs.zs_primes(30, onPrime);
    std.debug.print("\n{d} primes\n", .{n});
}
