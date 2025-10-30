const std = @import("std");
const uefi = std.os.uefi;
pub const io = @import("io.zig");

pub const UefiInfo = struct {
    image_handle: uefi.Handle,
    table: *uefi.tables.SystemTable,
};

pub const RuntimeError = error{
    NotAvailable,
};

pub const ServiceFlags = packed struct {
    Com1Enable: bool = true,
};

pub const RuntimeState = struct {
    const This = @This();

    flags: ServiceFlags,
    uefi: ?UefiInfo,

    pub fn shutdown(this: This) noreturn {
        _ = this;
        std.debug.panic("Shutdown not supported\n", .{});
    }

    pub fn sleep(this: This, microseconds: usize) bool {
        _ = this;
        _ = microseconds;
        std.debug.panic("Sleep not supported\n", .{});
    }
};

pub fn init(handle: uefi.Handle, table: *uefi.tables.SystemTable, flags: ServiceFlags) RuntimeState {
    if (flags.Com1Enable) {
        io.serial.init_com1();
    }

    return RuntimeState{
        .flags = flags,
        .uefi = .{
            .image_handle = handle,
            .table = table,
        },
    };
}
