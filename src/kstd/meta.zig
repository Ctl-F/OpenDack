const std = @import("std");

/// will assert that an actual type (t) is the same as the expected type
/// if expected is a function, then actual(t) will also work if t is a function
/// pointer with a compatable signature to expected
pub fn expect_type(t: anytype, expected: type) void {
    comptime {
        const expectedInfo = @typeInfo(expected);

        if (expectedInfo == .@"fn") {
            return expect_function(t, expectedInfo.@"fn");
        }

        // other cases here maybe...

        // default case
        if (@TypeOf(t) != expected) {
            @compileError("Type mismatch, expected: " ++ @typeName(expected) ++ " got: " ++ @typeName(@TypeOf(t)));
        }
    }
}

pub fn is_nullable(t: anytype) bool {
    return @typeInfo(@TypeOf(t)) == .optional;
}

const MAX_PARAMS_FOR_VALIDATION = 128;
const FunctionSignature = struct {
    params_buffer: [MAX_PARAMS_FOR_VALIDATION]type,
    params: []type,
    returnType: ?type,

    pub fn from_type_info(info: std.builtin.Type.Fn) @This() {
        var this: @This() = undefined;

        if (info.is_var_args) {
            this.params = &.{};
        } else {
            if (info.params.len > this.params_buffer.len) {
                @compileError("Provided function info has too many parameters for validation");
            }

            for (info.params, 0..) |param, idx| {
                this.params_buffer[idx] = param.type orelse @compileError("Cannot evaluate a function with null parameter types.");
            }
            this.params = this.params_buffer[0..info.params.len];
        }

        this.returnType = info.return_type;

        return this;
    }
};

fn expect_function(actual: anytype, expected: std.builtin.Type.Fn) void {
    const actual_t = @TypeOf(actual);
    const actual_info = @typeInfo(actual_t);

    const actual_fn_info = switch (actual_info) {
        .@"fn" => |_fn| _fn,
        .pointer => |_ptr| ft: {
            const child_info = @typeInfo(_ptr.child);

            if (child_info != .@"fn") {
                @compileError("Expected a function or a function pointer, got a pointer to " ++ @typeName(_ptr.child));
            }

            break :ft child_info.@"fn";
        },
        else => @compileError("Expected a function or a function pointer, got " ++ @typeName(actual_t)),
    };

    const actual_signature = FunctionSignature.from_type_info(actual_fn_info);
    const expected_signature = FunctionSignature.from_type_info(expected);

    const matching_return_type = actual_signature.returnType == expected_signature.returnType;
    const matching_param_count = actual_signature.params.len == expected_signature.params.len;

    const matching_va_args = actual_fn_info.is_var_args == expected.is_var_args;
    const matching_cc = actual_fn_info.calling_convention == expected.calling_convention;

    const matching_params = matching_param_count and EQUAL_SPANS: {
        // if we hit this block we know that the params length is equal so we can use the same index space for both
        for (0..expected_signature.params.len) |idx| {
            if (expected_signature.params[idx] != actual_signature.params[idx]) {
                break :EQUAL_SPANS false;
            }
        }

        break :EQUAL_SPANS true;
    };

    if (!matching_params or !matching_return_type or !matching_va_args or !matching_cc) {
        var message = "Provided function signature does not match expected function signature:\n";

        if (!matching_return_type) {
            message = message ++ " - expected return type: " ++ @typeName(expected_signature.returnType orelse noreturn) ++ " provided: " ++ @typeName(actual_signature.returnType orelse noreturn) ++ "\n";
        }
        if (!matching_param_count) {
            message = message ++ " - wrong number of parameters provided\n";
        } else if (!matching_params) {
            message = message ++ " - parameter types do not match\n";
        }

        if (!matching_va_args) {
            message = message ++ " - var-args mismatch between functions\n";
        }

        if (!matching_cc) {
            message = message ++ " - mismatch in calling convention between functions\n";
        }

        @compileError(message);
    }
}
