const std = @import("std");
const uefi = std.os.uefi;
pub const io = @import("io.zig");
const hal = @import("hal.zig");
const Host = @import("HostInfo.zig");

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

    host_info: Host.HostInfo,
    flags: ServiceFlags,
    uefi: ?UefiInfo,
    _debug_buffer: [256]u8 = undefined,

    pub fn shutdown(this: This) noreturn {
        _ = this;
        std.debug.panic("Shutdown not supported\n", .{});
    }

    pub fn sleep(this: This, microseconds: usize) bool {
        _ = this;
        _ = microseconds;
        std.debug.panic("Sleep not supported\n", .{});
    }

    pub fn debug_print(this: *This, comptime fmt: []const u8, args: anytype) void {
        _ = this;
        var writer = SerialWriter.init(&.{});
        writer.interface.print(fmt, args) catch {};

        // hacky solution just to see what's going on
        const target: u64 = 2000000000;
        const start = hal.HardwareLayer.ticks();
        while (hal.HardwareLayer.ticks() - start < target) {
            hal.HardwareLayer.pause();
        }
    }

    const SerialWriter = struct {
        const sio = std.Io;
        interface: sio.Writer,

        pub fn init(buffer: []u8) @This() {
            return @This(){
                .interface = .{
                    .buffer = buffer,
                    .vtable = &.{
                        .drain = @This().drain,
                    },
                },
            };
        }

        fn drain(w: *sio.Writer, data: []const []const u8, splat: usize) sio.Writer.Error!usize {
            _ = w;
            var count: usize = 0;
            var last_block: []const u8 = &.{};

            for (data) |block| {
                count += block.len;
                io.serial.write_ascii(block);
                last_block = block;
            }

            if (splat > 1) {
                for (1..splat) |_| {
                    count += last_block.len;
                    io.serial.write_ascii(last_block);
                }
            }

            return count;
        }
    };
};

var GLOBAL_STATIC_STATE: RuntimeState = undefined;

pub fn init(handle: uefi.Handle, table: *uefi.tables.SystemTable, flags: ServiceFlags) *RuntimeState {
    if (flags.Com1Enable) {
        io.serial.init_com1();
    }

    GLOBAL_STATIC_STATE = RuntimeState{
        .flags = flags,
        .host_info = Host.HostInfo.init(),
        .uefi = .{
            .image_handle = handle,
            .table = table,
        },
    };

    return &GLOBAL_STATIC_STATE;
}
