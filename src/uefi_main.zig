const std = @import("std");
const uefi = std.os.uefi;

const stdio = @import("io.zig");

pub export fn EfiMain(
    image_handle: uefi.Handle,
    sys: *uefi.tables.SystemTable,
) uefi.Status {
    _ = image_handle;

    stdio.init(.{
        .serial = true,
        .stdout = true,
        .stdin = true,
    }, .{
        .uefiIn = sys.con_in,
        .uefiOut = sys.con_out,
        .boot = sys.boot_services,
    });

    stdio.write("Hello UEFI\r\n") catch return .aborted;
    stdio.write("Press any key to continue...\r\n") catch return .aborted;

    stdio.write("Enter your name: ") catch return .aborted;

    var buffer = [_]u8{0} ** 512;
    const count = stdio.read(&buffer) catch return .aborted;

    if (count == 0) {
        stdio.write("Alright then, keep your secrets\r\n") catch return .aborted;
        return .success;
    }

    stdio.print("Hello {s}\r\n", .{buffer[0..count]});

    _ = stdio.get_key() catch return .aborted;
    return .success;
}
