const std = @import("std");
const uefi = std.os.uefi;

const runtime = @import("runtime.zig");
const stdio = @import("io.zig");

fn KernelInit(rState: *runtime.RuntimeState) !void {
    try rState.init_stdio();
}

fn KernelMain(rState: *runtime.RuntimeState) !void {
    try stdio.write("Hello UEFI\r\n");
    try stdio.write("Enter your name: ");

    var buffer = [_]u8{0} ** 512;
    const count = try stdio.read(&buffer, .{});

    if (count == 0) {
        try stdio.write("Alright then, keep your secrets\r\n");
        return;
    }

    stdio.print("Hello {s}\r\n", .{buffer[0..count]});
    try stdio.write("Press any key to continue...\r\n");
    _ = try stdio.get_key();

    rState.shutdown();
}

pub export fn EfiMain(image_handle: uefi.Handle, sys: *uefi.tables.SystemTable) uefi.Status {
    var services = runtime.init(image_handle, sys, .{ .Com1Enable = true });
    KernelInit(&services) catch return .aborted;
    KernelMain(&services) catch return .aborted;
    return .success;
}
