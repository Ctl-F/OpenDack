const std = @import("std");

pub const StaticString = struct {
    src: []const u8,
};

pub fn WideStringPool(comptime backing: type, comptime strings: []const StaticString) type {
    comptime var poolWidth: usize = 0;
    comptime for (strings) |str| {
        poolWidth += str.src.len + 1; // for null terminating character
    };

    comptime var initializingData: [poolWidth]backing = undefined;
    comptime var initializingIndex: usize = 0;

    comptime var lookupSet: [strings.len]usize = undefined;

    comptime for (strings, 0..) |str, idx| {
        lookupSet[idx] = initializingIndex;

        for (str.src) |char| {
            initializingData[initializingIndex] = char;
            initializingIndex += 1;
        }
        initializingData[initializingIndex] = 0;
        initializingIndex += 1;
    };

    return struct {
        const This = @This();
        const Char = backing;

        buffer: [poolWidth]Char = initializingData,
        lookup: [strings.len]usize = lookupSet,

        pub fn get_str(this: This, index: usize) [:0]const Char {
            std.debug.assert(index < this.lookup.len);
            const start = this.lookup[index];

            const end = std.mem.indexOfScalar(Char, this.buffer[start..], 0).?;

            return this.buffer[start..(start + end) :0];
        }
    };
}
