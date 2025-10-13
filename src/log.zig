const std = @import("std");
const serial = @import("serial.zig");

const uefi = std.os.uefi;

pub const OutputMode = packed struct {
    serial: bool = false,
    stdout: bool = false,
    _has_init: bool = false,
    _reserved: u5 = 0,
};

var logMode: OutputMode = .{};
var stdOutHook: ?*uefi.protocol.SimpleTextOutput = null;

pub fn init(mode: OutputMode, stdout: ?*uefi.protocol.SimpleTextOutput) void {
    logMode = mode;

    if (mode.serial) {
        serial.init_com1();
        logMode._has_init = true;
    }

    if (mode.stdout) {
        std.debug.assert(stdout != null);
        stdOutHook = stdout;
        logMode._has_init = true;
    }
}

pub fn debug_assert(cond: bool, message: []const u8) void {
    if (cond) return;

    switch (@import("builtin").mode) {
        .Debug, .ReleaseSafe => {
            init(.{ .serial = true }, null);
            write(message);
            unreachable;
        },
        else => {
            unreachable;
        },
    }
}

pub fn write(message: []const u8) void {
    debug_assert(logMode._has_init, "Warning: call to a writing method has happened before proper init!\r\n    Serial output has been auto-initialized but only in debug mode. Please correct error before releasing code.\r\n");

    if (logMode.serial) {
        serial.write_ascii(message);
    }

    if (logMode.stdout) {
        widen_and_write_batched(message, stdOutHook.?);
    }
}

const BATCH_SIZE: usize = 512;
fn widen_and_write_batched(message: []const u8, stdout: *uefi.protocol.SimpleTextOutput) void {
    var buffer = [_]u16{0} ** (BATCH_SIZE + 1);

    var start: usize = 0;
    var end: usize = BATCH_SIZE;
    while (end < message.len) {
        serial.write_ascii("Entering batch loop\r\n");

        serial.write_ascii("Message Len: ");
        serial.write_int(usize, message.len);
        serial.write_ascii(" | Start: ");
        serial.write_int(usize, start);
        serial.write_ascii(" | End: ");
        serial.write_int(usize, end);
        serial.write_ascii("\r\n");

        widen(message[start..end], &buffer);

        _ = stdout.outputString(@ptrCast(@alignCast(&buffer)));

        start = end;
        end += BATCH_SIZE;
    }
    serial.write_ascii("Out of batch loop\r\n");
    serial.write_ascii("Message Len: ");
    serial.write_int(usize, message.len);
    serial.write_ascii(" | Start: ");
    serial.write_int(usize, start);
    serial.write_ascii(" | End: ");
    serial.write_int(usize, end);
    serial.write_ascii("\r\n");

    widen(message[start..], &buffer);
    _ = stdout.outputString(@ptrCast(@alignCast(&buffer)));
}

fn widen(text: []const u8, buffer: []u16) void {
    const begin = 0;
    const end = text.len;

    var src_cursor: usize = begin;
    var dst_cursor: usize = 0;

    serial.write_ascii("Text Len: ");
    serial.write_int(usize, end - begin);
    serial.write_ascii("/");
    serial.write_int(usize, buffer.len - 1);
    serial.write_ascii("\r\n");

    debug_assert(end - begin <= buffer.len - 1, "Invalid configuration for `widen`, text view is larger than buffer");

    while (src_cursor < end) : ({
        src_cursor += 1;
        dst_cursor += 1;
    }) {
        buffer[dst_cursor] = text[src_cursor];
    }
    buffer[dst_cursor] = 0;
}
