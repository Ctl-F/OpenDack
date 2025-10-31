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

pub inline fn ticks() u64 {
    var low: u32 = undefined;
    var high: u32 = undefined;

    // according to ZIG docs we need to use [SOURCE], [DESTINATION] syntax
    asm volatile ("cpuid");
    asm volatile ("rdtsc"
        // output parameters
        : [low] "={eax}" (low),
          //^(1)   ^(2)    ^(3)
          [high] "={edx}" (high),
        : // input parameters
        : .{ .memory = true }); // not sure if this clobber is needed since we're writing to defined addresses (low/high)

    return (@as(u64, high) << 32) | @as(u64, low);

    // 1) This is the label that is used in the %[...] instruction expression. It's manditory even if not used
    // 2) This is the register to be used for the assembly value, ={...} means that the value in (3) shall be
    //      assigned to whatever is in the ={...} register
    // 2.a) Input Parameters do not need the =, and just use {...} and basically means that the register {...}
    //      shall be equal to the value in (3) at the time that this instruction executes
    // 3) This is the value binder, it can be a variable or a ->(type) which is used for return values without needing
    //      an intermediate value
    //
    // The expression:
    // FN(X, Y):
    //   mov eax, [X]
    //   mov ebx, [Y]
    //   add eax, ebx
    //   mov [X], eax
    //
    // (note that the above is intel syntax, we need to reverse it)
    // the above can be written as such:
    // asm volatile ( "mov %[x], %%eax"
    //      :
    //      : [x] "{eax}" (x) );
    // asm volatile ( "mov %[y], %%ebx"
    //      :
    //      : [y] "{ebx}" (y) );
    // asm volatile ( "add %%ebx, %%eax" );
    // asm volatile ( "mov %%eax, %[x]"
    //      : [x] "={eax}" (x) );
    //
    // although the above could also be simplified further:
    //
    // asm volatile ( "add %[y], %[x]"
    //      : [x] "={eax}" (x)
    //      : [y] "{ebx}" (y));
    //
    // and since by definition x must be bound to EAX and y must be bound to EBX
    // for the instruction, we can avoid the extra mov instructions.
}
