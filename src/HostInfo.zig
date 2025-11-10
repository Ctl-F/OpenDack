pub const HostInfo = struct {
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
    x2apic_ids: []u32,

    // cpuid deterministic topology levels
    topology_levels: []TopologyLevel,

    // address width
    physical_address_bits: u8,
    linear_address_bits: u8,

    // caches (vector)
    caches: []CacheInfo,

    // feature flags
    features: FeatureFlags,

    // memory & device hints
    memory_map_source: MemoryMapSource,
    memory_regions: []MemoryRegion,

    hypervisor: ?HypervisorInfo,

    pub fn init() @This() {
        const hal = @import("hal.zig");
        var instance: @This() = undefined;
        var buffer: [13]u8 align(@alignOf(u32)) = undefined;
        hal.vendor_string(&buffer, &instance.max_basic_leaf);
        @memcpy(&instance.vendor_string, &buffer);

        hal.extension_count(&instance.max_extended_leaf);

        hal.chip_id(&instance);
        hal.address_width_bits(instance.max_extended_leaf, &instance.physical_address_bits, &instance.linear_address_bits);

        return instance;
    }
};

pub const TopologyLevel = struct {};
pub const CacheInfo = struct {};
pub const FeatureFlags = packed struct {};
pub const MemoryMapSource = struct {};
pub const MemoryRegion = struct {};
pub const HypervisorInfo = struct {};
