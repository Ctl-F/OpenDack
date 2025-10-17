// all x86_64 assembly implementations should go here

pub const io = struct {
    pub fn in8(port: u16) u8 {
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
    }
};

pub inline fn pause() void {
    asm volatile ("pause");
}
