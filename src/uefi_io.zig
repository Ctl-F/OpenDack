const std = @import("std");
const uefi = std.os.uefi;
const io = std.Io;
const hal = @import("hal.zig").HardwareLayer;
const runtime = @import("runtime.zig");

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

        var count: usize = 0;
        var last_block: []const u8 = &.{};
        for (data) |block| {
            count += try this.widen_and_write(block);
            last_block = block;
        }

        if (splat != 0) {
            // TODO: widen once and write multiple times rather than doing
            // the widen work multiple times
            for (0..splat) |_| {
                count += try this.widen_and_write(last_block);
            }
        }

        return count;
    }

    const BATCH_SIZE: usize = 512;
    fn widen_and_write(this: *This, message: []const u8) io.Writer.Error!usize {
        var buffer = [_]u16{0} ** (BATCH_SIZE + 1);

        if (message.len == 0) return;
        var len: usize = 0;
        var start: usize = 0;
        var end: usize = BATCH_SIZE;
        while (end < message.len) {
            widen(message[start..end], &buffer);
            try this.uefi_write(@ptrCast(@alignCast(&buffer)));

            start = end;
            end += BATCH_SIZE;
            len += BATCH_SIZE;
        }

        widen(message[start..], &buffer);
        try this.uefi_write(@ptrCast(@alignCast(&buffer)));
        len += message[start..].len;
        return len;
    }

    inline fn uefi_write(this: *This, buffer: [*:0]const u16) io.Writer.Error!void {
        if (try this.stpOut.outputString(buffer)) {
            return;
        }
        return error.WriteFailed;
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

pub const TerminalConfig = struct {
    allowControls: bool = true,
    cursorChar: u8 = '_',
};

pub const UefiReaderConfig = struct {
    echo: ?*BufferedUefiWriter = null,
    echoConfig: TerminalConfig = .{},
    truncateToAscii: bool = true,
    runtimeHandle: ?runtime.RuntimeState = null,
};

pub const BufferedUefiReader = struct {
    const This = @This();

    stpIn: *uefi.protocol.SimpleTextInput,
    config: UefiReaderConfig,
    interface: io.Reader,

    pub fn init(in: *uefi.protocol.SimpleTextInput, config: UefiReaderConfig) This {
        return This{
            .stpIn = in,
            .config = config,
            .interface = io.Reader{
                .buffer = &.{},
                .seek = 0,
                .end = 0,
                .vtable = &.{
                    .stream = v_stream,
                },
            },
        };
    }

    const UefiKeyStroke = struct {
        unicode_char: u16,
        scancode: u16,
    };

    pub fn get_key(this: *const This) !UefiKeyStroke {
        const KSE = uefi.protocol.SimpleTextInput.ReadKeyStrokeError;

        POLL: while (true) {
            const input = this.stpIn.readKeyStroke() catch |rerr| {
                switch (rerr) {
                    KSE.NotReady => {
                        hal.pause(); // signal that we are waiting
                        if (this.config.runtimeHandle) |handle| {
                            _ = handle.sleep(1000); // sleep if we can (if our runtime allows it)
                        }
                        continue :POLL;
                    },
                    else => return rerr,
                }
            };

            return UefiKeyStroke{
                .unicode_char = input.unicode_char,
                .scancode = input.scan_code,
            };
        }
    }

    pub const Scancode = struct {
        pub const Up: usize = 0x01;
        pub const Down: usize = 0x02;
        pub const Right: usize = 0x03;
        pub const Left: usize = 0x04;
        pub const Home: usize = 0x05;
        pub const End: usize = 0x06;
        pub const Insert: usize = 0x07;
        pub const Delete: usize = 0x08;
        pub const PageUp: usize = 0x09;
        pub const PageDown: usize = 0x0A;
        pub const F1: usize = 0x0B;
        pub const F2: usize = 0x0C;
        pub const F3: usize = 0x0D;
        pub const F4: usize = 0x0E;
        pub const F5: usize = 0x0F;
        pub const F6: usize = 0x10;
        pub const F7: usize = 0x11;
        pub const F8: usize = 0x12;
        pub const F9: usize = 0x13;
        pub const F10: usize = 0x14;
        pub const Escape: usize = 0x17;

        const CHAR_BACKSPACE: u8 = 0x08;
    };

    fn v_stream(r: *io.Reader, w: *io.Writer, limit: io.Limit) io.Reader.StreamError!usize {
        const this: *This = @fieldParentPtr("interface", r);
        var buffer = [_]u8{0} ** 1024; // todo: have a better "true" limit from an allocation
        var cursor: usize = 0;
        var buffer_end: usize = 0;

        const end: usize = @min(limit.toInt() orelse std.math.maxInt(usize), buffer.len);
        FILL_BUFFER: while (buffer_end < end) {
            if (this.config.echo) |echo| {
                // 0x08 ==> '\b'
                echo.interface.writeAll(&.{ this.config.echoConfig.cursorChar, Scancode.CHAR_BACKSPACE }) catch return io.Reader.StreamError.WriteFailed;
            }

            const stroke = this.get_key() catch return io.Reader.StreamError.ReadFailed;

            if (stroke.scancode != 0) {
                // handle scancode
                // TODO: Handle left and right
            } else {
                if (!this.config.truncateToAscii) {
                    // not supported yet
                    return io.Reader.StreamError.WriteFailed;
                }
                const char: u8 = CORRECTED: {
                    const c: u8 = @trunc(stroke.unicode_char);
                    if (c == '\r') break :CORRECTED '\n';
                    break :CORRECTED c;
                };

                if (char == '\n') {
                    break :FILL_BUFFER;
                } else if (char == Scancode.CHAR_BACKSPACE and cursor > 0) {
                    // TODO: account for left/right cursor
                    cursor -= 1;
                    buffer_end -= 1;
                    if (this.config.echo) |echo| {
                        echo.interface.writeAll(&.{
                            ' ',
                            Scancode.CHAR_BACKSPACE,
                            Scancode.CHAR_BACKSPACE,
                            ' ',
                            Scancode.CHAR_BACKSPACE,
                        });
                    }

                    continue :FILL_BUFFER;
                }

                if (cursor == buffer_end) {
                    buffer[cursor] = char;
                    cursor += 1;
                    buffer_end += 1;

                    if (this.config.echo) |echo| {
                        echo.interface.writeAll(&.{
                            char,
                        });
                        // Next iteration should output cursor
                    }
                } else {
                    // TODO: Handle left/right behavior
                    // var i: usize = buffer_end;
                    // while (i > cursor) : (i -= 1) {
                    //     buffer[i] = buffer[i - 1];
                    // }
                    // buffer[cursor] = char;
                    // cursor += 1;
                    // buffer_end += 1;
                }
            }
        }

        const slice = buffer[0..buffer_end];
        try w.writeAll(slice);
        return slice.len;
    }
};
