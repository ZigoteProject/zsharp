//! unikit: zg (Unicode text processing, a Zig package) behind a C ABI, built as a static library
//! for Z# (examples/zig): `zig build -Doptimize=ReleaseFast` for this machine, and for a Cortex-M4
//! `zig build -Doptimize=ReleaseSmall -Dtarget=thumb-freestanding-eabihf -Dcpu=cortex_m4+vfp4d16sp
//! --prefix zig-out/cortex-m4`. zg 0.18.0 needs zg-zig-0.17.patch for Zig 0.17 (README.md).
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const zg = b.dependency("zg", .{ .target = target, .optimize = optimize });
    const lib = b.addLibrary(.{
        .name = "unikit",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/unikit.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "Graphemes", .module = zg.module("Graphemes") },
                .{ .name = "DisplayWidth", .module = zg.module("DisplayWidth") },
                .{ .name = "LetterCasing", .module = zg.module("LetterCasing") },
                .{ .name = "Normalize", .module = zg.module("Normalize") },
                .{ .name = "CaselessMatch", .module = zg.module("CaselessMatch") },
            },
        }),
    });
    b.installArtifact(lib);
}
