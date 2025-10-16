const std = @import("std");
const serial = @import("serial.zig");

const uefi = std.os.uefi;

pub const OutputMode = packed struct {
    serial: bool = false,
    stdout: bool = false,
    _has_init: bool = false,
    _reserved: u5 = 0,
};

var logMode: OutputMode = .{};
var stdOutHook: ?*uefi.protocol.SimpleTextOutput = null;

pub fn init(mode: OutputMode, stdout: ?*uefi.protocol.SimpleTextOutput) void {
    logMode = mode;

    if (mode.serial) {
        serial.init_com1();
        logMode._has_init = true;
    }

    if (mode.stdout) {
        std.debug.assert(stdout != null);
        stdOutHook = stdout;
        logMode._has_init = true;
    }
}

pub fn debug_assert(cond: bool, message: []const u8) void {
    if (cond) return;

    switch (@import("builtin").mode) {
        .Debug, .ReleaseSafe => {
            init(.{ .serial = true }, null);
            write(message);
            unreachable;
        },
        else => {
            unreachable;
        },
    }
}

const ArgSetType = u32;
const ArgState = struct {
    next_arg: usize = 0,
    used_args: ArgSetType = 0,
    args_len: usize,

    pub fn hasUnusedArgs(self: *@This()) bool {
        return @popCount(self.used_args) != self.args_len;
    }

    pub fn nextArg(self: *@This(), arg_index: ?usize) ?usize {
        const next_index = arg_index orelse init: {
            const arg = self.next_arg;
            self.next_arg += 1;
            break :init arg;
        };

        if (next_index >= self.args_len) {
            return null;
        }

        self.used_args |= @as(ArgSetType, 1) << @as(u5, @intCast(next_index));
        return next_index;
    }
};

const Alignment = enum {
    left,
    center,
    right,
};

const default_alignment = .right;
const default_fill_char = ' ';

pub const FormatOptions = struct {
    precision: ?usize = null,
    width: ?usize = null,
    alignment: Alignment = default_alignment,
    fill: u21 = default_fill_char,
};

const Placeholder = struct {
    specifier_arg: []const u8,
    fill: u21,
    alignment: Alignment,
    arg: Specifier,
    width: Specifier,
    precision: Specifier,

    pub fn parse(comptime str: anytype) Placeholder {
        const view = std.unicode.Utf8View.initComptime(&str);
        comptime var parser = Parser{
            .iter = view.iterator(),
        };

        const arg = comptime parser.specifier() catch |err| @compileError(@errorName(err));
        const specifier_arg = comptime parser.until(':');
        if (comptime parser.char()) |ch| {
            if (ch != ':') {
                @compileError("Expected : or }, found '" ++ std.unicode.utf8EncodeComptime(ch) ++ "'");
            }
        }

        var fill: ?u21 = comptime if (parser.peek(1)) |ch|
            switch (ch) {
                '<', '^', '>' => parser.char(),
                else => null,
            }
        else
            null;

        const alignment: ?Alignment = comptime if(parser.peek(0)) |ch| init: {
            switch(ch) {
                '<', '^', '>' => {
                    // TODO: Finishing stealing std.fmt.Placeholder/std.debug.print code
                    // for UEFI/SERIAL usage
                }
            }
        }
    }
};

const Specifier = union(enum) {
    none,
    number: usize,
    named: []const u8,
};

pub fn print(comptime fmt: []const u8, args: anytype) void {
    const max_format_specifiers = 32;
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);

    if (args_type_info != .@"struct") {
        @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
    }

    const fields_info = args_type_info.@"struct".fields;
    if (fields_info.len > max_format_specifiers) {
        @compileError("32 arguments max are supported per format call");
    }

    @setEvalBranchQuota(2000000);
    comptime var arg_state: ArgState = .{ .args_len = fields_info.len };
    comptime var i = 0;
    comptime var literal: []const u8 = "";

    inline while (true) {
        const start_index = i;

        inline while (i < fmt.len) : (i += 1) {
            switch (fmt[i]) {
                '{', '}' => break,
                else => {},
            }
        }

        comptime var end_index = i;
        comptime var unescape_brace = false;

        if (i + 1 < fmt.len and fmt[i + 1] == fmt[i]) {
            unescape_brace = true;
            end_index += 1;
            i += 2;
        }

        literal = literal ++ fmt[start_index..end_index];

        if (unescape_brace) continue;

        if (literal.len != 0) {
            write(literal);
            literal = "";
        }

        if (i >= fmt.len) break;

        if (fmt[i] == '}') {
            @compileError("missing opening {");
        }

        comptime std.debug.assert(fmt[i] == '{');
        i += 1;

        const fmt_begin = i;
        inline while (i < fmt.len and fmt[i] != '}') : (i += 1) {}
        const fmt_end = i;

        if (i > fmt.len) {
            @compileError("missing closing }");
        }

        comptime std.debug.assert(fmt[i] == '}');
        i += 1;

        const placeholder = comptime Placeholder.parse(fmt[fmt_begin..fmt_end].*);
        const arg_pos = comptime switch (placeholder.arg) {
            .none => null,
            .number => |pos| pos,
            .named => |arg_name| std.meta.fieldIndex(ArgsType, arg_name) orelse @compileError("no argument with name '" ++ arg_name ++ "'"),
        };

        const width = switch (placeholder.width) {
            .none => null,
            .number => |v| v,
            .named => |arg_name| blk: {
                const arg_i = comptime std.meta.fieldIndex(ArgsType, arg_name) orelse @compileError("no argument with name '" ++ arg_name ++ "'");
                _ = comptime arg_state.nextArg(arg_i) orelse @compileError("too few arguments");
                break :blk @field(args, arg_name);
            },
        };

        const precision = switch (placeholder.precision) {
            .none => null,
            .number => |v| v,
            .named => |arg_name| blk: {
                const arg_i = comptime std.meta.fieldIndex(ArgsType, arg_name) orelse @compileError("no argument with name '" ++ arg_name ++ "'");
                _ = comptime arg_state.nextArg(arg_i) orelse @compileError("too few arguments");
                break :blk @field(args, arg_name);
            },
        };

        const arg_to_print = comptime arg_state.nextArg(arg_pos) orelse @compileError("too few arguments");

        formatType(
            @field(args, fields_info[arg_to_print].name),
            placeholder.specifier_arg,
            FormatOptions{
                .fill = placeholder.fill,
                .alignment = placeholder.alignment,
                .width = width,
                .precision = precision,
            },
            std.options.fmt_max_depth,
        );
    }

    if (comptime arg_state.hasUnusedArgs()) {
        const missing_count = arg_state.args_len - @popCount(arg_state.used_args);
        switch (missing_count) {
            0 => unreachable,
            1 => @compileError("Unused argument in '" ++ fmt ++ "'"),
            else => @compileError("Unused arguments in '" ++ fmt + "'"),
        }
    }
}

pub fn write(message: []const u8) void {
    debug_assert(logMode._has_init, "Warning: call to a writing method has happened before proper init!\r\n    Serial output has been auto-initialized but only in debug mode. Please correct error before releasing code.\r\n");

    if (logMode.serial) {
        serial.write_ascii(message);
    }

    if (logMode.stdout) {
        widen_and_write_batched(message, stdOutHook.?);
    }
}

pub fn write_bool(value: bool) void {
    write(if (value) "true" else "false");
}

pub fn write_float(comptime fTy: type, value: fTy, decimals: u8) void {
    const info = switch (@typeInfo(fTy)) {
        .float => |finfo| finfo,
        else => @compileError("Expected float type"),
    };
    _ = info; // doesn't seem needed in the current method currently

    var v = value;

    if (v < 0) {
        write("-");
        v = -v;
    }

    if (std.math.isInf(v)) {
        write("inf");
        return;
    }
    if (std.math.isNan(v)) {
        write("nan");
        return;
    }

    const rounding_factor = std.math.pow(fTy, 10.0, @floatFromInt(decimals));
    v = @round(v * rounding_factor) / rounding_factor;

    const int_part: i64 = @intFromFloat(v);
    const frac_part = v - @as(fTy, @floatFromInt(int_part));

    write_int(i64, int_part);
    if (decimals == 0) return;
    write(".");

    var frac = frac_part;
    var i: u8 = 0;
    var non_zero_printed = false;
    while (i < decimals) : (i += 1) {
        frac *= 10.0;
        const digit: u8 = @intCast(@as(i32, @intFromFloat(frac)) % 10);
        non_zero_printed = non_zero_printed or (digit > 0);
        write(&.{'0' + digit});
        frac -= @floor(frac);
        if (frac == 0.0) break;
    }
    if (!non_zero_printed and frac > std.math.floatEps(fTy)) {
        write("*"); // mark if the value is really small but can't be printed in the defined digits
    }
}

pub fn write_int(comptime iTy: type, value: iTy) void {
    const info = switch (@typeInfo(iTy)) {
        .int => |iinfo| iinfo,
        else => @compileError("Expected integer type"),
    };

    var val = value;

    const is_signed = info.signedness == .signed;

    if (val == 0) {
        write("0");
        return;
    }

    if (is_signed and val < 0) {
        write("-");
        val = @abs(val);
    }

    var place: iTy = 10;
    while (val >= place) : (place *= 10) {}
    place /= 10;

    while (place > 0) : (place /= 10) {
        const digit = (val / place) % 10;
        write(&.{'0' + @as(u8, @intCast(digit))});
    }
}

const BATCH_SIZE: usize = 512;
fn widen_and_write_batched(message: []const u8, stdout: *uefi.protocol.SimpleTextOutput) void {
    var buffer = [_]u16{0} ** (BATCH_SIZE + 1);

    var start: usize = 0;
    var end: usize = BATCH_SIZE;
    while (end < message.len) {
        serial.write_ascii("Entering batch loop\r\n");

        serial.write_ascii("Message Len: ");
        serial.write_int(usize, message.len);
        serial.write_ascii(" | Start: ");
        serial.write_int(usize, start);
        serial.write_ascii(" | End: ");
        serial.write_int(usize, end);
        serial.write_ascii("\r\n");

        widen(message[start..end], &buffer);

        _ = stdout.outputString(@ptrCast(@alignCast(&buffer)));

        start = end;
        end += BATCH_SIZE;
    }
    serial.write_ascii("Out of batch loop\r\n");
    serial.write_ascii("Message Len: ");
    serial.write_int(usize, message.len);
    serial.write_ascii(" | Start: ");
    serial.write_int(usize, start);
    serial.write_ascii(" | End: ");
    serial.write_int(usize, end);
    serial.write_ascii("\r\n");

    widen(message[start..], &buffer);
    _ = stdout.outputString(@ptrCast(@alignCast(&buffer)));
}

fn widen(text: []const u8, buffer: []u16) void {
    const begin = 0;
    const end = text.len;

    var src_cursor: usize = begin;
    var dst_cursor: usize = 0;

    serial.write_ascii("Text Len: ");
    serial.write_int(usize, end - begin);
    serial.write_ascii("/");
    serial.write_int(usize, buffer.len - 1);
    serial.write_ascii("\r\n");

    debug_assert(end - begin <= buffer.len - 1, "Invalid configuration for `widen`, text view is larger than buffer");

    while (src_cursor < end) : ({
        src_cursor += 1;
        dst_cursor += 1;
    }) {
        buffer[dst_cursor] = text[src_cursor];
    }
    buffer[dst_cursor] = 0;
}
