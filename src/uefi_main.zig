const std = @import("std");
const uefi_str = @import("uefi_str.zig");
const serial = @import("serial.zig");

const uefi = std.os.uefi;

const Pool = uefi_str.WideStringPool(u16, &.{
    .{
        .src = "Hello UEFI\r\n",
    },
    .{
        .src = "Press any key to continue...\r\n",
    },
}){};

pub export fn EfiMain(
    image_handle: uefi.Handle,
    sys: *uefi.tables.SystemTable,
) uefi.Status {
    _ = image_handle;
    serial.init_com1();

    const stdout = sys.con_out.?;
    _ = stdout.reset(false);

    //_ = stdout.outputString(Pool.get_str(0));
    serial.write_ascii("Hello UEFI\n");
    serial.dump_bytes(u8, &.{ 0xDE, 0xAD, 0xBE, 0xEF });
    serial.write_ascii("\n!\n");
    //serial.dump_bytes(u16, Pool.get_str(0));
    //serial.write_ascii("\n");
    //serial.dump_bytes(u16, Pool.get_str(1));
    //serial.write_ascii("\n");
    //flush_console(sys);
    //_ = stdout.outputString(Pool.get_str(1));
    //flush_console(sys);

    var input = sys.con_in.?;
    _ = input.reset(false);

    var key_event: uefi.protocol.SimpleTextInput.Key.Input = undefined;

    while (true) {
        const status = input.readKeyStroke(&key_event);
        if (status == .success) break;
        _ = sys.boot_services.?.stall(50000);
    }
    return .success;
}

fn flush_console(sys: *uefi.tables.SystemTable) void {
    const bs = sys.boot_services.?;

    var event: uefi.Event = undefined;
    if (bs.createEvent(
        uefi.tables.BootServices.event_timer | uefi.tables.BootServices.event_notify_signal,
        uefi.tables.BootServices.tpl_application,
        null,
        null,
        &event,
    ) != .success) return;

    _ = bs.setTimer(event, uefi.tables.TimerDelay.timer_relative, 50000000);
    var index: usize = 0;
    _ = bs.waitForEvent(1, &[_]uefi.Event{event}, &index);
    _ = bs.closeEvent(event);
}
