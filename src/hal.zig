const builtin = @import("builtin");

pub const HardwareLayer = switch (builtin.target.cpu.arch) {
    .x86_64 => @import("hal/x86_64.zig"),
    else => @compileError("Hardware abstraction layer not implemented for: " ++ builtin.target.cpu.arch.genericName()),
};
