const std = @import("std");
const uefi = std.os.uefi;
const io = std.Io;

pub const BufferedUefiWriter = struct {
    const This = @This();

    stpOut: *uefi.protocol.SimpleTextOutput,
    interface: io.Writer,

    pub fn init(buffer: []u8, out: *uefi.protocol.SimpleTextOutput) This {
        return This{
            .stpOut = out,
            .interface = io.Writer{
                .buffer = buffer,
                .vtable = &.{
                    .drain = v_drain,
                },
            },
        };
    }

    fn v_drain(w: *io.Writer, data: []const []const u8, splat: usize) io.Writer.Error!usize {
        const this: *This = @fieldParentPtr("interface", w); // apparently this recovors our "this" pointer

        var last_block: []const u8 = &.{};
        for (data) |block| {
            try this.widen_and_write(block);
            last_block = block;
        }

        if (splat != 0) {
            // TODO: widen once and write multiple times rather than doing
            // the widen work multiple times
            for (0..splat) |_| {
                try this.widen_and_write(last_block);
            }
        }
    }

    const BATCH_SIZE: usize = 512;
    fn widen_and_write(this: *This, message: []const u8) io.Writer.Error!usize {
        var buffer = [_]u16{0} ** (BATCH_SIZE + 1);

        if (message.len == 0) return;
        var len: usize = 0;
        len += 1; // TODO: finish
        var start: usize = 0;
        var end: usize = BATCH_SIZE;
        while (end < message.len) {
            widen(message[start..end], &buffer);
            try this.uefi_write(@ptrCast(@alignCast(&buffer)));

            start = end;
            end += BATCH_SIZE;
        }

        widen(message[start..], &buffer);
        try this.uefi_write(@ptrCast(@alignCast(&buffer)));
    }

    inline fn uefi_write(this: *This, buffer: [*:0]const u16) !void {
        switch (this.stpOut.outputString(buffer)) {
            .success => return,
            else => return io.Writer.Error.WriteFailed,
        }
    }

    fn widen(text: []const u8, buffer: []u16) void {
        const begin = 0;
        const end = text.len;

        var src_cursor: usize = begin;
        var dst_cursor: usize = 0;

        std.debug.assert(text.len < buffer.len);

        while (src_cursor < end) : ({
            src_cursor += 1;
            dst_cursor += 1;
        }) {
            buffer[dst_cursor] = text[src_cursor];
        }
        buffer[dst_cursor] = 0;
    }
};

pub const BufferedUefiReader = struct {};
