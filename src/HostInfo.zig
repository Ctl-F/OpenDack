const std = @import("std");
const runtime = @import("runtime.zig");

pub const HostInfo = struct {
    // In practice the max of 3 should be enough, but
    // technically this is open-ended so we'll keep 6 slots available
    // since we aren't technically hurting for memory
    const MAX_SUPPORTED_TOPOLOGY_LEVEL_COUNT: usize = 6;
    const MAX_SUPPORTED_CACHE_INFO_COUNT: usize = 6;

    vendor_string: [13]u8,
    brand: [49]u8,
    max_basic_leaf: u32,
    max_extended_leaf: u32,

    // identification
    family: u8,
    model: u8,
    stepping: u8,
    processor_type: u8,

    // cores/topology
    logical_processors: usize,
    smt_threads_per_core: usize,
    cores_per_package: usize,
    packages: usize,
    apic_id_width: u8,

    // cpuid deterministic topology levels
    topology_levels_buffer: [MAX_SUPPORTED_TOPOLOGY_LEVEL_COUNT]TopologyLevel,
    topology_levels: []TopologyLevel,

    // address width
    physical_address_bits: u8,
    linear_address_bits: u8,

    // caches (vector)
    cache_buffer: [MAX_SUPPORTED_CACHE_INFO_COUNT]CacheInfo,
    caches: []CacheInfo,

    // feature flags
    features: FeatureFlags,

    // memory & device hints
    memory_map: MemoryMap,

    hypervisor: ?HypervisorInfo,

    pub fn init() @This() {
        const hal = @import("hal.zig");
        var instance: @This() = undefined;
        var buffer: [128]u8 align(@alignOf(u32)) = undefined;
        hal.vendor_string(buffer[0..13], &instance.max_basic_leaf);
        @memcpy(&instance.vendor_string, buffer[0..13]);

        hal.extension_count(&instance.max_extended_leaf);

        hal.chip_id(&instance);
        hal.address_width_bits(instance.max_extended_leaf, &instance.physical_address_bits, &instance.linear_address_bits);

        hal.brand_string(instance.max_extended_leaf, &buffer);
        @memcpy(&instance.brand, buffer[0..instance.brand.len]);

        hal.detect_topology(&instance);

        instance.caches = hal.detect_caches(&instance.cache_buffer);

        return instance;
    }

    pub fn init_memory_map(this: *@This(), parent: *runtime.RuntimeState) !void {
        if (parent.uefi) |efi| {
            _ = this;
            _ = efi;
        } else {
            @import("serial.zig").runtime_error_norecover("WARNING: InitMemoryMap called from a non-uefi context.\nThis either points to a bug (double-init) or an invalid (unimplemented use case).\nPlease investigate.", .{});
        }
    }

    // this is necesary becuase UEFI can (and will) relocate our HostInfo data
    // and when this happens the slice length will still be correct but the pointer will not be
    // so we just need to recalculate all of the slices using the new pointer location.
    // not ideal but managable.
    pub fn correct_for_relocation(this: *@This()) void {
        this.topology_levels = this.topology_levels_buffer[0..this.topology_levels.len];
        this.caches = this.cache_buffer[0..this.caches.len];
    }
};

pub const TopologyLevel = struct {
    level_number: u8,
    level_type: enum(u8) { smt = 1, core = 2, _ },
    shift_right: u8,
    logical_count: u16,
    x2apic_id: u32,
};

pub const CacheInfo = struct {
    pub const Type = enum(u8) {
        none = 0,
        data = 1,
        instruction = 2,
        unified = 3,
        _,

        pub fn is_unknown(this: @This()) bool {
            return @intFromEnum(this) > 3;
        }
    };

    level: u8,
    type: Type,
    line_size: u16, // bytes per line
    ways: u16, // associativity?
    partitions: u16, // usually 1
    sets: u32,
    shared_logical: u16, // logical processors sharing this cache
    size_bytes: usize, // derived total size
    inclusive: bool, // true if cache includes lower levels
    fully_associative: bool,
};
pub const FeatureFlags = @import("hal.zig").FeatureFlags;

pub const PageSize = 4096;
pub const Page = [PageSize]u8;

pub const PageStatus = enum(u8) {
    free,
    live,
    mmio,
    mmdisk,
    unusable,
};

pub const PageFlags = packed struct(u32) {
    status: PageStatus, // 8 bits
    read: bool,
    write: bool,
    execute: bool,
    cache_enable: bool,
    dirty: bool,
    level: enum(u1) { kernel, user },
};

pub const PageDescriptor = struct {
    reference_counter: u16,
    status: PageStatus,
};

pub const VirtualPageDescriptor = struct {
    backing_page: u64, // backing physical page
    backing_offset: u64, // for use if we want to do disk mapping, otherwise keep this at zero
    flags: PageFlags,
    virtual_base: u64, // base offset in virtual address space
};

pub const MemoryMap = struct {};

pub const HypervisorInfo = struct {};
