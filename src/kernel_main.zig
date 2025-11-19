const runtime = @import("runtime.zig");
const serial = @import("serial.zig");

pub fn KernelMain(state: *runtime.RuntimeState) noreturn {
    state.debug_print("Hello Kernel\n", .{});

    @trap();
}
