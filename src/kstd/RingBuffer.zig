const meta = @import("meta.zig");
const serial = @import("../serial.zig");

pub fn RingBuffer(comptime T: type) type {
    return struct {
        const This = @This();
        pub const RingErrors = error{ Unexpected, GrabFailure, BufferIsFull, NotFound };

        buffer: []T,
        cursor: usize,

        pub fn init(pool: []T) This {
            return .{
                .buffer = pool,
                .cursor = 0,
            };
        }

        //TODO: figure this out in a generic way that also works
        // for when the data needs special handling and special initialization cases
        pub fn request(this: *This, comptime predicate: fn (*const T) bool, comptime onGrab: anytype) RingErrors!usize {
            meta.expect_type(predicate, fn (*const T) bool);

            const onGrabType = fn (*T) bool;
            if (meta.is_nullable(onGrab)) {
                if (onGrab != null) {
                    meta.expect_type(onGrab.?, onGrabType);
                }
            } else {
                meta.expect_type(onGrab, onGrabType);
            }

            var seek = this.cursor;
            while (true) : (seek = this.next(seek)) {}

            return error.Unexpected;
        }

        fn next(this: This, crs: usize) usize {
            serial.assert(this.buffer.len != 0);
            return (crs + 1) % this.buffer.len;
        }

        fn last(this: This, crs: usize) usize {
            serial.assert(this.buffer.len != 0);
            return (crs -% 1) % this.buffer.len;
        }
    };
}
