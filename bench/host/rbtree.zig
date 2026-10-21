// A red-black tree: inserting a million keys, then looking each one up. An in-place
// left-leaning red-black tree (Sedgewick), the usual way to write one in Zig.
const std = @import("std");
const common = @import("common.zig");

const Node = struct { key: i64, l: ?*Node, r: ?*Node, red: bool };

fn isRed(n: ?*const Node) bool {
    return if (n) |p| p.red else false;
}

fn rotateLeft(h: *Node) *Node {
    const x = h.r.?;
    h.r = x.l;
    x.l = h;
    x.red = h.red;
    h.red = true;
    return x;
}

fn rotateRight(h: *Node) *Node {
    const x = h.l.?;
    h.l = x.r;
    x.r = h;
    x.red = h.red;
    h.red = true;
    return x;
}

fn flip(h: *Node) void {
    h.red = !h.red;
    h.l.?.red = !h.l.?.red;
    h.r.?.red = !h.r.?.red;
}

fn insert(node: ?*Node, k: i64) *Node {
    var h = node orelse {
        const n = common.gpa.create(Node) catch @panic("out of memory");
        n.* = .{ .key = k, .l = null, .r = null, .red = true };
        return n;
    };
    if (k < h.key) h.l = insert(h.l, k) else if (k > h.key) h.r = insert(h.r, k) else return h;
    if (isRed(h.r) and !isRed(h.l)) h = rotateLeft(h);
    if (isRed(h.l) and isRed(h.l.?.l)) h = rotateRight(h);
    if (isRed(h.l) and isRed(h.r)) flip(h);
    return h;
}

fn contains(t: ?*const Node, k: i64) bool {
    var p = t;
    while (p) |n| {
        if (k < n.key) p = n.l else if (k > n.key) p = n.r else return true;
    }
    return false;
}

fn drop(t: ?*Node) void {
    if (t) |n| {
        drop(n.l);
        drop(n.r);
        common.gpa.destroy(n);
    }
}

pub fn main(init: std.process.Init) void {
    const n = common.start(init, 1000000);
    var t: ?*Node = null;
    var seed: i64 = 42;
    var i: i64 = 0;
    while (i < n) : (i += 1) {
        seed = @mod(seed * 1103515245 + 12345, 2147483648);
        const root = insert(t, @mod(seed, n));
        root.red = false;
        t = root;
    }
    var found: i64 = 0;
    i = 0;
    while (i < n) : (i += 1) {
        if (contains(t, i)) found += 1;
    }
    common.print("{d}\n", .{found});
    drop(t);
}
