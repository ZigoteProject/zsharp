// Recursive Fibonacci: calls and integer arithmetic (ReleaseFast: overflow is unchecked).
const std = @import("std");
const common = @import("common.zig");

fn fib(n: i64) i64 {
    return if (n < 2) n else fib(n - 1) + fib(n - 2);
}

pub fn main(init: std.process.Init) void {
    common.print("{d}\n", .{fib(common.start(init, 32))});
}
