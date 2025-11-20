const std = @import("std");
const uefi = std.os.uefi;

const Host = @import("HostInfo.zig");
const runtime = @import("runtime.zig");

fn BootInit(rState: *runtime.RuntimeState) !void {
    _ = rState;
}

fn BootMain(rState: *runtime.RuntimeState) !void {
    //runtime.io.serial.write_ascii("Hello World\r\n");
    rState.debug_print("Vendor: [{s}]\nBrand: [{s}]\nMaxLeafNode: {x}\nMaxExtNode: {x}\n", .{
        &rState.host_info.vendor_string,
        &rState.host_info.brand,
        rState.host_info.max_basic_leaf,
        rState.host_info.max_extended_leaf,
    });

    rState.debug_print("Family: {}\nStepping: {}\nProcessor-Type: {}\nModel: {}\nAddress:\n  Physical: {}\n  Linear: {}\n", .{
        rState.host_info.family,
        rState.host_info.stepping,
        rState.host_info.processor_type,
        rState.host_info.model,
        rState.host_info.physical_address_bits,
        rState.host_info.linear_address_bits,
    });

    for (rState.host_info.topology_levels) |level| {
        rState.debug_print("TopologyLvl: {}\n - Type: {}\n - Count: {}\n", .{
            level.level_number,
            level.level_type,
            level.logical_count,
        });
    }

    for (rState.host_info.caches) |cache| {
        rState.debug_print("Cache: {}\n - Type: {}\n - LineSize: {}\n - Size: {}\n", .{
            cache.level,
            cache.type,
            cache.line_size,
            cache.size_bytes,
        });
    }

    rState.debug_print("Logical Processors: {}\nFeatures: {}\n", .{ rState.host_info.logical_processors, rState.host_info.features });

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

    // const sfs = FSLOOKUP: {
    //     if (std.os.uefi.system_table.boot_services) |bs| {
    //         const file_protocol = try bs.locateProtocol(std.os.uefi.protocol.SimpleFileSystem, null);

    //         if (file_protocol) |prot| {
    //             break :FSLOOKUP prot;
    //         }
    //     }
    //     rState.debug_print("Unable to locate boot services", .{});
    //     return error.NotAvailable;
    // };

    // const volume = try sfs.openVolume();
    // defer volume.close() catch unreachable;

    // const kernelImage = try volume.open("ODK/KERNEL/OPENDACK.ELF", .read, .{});
    // defer kernelImage.close() catch unreachable;

    // TODO: load everything

    @trap();
}

pub export fn EfiMain(image_handle: uefi.Handle, sys: *uefi.tables.SystemTable) uefi.Status {
    const services = runtime.init(image_handle, sys, .{ .Com1Enable = true });
    services.host_info.correct_for_relocation();

    BootInit(services) catch return .aborted;
    BootMain(services) catch return .aborted;
    return .success;
}
