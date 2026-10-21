// Shared by the Zig benchmarks: the size argument, output, and the allocator.
const std = @import("std");

pub const gpa = std.heap.smp_allocator;
var io: std.Io = undefined;

// start keeps the process's Io for print, and returns the size argument
pub fn start(init: std.process.Init, default: i64) i64 {
    io = init.io;
    var args = init.minimal.args.iterate();
    _ = args.skip();
    const a = args.next() orelse return default;
    return std.fmt.parseInt(i64, a, 10) catch default;
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, fmt, args) catch unreachable;
    std.Io.File.stdout().writeStreamingAll(io, s) catch {};
}
