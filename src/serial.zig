const COM1: u16 = 0x3F8;
const TRANSMIT_HOLDING_REG: u16 = 0;
const INTERRUPT_ENABLE_REG: u16 = 1;
const INTERUPT_ID_REG: u16 = 2;
const LINE_CONTROL_REG: u16 = 3;
const MODEM_CONTROL_REG: u16 = 4;
const LINE_STATUS_REG: u16 = 5; // bit 5 (0x20) is set when THR is empty
const MODEM_STATUS_REG: u16 = 6;
const SCRATCH_REG: u16 = 7;

const std = @import("std");
const hal = @import("hal.zig").HardwareLayer;
const io = hal.io;

pub fn init_com1() void {
    // disable interrupts
    io.out8(COM1 + INTERRUPT_ENABLE_REG, 0x00);

    // enable DLAB (set baud rate divisor)
    io.out8(COM1 + LINE_CONTROL_REG, 0x80);
    io.out8(COM1 + TRANSMIT_HOLDING_REG, 0x01); // Divisor low byte (115200 baud)
    io.out8(COM1 + INTERRUPT_ENABLE_REG, 0x00); // Divisor high byte

    // 8bits, no parity, one stop bit
    io.out8(COM1 + LINE_CONTROL_REG, 0x03);

    // Enable FIFO, clear them
    io.out8(COM1 + INTERUPT_ID_REG, 0xC7);

    // Enable IRQs, RTS/DSR set
    io.out8(COM1 + MODEM_CONTROL_REG, 0x0B);
}

const FmtSlice = union(enum) {
    literal: []const u8,
    placeholder: enum { string, int, hex },
};

pub fn write_message(comptime fmt: []const u8, args: anytype) void {
    const argsType = @TypeOf(args);
    const info = @typeInfo(argsType);

    if (info != .@"struct") {
        @compileError("Struct type expected as args parameter for serial.write_message");
    }
    const sInfo = info.@"struct";

    comptime var fieldNum: usize = 0;
    comptime var idx: usize = 0;

    init_com1();

    @setEvalBranchQuota(2000000);
    inline while (idx < fmt.len) {
        if (fmt[idx] == '{') {
            idx += 1;
            if (idx >= fmt.len) {
                write_ascii("{");
                break;
            }
            const sp = fmt[idx];
            idx += 1;
            if (idx >= fmt.len) {
                write_ascii(&.{ "{", sp });
                break;
            }

            if (fmt[idx] != '}') {
                write_ascii(&.{ "{", sp });
                continue;
            }
            idx += 1;

            comptime std.debug.assert(fieldNum < sInfo.fields.len);
            switch (sp) {
                's' => {
                    const next_arg = @field(args, sInfo.fields[fieldNum].name);
                    write_ascii(next_arg);
                },
                'd' => {
                    const next_arg = @field(args, sInfo.fields[fieldNum].name);
                    const next_arg_t = @TypeOf(next_arg);
                    comptime std.debug.assert(@typeInfo(next_arg_t) == .int);

                    write_int(next_arg_t, next_arg);
                },
                'x' => {
                    const next_arg = @field(args, sInfo.fields[fieldNum].name);
                    const next_arg_t = @TypeOf(next_arg);
                    comptime std.debug.assert(@typeInfo(next_arg_t) == .int);

                    write_hex(next_arg_t, next_arg);
                },
                else => @compileError("Unknown format specifier: " ++ &.{sp}),
            }
            fieldNum += 1;
        } else {
            const start = idx;
            inline while (idx < fmt.len and fmt[idx] != '{') : (idx += 1) {}
            write_ascii(fmt[start..idx]);
        }
    }

    if (fieldNum != sInfo.fields.len) {
        @compileError("Too many arguments in serial.write_message");
    }
}

pub fn assert(ok: bool) void {
    if (!ok) {
        runtime_error_norecover("Assert has failed\n", .{});
    }
    unreachable;
}

pub fn runtime_error_norecover(comptime fmt: []const u8, args: anytype) noreturn {
    write_message(fmt, args);
    @trap();
}

fn serial_write_char(c: u8) void {
    while ((io.in8(COM1 + LINE_STATUS_REG) & 0x20) == 0) {
        hal.pause();
    }
    io.out8(COM1, c);
}

pub fn write_int(comptime iTy: type, value: iTy) void {
    const ti = @typeInfo(iTy);
    if (ti != .int) @compileError("Expected integer type");
    const info = ti.int;

    const is_signed = info.signedness == .signed;

    // pick a wide unsigned accumulator (64-bit) so intermediate math can't overflow
    const uval: u64 = if (is_signed) SVAL: {
        // handle negative signed values safely
        const signed_val = @as(i128, value);
        break :SVAL if (signed_val < 0) @as(u64, -signed_val) else @as(u64, signed_val);
    } else UVAL: {
        break :UVAL @as(u64, value);
    };

    if (uval == 0) {
        write_ascii(&.{'0'});
        return;
    }

    // compute highest place (1, 10, 100, ...) without overflow using u64
    var place: u64 = 1;
    while (true) {
        const next = place * 10;
        if (next == 0 or next > uval) break;
        place = next;
    }

    while (place != 0) : (place /= 10) {
        const digit: u8 = @intCast((uval / place) % 10);
        const ch: u8 = @as(u8, '0') + digit;
        write_ascii(&.{ch});
    }
}

pub fn write_hex(comptime iTy: type, value: iTy) void {
    const info = @typeInfo(iTy);
    if (info != .int) @compileError("Expected integer type");
    const iInfo = info.int;

    if (iInfo.signedness == .signed) {
        @compileError("Please convert to an unsigned representation for hex display");
    }

    const width = iInfo.bits;
    if (width % 4 != 0) {
        @compileError("Integer width must be divisible by 4 (u8/u16/u32/u64)");
    }

    const hexChars = "0123456789ABCDEF";

    write_ascii("0x");

    // Print fixed width, MSB first (human readable, consistent across all CPUs)
    var shift: usize = width - 4;
    while (true) {
        const nibble: u8 = @intCast((value >> @truncate(shift)) & 0xF);
        const ch: u8 = hexChars[nibble];
        write_ascii(&.{ch});
        if (shift == 0) break;
        shift -= 4;
    }
}

pub fn write_int_old(comptime iTy: type, value: iTy) void {
    const info = switch (@typeInfo(iTy)) {
        .int => |iinfo| iinfo,
        else => @compileError("Expected integer type"),
    };

    var val = value;

    const is_signed = info.signedness == .signed;

    if (val == 0) {
        write_ascii("0");
        return;
    }

    if (is_signed and val < 0) {
        write_ascii("-");
        val = @abs(val);
    }

    var place: iTy = 10;
    while (true) {
        const next = place * 10;
        if (next > val or next < place) break; // prevent overflow
        place = next;
    }

    while (place > 0) : (place /= 10) {
        const digit = (val / place) % 10;
        write_ascii(&.{'0' + @as(u8, @intCast(digit))});
    }
}

pub fn write_ascii(s: []const u8) void {
    for (s) |c| {
        if (c == '\n') {
            serial_write_char('\r');
        }
        serial_write_char(c);
    }
}

fn convert_nibble(val: u4) u8 {
    const hex = "0123456789ABCDEF";
    return hex[val];
}

fn convert_to_hex(comptime T: type, val: T, buffer: []u8) void {
    const t_ptr: *const T = &val;
    const b_ptr: [*]const u8 = @ptrCast(@alignCast(t_ptr));
    const bytes: []const u8 = b_ptr[0..@sizeOf(T)];

    var index: usize = 0;
    var i: usize = @sizeOf(T);
    while (i > 0) : (i -= 1) {
        const byte = bytes[i - 1];

        const low = byte & 0xF;
        const high = (byte >> 4) & 0xF;

        buffer[index] = convert_nibble(@truncate(high));
        buffer[index + 1] = convert_nibble(@truncate(low));
        index += 2;
    }
}

pub const ByteFmt = struct {
    Space: u2 = 1,
    PrintAddr: bool = false,
    IncAscii: bool = false,
};

pub fn dump_bytes(comptime T: type, span: []const T, comptime fmt: ByteFmt) void {
    if (fmt.PrintAddr) {
        var lbuffer = [_]u8{ 0, 0 } ** @sizeOf(u64);
        convert_to_hex(u64, @as(u64, @intFromPtr(span.ptr)), &lbuffer);
        write_ascii(&lbuffer);
        write_ascii(": ");
    }

    var buffer = [_]u8{ 0, 0 } ** @sizeOf(T);
    for (span) |v| {
        convert_to_hex(T, v, &buffer);
        write_ascii(&buffer);

        if (fmt.IncAscii) {
            if (v > ' ' and v < 128) {
                write_ascii("(");

                write_ascii(&.{@as(u8, @truncate(v))});

                write_ascii(")");
            }
        }

        if (fmt.Space > 0) {
            const sp = [_]u8{' '} ** fmt.Space;
            write_ascii(&sp);
        }
    }
}

pub fn write_utf16(s: []const u16) void {
    for (s) |c| {
        const ch: u8 = @truncate(c);

        if (ch == '\n') {
            serial_write_char('\r');
        }
        serial_write_char(ch);
    }
}
