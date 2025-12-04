pub fn RingBuffer(comptime T: type) type {
    return struct {
        const This = @This();
        pub const RingErrors = error{ Unexpected, BufferIsFull, NotFound };

        buffer: []T,
        cursor: usize,

        pub fn init(pool: []T) This {
            return .{
                .buffer = pool,
                .cursor = 0,
            };
        }

        pub fn request(this: *This) RingErrors!usize {
            _ = this;
            return error.Unexpected;
        }
    };
}
