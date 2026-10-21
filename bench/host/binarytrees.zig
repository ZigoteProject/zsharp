// Binary trees (the Benchmarks Game): allocating and walking many small trees, with the
// general-purpose allocator.
const std = @import("std");
const common = @import("common.zig");

const Node = struct { l: ?*Node, r: ?*Node };

fn make(d: i64) *Node {
    const n = common.gpa.create(Node) catch @panic("out of memory");
    n.* = if (d == 0) .{ .l = null, .r = null } else .{ .l = make(d - 1), .r = make(d - 1) };
    return n;
}

fn check(n: *const Node) i64 {
    return if (n.l) |l| 1 + check(l) + check(n.r.?) else 1;
}

fn drop(n: *Node) void {
    if (n.l) |l| {
        drop(l);
        drop(n.r.?);
    }
    common.gpa.destroy(n);
}

pub fn main(init: std.process.Init) void {
    const max_depth = @max(6, common.start(init, 16));
    const stretch = max_depth + 1;
    const s = make(stretch);
    common.print("stretch tree of depth {d}\t check: {d}\n", .{ stretch, check(s) });
    drop(s);
    const long_lived = make(max_depth);
    var d: i64 = 4;
    while (d <= max_depth) : (d += 2) {
        const iterations = @as(i64, 1) << @intCast(max_depth - d + 4);
        var total: i64 = 0;
        var i: i64 = 0;
        while (i < iterations) : (i += 1) {
            const t = make(d);
            total += check(t);
            drop(t);
        }
        common.print("{d}\t trees of depth {d}\t check: {d}\n", .{ iterations, d, total });
    }
    common.print("long lived tree of depth {d}\t check: {d}\n", .{ max_depth, check(long_lived) });
    drop(long_lived);
}
