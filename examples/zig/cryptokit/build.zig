//! cryptokit: Zig's standard library cryptography (BLAKE3, Ed25519, CRC-32) behind a C ABI, built
//! as a static library for Z# (examples/zig): `zig build -Doptimize=ReleaseFast` for this machine,
//! and for a Cortex-M4 `zig build -Doptimize=ReleaseSmall -Dtarget=thumb-freestanding-eabihf
//! -Dcpu=cortex_m4+vfp4d16sp --prefix zig-out/cortex-m4`.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const lib = b.addLibrary(.{
        .name = "cryptokit",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cryptokit.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    // Zig's compiler runtime (the 128-bit arithmetic Ed25519 uses) inside the archive, so any C
    // toolchain links it
    lib.bundle_compiler_rt = true;
    b.installArtifact(lib);
}
