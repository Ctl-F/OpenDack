const COM1: u16 = 0x3F8;
const TRANSMIT_HOLDING_REG: u16 = 0;
const INTERRUPT_ENABLE_REG: u16 = 1;
const INTERUPT_ID_REG: u16 = 2;
const LINE_CONTROL_REG: u16 = 3;
const MODEM_CONTROL_REG: u16 = 4;
const LINE_STATUS_REG: u16 = 5; // bit 5 (0x20) is set when THR is empty
const MODEM_STATUS_REG: u16 = 6;
const SCRATCH_REG: u16 = 7;

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
    while ((io.in8(COM1 + LINE_STATUS_REG) & 0x20) == 0) {}
    io.out8(COM1, c);
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
    const ptr = @as(*const [*]u8, @ptrCast(@alignCast(&val)));
    const bytes: []u8 = &ptr[0..@sizeOf(T)];

    var index: usize = 0;
    for (bytes) |byte| {
        const low = byte & 0xF;
        const high = (byte & 0xF0) >> 4;

        buffer[index] = convert_nibble(@truncate(high));
        buffer[index + 1] = convert_nibble(@truncate(low));
        index += 2;
    }
}

pub fn dump_bytes(comptime T: type, span: []const T) void {
    var buffer = [_]u8{ 0, 0 } ** @sizeOf(T);
    for (span) |v| {
        convert_to_hex(T, v, &buffer);
        write_ascii(&buffer);
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

const io = struct {
    pub fn in8(port: u16) u8 {
        // asm volatile ("inb {port}, {val}"
        //     : [val] "=a" (val),
        //     : [port] "Nd" (port),
        // );

        return asm volatile ("inb %[port], %[ret]"
            : [ret] "={al}" (-> u8),
            : [port] "{dx}" (port),
        );
    }

    pub fn out8(port: u16, val: u8) void {
        asm volatile ("outb %[val], %[port]"
            :
            : [val] "{al}" (val),
              [port] "{dx}" (port),
        );

        // asm volatile ("outb {val}, {port}"
        //     :
        //     : [val] "a" (val),
        //       [port] "Nd" (port),
        // );
    }
};
