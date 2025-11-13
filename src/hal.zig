const builtin = @import("builtin");
const serial = @import("io.zig").serial;
pub const host = @import("HostInfo.zig");
const HostInfo = host.HostInfo;

pub const HardwareLayer = switch (builtin.target.cpu.arch) {
    .x86_64 => @import("hal/x86_64.zig"),
    else => @compileError("Hardware Abstraction Layer not implemented for: " ++ builtin.target.cpu.arch.genericName()),
};

pub fn detect_topology(info: *HostInfo) void {
    var metadata: HardwareLayer.CoreTopologyMeta = undefined;
    info.topology_levels = HardwareLayer.detect_topology(info.max_basic_leaf, info.features.x2apic_enabled, &info.topology_levels_buffer, &metadata);

    info.logical_processors = metadata.logical_processors;
    info.smt_threads_per_core = metadata.smt_threads_per_core;
    info.cores_per_package = metadata.cores_per_package;
    info.packages = metadata.packages;
}

pub fn detect_caches(cache_buffer: []host.CacheInfo) []host.CacheInfo {
    return HardwareLayer.detect_caches(cache_buffer);
}

pub fn brand_string(maxExtLeaf: u32, buffer: []align(@alignOf(u32)) u8) void {
    switch (builtin.target.cpu.arch) {
        .x86_64 => {
            if (buffer.len < 49) {
                serial.init_com1();
                serial.write_ascii("Buffer length is too small for x86_64 vendor_string.\n");
                @trap();
            }

            HardwareLayer.cpuid_brand_string(maxExtLeaf, @ptrCast(buffer.ptr));
        },
        else => {
            HardwareLayer.brand_string(maxExtLeaf, buffer);
        },
    }
}

pub fn vendor_string(buffer: []align(@alignOf(u32)) u8, metadata: ?*u32) void {
    switch (builtin.target.cpu.arch) {
        .x86_64 => {
            if (buffer.len < 13) {
                serial.init_com1();
                serial.write_ascii("Buffer length is too small for x86_64 vendor_string.\n");
                @trap();
            }

            HardwareLayer.get_vendor_string(@ptrCast(buffer.ptr), metadata);
        },
        else => HardwareLayer.get_vendor_string(buffer, metadata),
    }
}

pub fn extension_count(count: *u32) void {
    switch (builtin.target.cpu.arch) {
        .x86_64 => {
            count.* = HardwareLayer.cpuid(0x80000000, 0).eax;
        },
        else => {
            HardwareLayer.extension_count(count);
        },
    }
}

pub fn address_width_bits(maxExtLeafCnt: u32, physical: *u8, virtual: *u8) void {
    // scaffolding kept in case future architectures vary
    switch (builtin.target.cpu.arch) {
        .x86_64 => {
            HardwareLayer.address_width(maxExtLeafCnt, physical, virtual);
        },
        else => {
            HardwareLayer.address_width(physical, virtual);
        },
    }
}

pub fn chip_id(info: *HostInfo) void {
    switch (builtin.target.cpu.arch) {
        .x86_64 => {
            const chip_info = HardwareLayer.get_chip_id(info.max_basic_leaf > 6, info.max_extended_leaf, &info.features);

            info.family = chip_info.family;
            info.stepping = chip_info.stepping;
            info.processor_type = chip_info.processor_type;
            info.model = chip_info.model;
        },
        else => HardwareLayer.get_chip_id(info),
    }
}

pub const FeatureFlags = packed struct {
    sse: bool,
    sse2: bool,
    sse3: bool,
    ssse3: bool,
    sse4_1: bool,
    sse4_2: bool,
    avx: bool,
    avx2: bool,
    avx512f: bool,
    apic: bool,
    x2apic_enabled: bool,
    tsc: bool,
    invariant_tsc: bool,
    xsave: bool,
    osxsave: bool,
    long_mode: bool,
    hypervisor_present: bool,
};
