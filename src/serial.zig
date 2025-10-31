const COM1: u16 = 0x3F8;
const TRANSMIT_HOLDING_REG: u16 = 0;
const INTERRUPT_ENABLE_REG: u16 = 1;
const INTERUPT_ID_REG: u16 = 2;
const LINE_CONTROL_REG: u16 = 3;
const MODEM_CONTROL_REG: u16 = 4;
const LINE_STATUS_REG: u16 = 5; // bit 5 (0x20) is set when THR is empty
const MODEM_STATUS_REG: u16 = 6;
const SCRATCH_REG: u16 = 7;

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

fn serial_write_char(c: u8) void {
    while ((io.in8(COM1 + LINE_STATUS_REG) & 0x20) == 0) {
        hal.pause();
    }
    io.out8(COM1, c);
}

pub fn write_int(comptime iTy: type, value: iTy) void {
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
    while (val >= place) : (place *= 10) {}
    place /= 10;

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
