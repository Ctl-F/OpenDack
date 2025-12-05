const meta = @import("meta.zig");
const serial = @import("../serial.zig");


pub fn RingBuffer(comptime T: type, comptime specializer: struct {
    /// Return true if a given T CAN be allocated (should it count as "free")
    /// (opens the door for reference counting and other things)
    RequestPredicate: fn(*const T) bool,
    ObtainObject: ?fn(*T) anyerror!void,

    /// Returns true if the item should be considered "fully free"
    /// this is for use when reference counting is implemented
    /// it's mostly a hint, if "true" is returned then the cursor will be
    /// positioned to the newly-available index so that the next allocation will
    /// succeed in O(1) time.
    /// If false is returned everything will continue to work but requests will
    /// happen in O(n) time always.
    FreeObject: fn(*T) anyerror!bool,
}) type {
    return struct {
        const This = @This();
        pub const RingErrors = error{ Unexpected, GrabFailure, BufferIsFull, NotFound };
        pub const Handle = struct {
            ptr: *T,
            index: usize,
        };

        buffer: []T,
        cursor: usize,

        pub fn init(pool: []T) This {
            return .{
                .buffer = pool,
                .cursor = 0,
            };
        }

        pub fn request(this: *This) anyerror!Handle {
            var seek = this.cursor;
            while (true) : (seek = this.next(seek)) {
                const itm = &this.buffer[seek];

                if(specializer.RequestPredicate(itm)){
                    this.cursor = seek;

                    if(specializer.ObtainObject) |onGrab| {
                        try onGrab(itm);
                    }

                    return .{ .index = seek, .ptr = itm };
                }

                if(seek == this.last(this.cursor)) {
                    break;
                }
            }

            return error.BufferIsFull;
        }

        pub fn free(this: *This, handle: Handle) anyerror!void {
            this.free_index(handle.index);
        }

        pub fn free_index(this: *This, index: usize) anyerror!void {
            serial.assert(index < this.buffer.len);

            if(try specializer.FreeObject(&this.buffer[index])){
                this.cursor = this.last(index);
            }
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
