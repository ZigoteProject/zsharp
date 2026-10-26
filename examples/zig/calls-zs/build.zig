//! Zig calling a Z# library: `zig build run` builds shapes.zs with zs build --lib (zs on PATH, or
//! -Dzs=/path/to/zs) and main.zig against it; `zig build qemu` builds it for a Cortex-M4 with
//! firmware.zig, and runs the firmware under QEMU (its mps2-an386 board).
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const zs = b.option([]const u8, "zs", "the Z# compiler (zs on PATH by default)") orelse "zs";

    // the Z# library: an archive and its header (libshapes.h) beside it
    const lib = b.addSystemCommand(&.{ zs, "build", "shapes.zs", "--lib", "--release", "-o" });
    lib.addFileInput(b.path("shapes.zs"));
    const archive = lib.addOutputFileArg("libshapes.a");

    const exe = b.addExecutable(.{
        .name = "shapes",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
            // the Z# runtime is written against the C library
            .link_libc = true,
        }),
    });
    // the header as a Zig module, "shapes"
    const header = b.addTranslateC(.{ .root_source_file = archive.dirname().path(b, "libshapes.h"), .target = target, .optimize = optimize });
    exe.root_module.addImport("shapes", header.createModule());
    exe.root_module.addObjectFile(archive);
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    b.step("run", "Build and run the program").dependOn(&run.step);

    // the firmware: the library for the chip, with no startup (firmware.zig has it)
    // a Cortex-M4F: its single-precision FPU (vfp4d16sp), whose registers carry float arguments
    // in the hard-float convention (eabihf), as the Z# library's chip build has them
    const chip = b.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .os_tag = .freestanding,
        .abi = .eabihf,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m4 },
        .cpu_features_add = std.Target.arm.featureSet(&.{.vfp4d16sp}),
    });
    const chip_lib = b.addSystemCommand(&.{ zs, "build", "shapes.zs", "--lib", "--target", "cortex-m4", "--release", "-o" });
    chip_lib.addFileInput(b.path("shapes.zs"));
    const chip_archive = chip_lib.addOutputFileArg("libshapes.a");
    const chip_header = b.addTranslateC(.{ .root_source_file = chip_archive.dirname().path(b, "libshapes.h"), .target = chip, .optimize = .ReleaseSmall, .link_libc = false });
    const firmware = b.addExecutable(.{
        .name = "firmware",
        .root_module = b.createModule(.{
            .root_source_file = b.path("firmware.zig"),
            .target = chip,
            .optimize = .ReleaseSmall,
        }),
    });
    firmware.root_module.addImport("shapes", chip_header.createModule());
    firmware.root_module.addObjectFile(chip_archive);
    firmware.setLinkerScript(b.path("firmware.ld"));
    firmware.entry = .{ .symbol_name = "Reset_Handler" };
    b.step("firmware", "Build the firmware for a Cortex-M4").dependOn(&b.addInstallArtifact(firmware, .{}).step);
    const qemu = b.addSystemCommand(&.{ "qemu-system-arm", "-M", "mps2-an386", "-nographic", "-semihosting-config", "enable=on,target=native", "-kernel" });
    qemu.addArtifactArg(firmware);
    b.step("qemu", "Run the firmware under QEMU").dependOn(&qemu.step);
}
