const builtin = @import("builtin");
const serial = @import("io.zig").serial;

pub const HardwareLayer = switch (builtin.target.cpu.arch) {
    .x86_64 => @import("hal/x86_64.zig"),
    else => @compileError("Hardware abstraction layer not implemented for: " ++ builtin.target.cpu.arch.genericName()),
};

pub fn vendor_string(buffer: []align(@alignOf(u32)) u8, metadata: ?*u32) void {
    switch (builtin.target.cpu.arch) {
        .x86_64 => {
            if (buffer.len < 13) {
                serial.init_com1();
                serial.write_ascii("Buffer length is too small for x86_64 vendor_string.\n");
                @trap();
            }

            HardwareLayer.get_vendor_string(@ptrCast(buffer.ptr), metadata);
        },
        else => HardwareLayer.get_vendor_string(buffer, metadata),
    }
}
