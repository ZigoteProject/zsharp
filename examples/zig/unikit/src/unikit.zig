//! unikit: zg's Unicode text processing behind a C ABI (unikit.h declares the same functions).
//! Strings cross as C strings (NUL-terminated UTF-8); a string this library makes is C memory
//! (malloc), given back with uk_free. It builds for an OS and for a chip alike: its memory is C's
//! malloc and free, the C library's on an OS and the Z# runtime's on a chip.
const std = @import("std");
const Graphemes = @import("Graphemes");
const DisplayWidth = @import("DisplayWidth");
const LetterCasing = @import("LetterCasing");
const Normalize = @import("Normalize");
const CaselessMatch = @import("CaselessMatch");

extern fn malloc(n: usize) ?[*]u8;
extern fn free(p: ?*anyopaque) void;

// C's malloc and free as an Allocator (std.heap.c_allocator needs a C library linked, which a
// chip has none of)
const allocator: std.mem.Allocator = .{ .ptr = undefined, .vtable = &.{
    .alloc = cAlloc,
    .resize = std.mem.Allocator.noResize,
    .remap = std.mem.Allocator.noRemap,
    .free = cFree,
} };

fn cAlloc(_: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
    // malloc's blocks are aligned to 8
    if (alignment.toByteUnits() > 8) return null;
    return malloc(len);
}

fn cFree(_: *anyopaque, memory: []u8, _: std.mem.Alignment, _: usize) void {
    free(memory.ptr);
}

// a copy as a C string, which C gives back with uk_free
fn owned(s: []const u8) [*:0]u8 {
    const out = allocator.allocSentinel(u8, s.len, 0) catch @panic("unikit: out of memory");
    @memcpy(out, s);
    return out.ptr;
}

/// How many grapheme clusters, the characters a reader sees, the text has.
export fn uk_graphemes(text: [*:0]const u8) usize {
    var iter = Graphemes.iterator(std.mem.span(text));
    var n: usize = 0;
    while (iter.next()) |_| n += 1;
    return n;
}

/// How many columns the text takes on a terminal (an emoji or a CJK character takes two).
export fn uk_width(text: [*:0]const u8) usize {
    return DisplayWidth.strWidth(std.mem.span(text));
}

/// The text in upper case, by Unicode's full mapping (ß is SS).
export fn uk_upper(text: [*:0]const u8) [*:0]u8 {
    const up = LetterCasing.toUpperAlloc(allocator, std.mem.span(text)) catch @panic("unikit: out of memory");
    defer allocator.free(up);
    return owned(up);
}

/// The text in lower case, by Unicode's full mapping (a final Σ is ς).
export fn uk_lower(text: [*:0]const u8) [*:0]u8 {
    const low = LetterCasing.toLowerAlloc(allocator, std.mem.span(text)) catch @panic("unikit: out of memory");
    defer allocator.free(low);
    return owned(low);
}

/// The text in Normalization Form C: é as one code point, not e and a combining accent.
export fn uk_nfc(text: [*:0]const u8) [*:0]u8 {
    const result = Normalize.nfc(allocator, std.mem.span(text)) catch @panic("unikit: out of memory");
    defer result.deinit(allocator);
    return owned(result.slice);
}

/// Whether two texts are the same ignoring case, after canonical normalization (Straße is
/// STRASSE).
export fn uk_same_caseless(a: [*:0]const u8, b: [*:0]const u8) bool {
    var matcher = CaselessMatch.CanonCaselessMatcher.default;
    return matcher.match(std.mem.span(a), std.mem.span(b));
}

/// Gives back a string this library made.
export fn uk_free(s: ?[*:0]u8) void {
    if (s) |p| allocator.free(std.mem.span(p));
}
