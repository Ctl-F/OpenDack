const std = @import("std");
pub const serial = @import("serial.zig");

// pub const IOFlags = packed struct {
//     Com1Enable: bool,
//     StdIO: bool,
// };

// pub const Stdio = struct {
//     in: *std.Io.Reader,
//     out: *std.Io.Writer,
//     _uefi_io: ?struct {
//         uefi_in: uefi_io.BufferedUefiReader,
//         uefi_out: uefi_io.BufferedUefiWriter,
//     } = null,
// };

// pub const STD_BUFFER_SIZE: usize = 1024;

// pub const IO = struct {
//     const This = @This();

//     flags: IOFlags,
//     stdio: ?Stdio,

//     pub fn init(flags: IOFlags, rState: *runtime.RuntimeState) !This {
//         var _this = This{
//             .flags = flags,
//         };

//         if (flags.Com1Enable) {
//             init_serial();
//         }

//         if (flags.StdIO) {
//             try _this.init_stdio(rState);
//         }

//         return _this;
//     }

//     fn init_serial() void {
//         serial.init_com1();
//     }

//     fn init_stdio(this: *This, rState: *runtime.RuntimeState) !void {
//         switch (rState.firmware) {
//             .None => {
//                 serial.write_ascii("stdio not implemented for bare metal execution");
//                 return error.NotAvailableForBareMetal;
//             },
//             .UEFI => |uInfo| {
//                 this.stdio = Stdio{
//                     .in = undefined,
//                     .out = undefined,
//                     ._uefi_io = .{
//                         .uefi_in = uefi_io.BufferedUefiReader.init(uInfo.table.con_in.?, .{
//                             .echo = null,
//                             .echoConfig = .{},
//                             .runtimeHandle = rState,
//                             .truncateToAscii = true,
//                         }),
//                         .uefi_out = uefi_io.BufferedUefiWriter.init(
//                             &(.{0} ** 1024),
//                             uInfo.table.con_out.?,
//                         ),
//                     },
//                 };

//                 this.stdio.?.in = &this.stdio.?._uefi_io.?.uefi_in.interface;
//                 this.stdio.?.out = &this.stdio.?._uefi_io.?.uefi_out.interface;
//             },
//         }
//     }
// };

// const std = @import("std");
// const serial = @import("serial.zig");
// const hal = @import("hal.zig").HardwareLayer;
// const uefi = std.os.uefi;

// pub const OutputMode = packed struct {
//     serial: bool = false,
//     stdout: bool = false,
//     stdin: bool = false,
//     _has_init: bool = false,
//     _reserved: u4 = 0,
// };

// var logMode: OutputMode = .{};

// pub const InterfaceProtocols = struct {
//     uefiIn: ?*uefi.protocol.SimpleTextInput,
//     uefiOut: ?*uefi.protocol.SimpleTextOutput,
//     boot: ?*uefi.tables.BootServices,
// };
// var systemServices = InterfaceProtocols{
//     .uefiIn = null,
//     .uefiOut = null,
//     .boot = null,
// };

// pub fn init(mode: OutputMode, services: InterfaceProtocols) void {
//     logMode = mode;

//     if (mode.serial) {
//         serial.init_com1();
//         logMode._has_init = true;
//     }
//     // simple text output/input protocol is never supposed to fail
//     // as long as there's a keyboard and monitor (and maybe even then it's not supposed to
//     // fail so for now we're sticking with debug assertions)
//     if (mode.stdout) {
//         std.debug.assert(services.uefiOut != null);
//         logMode._has_init = true;
//     }

//     if (mode.stdin) {
//         std.debug.assert(services.uefiIn != null);
//         logMode._has_init = true;
//     }

//     systemServices = services;
// }

// pub fn debug_assert(cond: bool, message: []const u8) void {
//     if (cond) return;

//     switch (@import("builtin").mode) {
//         .Debug, .ReleaseSafe => {
//             if (!logMode.serial or !logMode._has_init) {
//                 init(
//                     .{
//                         .serial = true,
//                     },
//                     .{
//                         .boot = null,
//                         .uefiIn = null,
//                         .uefiOut = null,
//                     },
//                 );
//             }
//             write(message) catch unreachable;
//             unreachable;
//         },
//         else => {
//             unreachable;
//         },
//     }
// }

// fn v_write(context: void, bytes: []const u8) WriterError!usize {
//     _ = context;
//     try write(bytes);
//     return bytes.len;
// }

// fn v_read(context: void, buffer: []u8) ReaderError!usize {
//     _ = context;
//     return try read(buffer);
// }

// pub const WriterError = error{
//     GenericError,
//     NotInitialized,
// };
// pub const ReaderError = error{
//     GenericError,
//     NotInitialized,
//     EchoError,
// };

// pub const Reader = std.io.Reader(void, ReaderError, v_read);
// pub const Writer = std.io.Writer(void, WriterError, v_write);
// pub const stdout = Writer{ .context = void{} };
// pub const stdin = Reader{ .context = void{} };

// pub fn print(comptime format: []const u8, args: anytype) void {
//     stdout.print(format, args) catch {};
// }

// pub const UefiKeyStroke = struct {
//     unicode_char: u16,
//     scancode: u16,
// };

// pub fn get_key() ReaderError!UefiKeyStroke {
//     if (!logMode._has_init or systemServices.uefiIn == null) {
//         return error.NotInitialized;
//     }
//     const uefiIn = systemServices.uefiIn.?;
//     return get_key_validated(uefiIn); // split this without the validation for slight performance increase in loops (like read)
// }

// fn get_key_validated(uefiIn: *uefi.protocol.SimpleTextInput) ReaderError!UefiKeyStroke {
//     var key: uefi.protocol.SimpleTextInput.Key.Input = undefined;
//     while (true) {
//         const status = uefiIn.readKeyStroke(&key);
//         if (status == .success) {
//             return .{ .unicode_char = key.unicode_char, .scancode = key.scan_code };
//         } else if (status == .not_ready) {
//             if (systemServices.boot) |bs| {
//                 _ = bs.stall(1000); // avoid busy waiting if possible
//             }
//             hal.pause();
//             // otherwise busy wait (there's nothign else to do
//             continue;
//         } else {
//             return error.GenericError; //TODO: get more specific error codes
//         }
//     }
// }

// const TranslationMode = union(enum) {
//     SimpleAscii: AsciiConfig,

//     pub const AsciiConfig = struct {
//         ReplaceCRWithLF: bool = true,
//     };
// };

// fn translate_stroke(stroke: UefiKeyStroke, comptime mode: TranslationMode) UefiKeyStroke {
//     return switch (mode) {
//         .SimpleAscii => |asconf| VAL: {
//             const char: u8 = @truncate(stroke.unicode_char);

//             if (asconf.ReplaceCRWithLF and char == '\r') {
//                 break :VAL UefiKeyStroke{
//                     .scancode = stroke.scancode,
//                     .unicode_char = '\n',
//                 };
//             }

//             break :VAL UefiKeyStroke{
//                 .scancode = stroke.scancode,
//                 .unicode_char = char,
//             };
//         },
//     };
// }

// pub const ReadConfig = struct {
//     echo: bool = true,
// };

// pub fn read(buffer: []u8, config: ReadConfig) ReaderError!usize {
//     if (!logMode._has_init or systemServices.uefiIn == null) {
//         return error.NotInitialized;
//     }
//     const uefiIn = systemServices.uefiIn.?;
//     var index: usize = 0;

//     while (index < buffer.len) {
//         const stroke = translate_stroke(try get_key_validated(uefiIn), .{ .SimpleAscii = .{} });

//         // simple convert utf16 to ascii for simplicity
//         // TODO: convert to utf8
//         const char: u8 = @truncate(stroke.unicode_char);
//         buffer[index] = char;
//         index += 1;

//         if (config.echo) {
//             write(&.{char}) catch return error.EchoError;
//         }

//         if (char == '\n') break;
//     }

//     return index;
// }

// pub fn write(message: []const u8) WriterError!void {
//     if (!logMode._has_init) {
//         return error.NotInitialized;
//     }

//     if (logMode.serial) {
//         serial.write_ascii(message);
//     }

//     if (logMode.stdout) {
//         if (systemServices.uefiOut) |hook| {
//             try widen_and_write_batched(message, hook);
//             return;
//         }
//         return error.NotInitialized;
//     }
// }

// const BATCH_SIZE: usize = 512;
// fn widen_and_write_batched(message: []const u8, _stdout: *uefi.protocol.SimpleTextOutput) WriterError!void {
//     var buffer = [_]u16{0} ** (BATCH_SIZE + 1);

//     if (message.len == 0) return;

//     var start: usize = 0;
//     var end: usize = BATCH_SIZE;
//     while (end < message.len) {
//         widen(message[start..end], &buffer);

//         try uefi_write(_stdout, @ptrCast(@alignCast(&buffer)));

//         start = end;
//         end += BATCH_SIZE;
//     }

//     widen(message[start..], &buffer);
//     try uefi_write(_stdout, @ptrCast(@alignCast(&buffer)));
// }

// inline fn uefi_write(uefiout: *uefi.protocol.SimpleTextOutput, buffer: [*:0]const u16) WriterError!void {
//     switch (uefiout.outputString(buffer)) {
//         .success => return,
//         else => return WriterError.GenericError, // todo: Add more specific error codes
//     }
// }

// fn widen(text: []const u8, buffer: []u16) void {
//     const begin = 0;
//     const end = text.len;

//     var src_cursor: usize = begin;
//     var dst_cursor: usize = 0;

//     debug_assert(text.len < buffer.len, "Invalid configuration for `widen`, text view is larger than buffer");

//     while (src_cursor < end) : ({
//         src_cursor += 1;
//         dst_cursor += 1;
//     }) {
//         buffer[dst_cursor] = text[src_cursor];
//     }
//     buffer[dst_cursor] = 0;
// }
