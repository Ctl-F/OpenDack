const std = @import("std");
const uefi = std.os.uefi;

const Host = @import("HostInfo.zig");
const runtime = @import("runtime.zig");

fn KernelInit(rState: *runtime.RuntimeState) !void {
    _ = rState;
}

fn KernelMain(rState: *runtime.RuntimeState) !void {
    //runtime.io.serial.write_ascii("Hello World\r\n");
    rState.debug_print("Vendor: [{s}]\nBrand: [{s}]\nMaxLeafNode: {}\nMaxExtNode: {}\n", .{
        &rState.host_info.vendor_string,
        &rState.host_info.brand,
        rState.host_info.max_basic_leaf,
        rState.host_info.max_extended_leaf,
    });

    rState.debug_print("Address:\n  Physical: {}\n  Linear: {}\n", .{
        rState.host_info.physical_address_bits,
        rState.host_info.linear_address_bits,
    });

    const gop: *uefi.protocol.GraphicsOutput = lookup: {
        if (rState.uefi) |efi| {
            if (efi.table.boot_services) |bs| {
                const protocol = try bs.locateProtocol(uefi.protocol.GraphicsOutput, null);
                if (protocol) |prot| {
                    break :lookup prot;
                }
            }
            return error.NotAvailable;
        } else {
            return error.NotAvailable;
        }
    };

    const mode_info = gop.mode.info.*;

    rState.debug_print("Resolution: {}x{}\nPixels Per Scanline: {}\nPFMT: {}\n", .{
        mode_info.horizontal_resolution,
        mode_info.vertical_resolution,
        mode_info.pixels_per_scan_line,
        @as(u32, @intFromEnum(mode_info.pixel_format)),
    });

    // runtime.io.serial.write_ascii("Resolution: ");
    // runtime.io.serial.write_int(u32, mode_info.horizontal_resolution);
    // runtime.io.serial.write_ascii("x");
    // runtime.io.serial.write_int(u32, mode_info.vertical_resolution);
    // runtime.io.serial.write_ascii(" -- Pixels Per Scanline: ");
    // runtime.io.serial.write_int(u32, mode_info.pixels_per_scan_line);
    // runtime.io.serial.write_ascii(" | PFMT: ");
    // runtime.io.serial.write_int(u32, @intFromEnum(mode_info.pixel_format));
    // runtime.io.serial.write_ascii("\r\n");

    const fb = gop.mode.frame_buffer_base;
    const stride = gop.mode.info.pixels_per_scan_line;

    const Pixel = packed struct {
        b: u8,
        g: u8,
        r: u8,
        reserved: u8 = 0,
    };

    const framebuffer: [*]volatile Pixel = @ptrFromInt(fb);
    framebuffer[10 * stride + 10] = Pixel{ .r = 255, .g = 0, .b = 255 };

    while (true) {
        @import("hal.zig").HardwareLayer.pause();
    }
}

pub export fn EfiMain(image_handle: uefi.Handle, sys: *uefi.tables.SystemTable) uefi.Status {
    var services = runtime.init(image_handle, sys, .{ .Com1Enable = true });
    KernelInit(&services) catch return .aborted;
    KernelMain(&services) catch return .aborted;
    return .success;
}
