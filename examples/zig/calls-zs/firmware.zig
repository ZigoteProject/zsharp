//! A Zig firmware for a Cortex-M4 (QEMU's mps2-an386) calling the Z# library (shapes.zs), built
//! with zs build --lib --target cortex-m4, as main.zig calls it on an OS. Zig has the vector table,
//! the reset handler and the output (semihosting, the debugger's console), and gives the library
//! its output (zs_write) and its stop (zs_stop), as a firmware with a Z# library does.
const std = @import("std");
const zs = @import("shapes");

// ---- semihosting: the debugger's (QEMU's) console and exit

fn semihost(op: u32, arg: usize) u32 {
    return asm volatile ("bkpt 0xab"
        : [ret] "={r0}" (-> u32),
        : [op] "{r0}" (op),
          [arg] "{r1}" (arg),
        : .{ .memory = true });
}

fn say(s: []const u8) void {
    var buf: [65]u8 = undefined;
    var rest = s;
    while (rest.len > 0) {
        const k = @min(rest.len, 64);
        @memcpy(buf[0..k], rest[0..k]);
        buf[k] = 0;
        _ = semihost(0x04, @intFromPtr(&buf)); // SYS_WRITE0
        rest = rest[k..];
    }
}

fn quit(code: u32) noreturn {
    const block = [2]u32{ 0x20026, code }; // ADP_Stopped_ApplicationExit, the code
    _ = semihost(0x20, @intFromPtr(&block)); // SYS_EXIT_EXTENDED
    while (true) {}
}

fn print(comptime format: []const u8, args: anytype) void {
    var buf: [128]u8 = undefined;
    say(std.fmt.bufPrint(&buf, format, args) catch "(too long)\n");
}

// ---- what the Z# library needs of the firmware: its output and its stop

export fn zs_write(p: [*]const u8, n: usize) void {
    say(p[0..n]);
}

export fn zs_stop(code: c_int) noreturn {
    quit(@intCast(code));
}

// a C function pointer Z# calls: each prime
fn onPrime(p: isize) callconv(.c) void {
    print("{d} ", .{p});
}

fn main() void {
    var square = [_]zs.Point{ .{ .x = 0, .y = 0 }, .{ .x = 2, .y = 0 }, .{ .x = 2, .y = 2 }, .{ .x = 0, .y = 2 } };
    print("area {d}\n", .{zs.zs_area(&square, square.len)});
    const m = zs.zs_middle(square[0], square[2]);
    print("middle {d} {d}\n", .{ m.x, m.y });
    const n = zs.zs_primes(30, onPrime);
    print("\n{d} primes\n", .{n});
}

// ---- startup: the vector table and the reset handler (firmware.ld places them)

extern var _sidata: u8;
extern var _sdata: u8;
extern var _edata: u8;
extern var _sbss: u8;
extern var _ebss: u8;
extern var _estack: u8;

export fn Reset_Handler() callconv(.c) noreturn {
    // .data from flash, .bss zeroed
    const data: [*]u8 = @ptrCast(&_sdata);
    const image: [*]const u8 = @ptrCast(&_sidata);
    @memcpy(data[0 .. @intFromPtr(&_edata) - @intFromPtr(&_sdata)], image);
    const bss: [*]u8 = @ptrCast(&_sbss);
    @memset(bss[0 .. @intFromPtr(&_ebss) - @intFromPtr(&_sbss)], 0);
    // the FPU on (CPACR: CP10, CP11)
    const cpacr: *volatile u32 = @ptrFromInt(0xE000ED88);
    cpacr.* |= 0xF << 20;
    asm volatile ("dsb\nisb");
    main();
    quit(0);
}

fn fault() callconv(.c) noreturn {
    say("hard fault\n");
    quit(1);
}

export const vectors linksection(".vectors") = [16]?*const anyopaque{
    &_estack, &Reset_Handler, &fault, &fault, &fault, &fault, &fault, null,
    null,     null,           null,   &fault, &fault, null,   &fault, &fault,
};
