const std = @import("std");
const uefi = std.os.uefi;
const io = @import("io.zig");
const serial = @import("serial.zig");

pub const Firmware = union(enum) {
    None,
    UEFI: UefiInfo,
};

pub const UefiInfo = struct {
    image_handle: uefi.Handle,
    table: *uefi.tables.SystemTable,
};

pub const RuntimeError = error{
    NotAvailableForUefi,
    NotAvailableForBareMetal,
};

pub const ServiceFlags = packed struct {
    Com1Enable: bool,
};

pub const RuntimeState = struct {
    const This = @This();

    firmware: Firmware,
    flags: ServiceFlags,

    pub fn shutdown(this: This) noreturn {
        switch (this.firmware) {
            .None => {
                io.write("Shutdown not implemented for bare metal execution") catch unreachable;
                unreachable;
            },
            .UEFI => |uinfo| {
                uinfo.table.runtime_services.resetSystem(
                    .shutdown,
                    .success,
                    null,
                );
            },
        }
    }

    pub fn init_stdio(this: This) RuntimeError!void {
        switch (this.firmware) {
            .None => {
                if (this.flags.Com1Enable) {
                    io.init(.{
                        .serial = true,
                        .stdin = false,
                        .stdout = false,
                    }, .{
                        .boot = null,
                        .uefiIn = null,
                        .uefiOut = null,
                    });
                    return;
                }
                return RuntimeError.NotAvailableForBareMetal;
            },
            .UEFI => |_uefi| {
                io.init(.{
                    .serial = this.flags.Com1Enable,
                    .stdin = true,
                    .stdout = true,
                }, .{
                    .boot = _uefi.table.boot_services,
                    .uefiIn = _uefi.table.con_in,
                    .uefiOut = _uefi.table.con_out,
                });

                return;
            },
        }
    }
};

pub fn init(image_handle: uefi.Handle, sys: *uefi.tables.SystemTable, flags: ServiceFlags) RuntimeState {
    return RuntimeState{
        .firmware = .{
            .UEFI = .{
                .image_handle = image_handle,
                .table = sys,
            },
        },
        .flags = flags,
    };
}
