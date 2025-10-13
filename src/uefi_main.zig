const std = @import("std");
const uefi = std.os.uefi;

const log = @import("log.zig");

const long_string = " 0) This is a really very long string........\r\nand it will continue for ever and ever (not really)\r\n" ++
    " 1) This is a really very long string........\r\nand it will continue for ever and ever (not really)\r\n" ++
    " 2) This is a really very long string........\r\nand it will continue for ever and ever (not really)\r\n" ++
    " 3) This is a really very long string........\r\nand it will continue for ever and ever (not really)\r\n" ++
    " 4) This is a really very long string........\r\nand it will continue for ever and ever (not really)\r\n" ++
    " 5) This is a really very long string........\r\nand it will continue for ever and ever (not really)\r\n" ++
    " 6) This is a really very long string........\r\nand it will continue for ever and ever (not really)\r\n" ++
    " 7) This is a really very long string........\r\nand it will continue for ever and ever (not really)\r\n" ++
    " 8) This is a really very long string........\r\nand it will continue for ever and ever (not really)\r\n" ++
    " 9) This is a really very long string........\r\nand it will continue for ever and ever (not really)\r\n" ++
    "10) This is a really very long string........\r\nand it will continue for ever and ever (not really)\r\n" ++
    "11) This is a really very long string........\r\nand it will continue for ever and ever (not really)\r\n" ++
    "12) This is a really very long string........\r\nand it will continue for ever and ever (not really)\r\n" ++
    "13) This is a really very long string........\r\nand it will continue for ever and ever (not really)\r\n" ++
    "14) This is a really very long string........\r\nand it will continue for ever and ever (not really)\r\n" ++
    "15) This is a really very long string........\r\nand it will continue for ever and ever (not really)\r\n" ++
    "16) This is a really very long string........\r\nand it will continue for ever and ever (not really)\r\n" ++
    "17) This is a really very long string........\r\nand it will continue for ever and ever (not really)\r\n" ++
    "18) And this is the end...\r\n";

pub export fn EfiMain(
    image_handle: uefi.Handle,
    sys: *uefi.tables.SystemTable,
) uefi.Status {
    _ = image_handle;

    log.init(.{
        .serial = true,
        .stdout = true,
    }, sys.con_out.?);

    log.write("Hello UEFI\r\n");
    log.write("Press any key to continue...\r\n");

    log.write(long_string);

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
