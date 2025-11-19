const std = @import("std");
const runtime = @import("runtime.zig");
const serial = @import("serial.zig");

const NUM_AVAIABLE_EXTRA_VPAGES = 1024;

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
            if (efi.table.boot_services) |bs| {
                const memInfo = try bs.getMemoryMapInfo();

                const page_count = memInfo.len;
                const uefi_buffer_len = page_count * memInfo.descriptor_size;
                const uefi_mm_buffer: []align(std.os.uefi.tables.MemoryDescriptor) u8 = bs.allocatePool(.loader_data, uefi_buffer_len) catch error.NotAvailable;

                const memorySlice = try bs.getMemoryMap(uefi_mm_buffer);
                var msIter = memorySlice.iterator();
                var num_pages: usize = 0;
                for (msIter.next()) |desc| {
                    num_pages += desc.number_of_pages;
                }

                this.memory_map = undefined;

                const totalSpace = num_pages * @sizeOf(PageDescriptor);
                // we might not always need this +1, but it helps us to at least verify that if we don't fit cleanly onto
                // a page, we have one extra to fit whatever extra descriptors we need.
                const kernelMapPageCount = (totalSpace / PageSize) + 1;
                const kernelMapVPageCount = (num_pages + NUM_AVAIABLE_EXTRA_VPAGES) * @sizeOf(VirtualPageDescriptor) + 1;

                this.memory_map.physical_page_buffer = @ptrCast(@alignCast(try bs.allocatePages(
                    std.os.uefi.tables.AllocateLocation.any, // ???
                    std.os.uefi.tables.MemoryType.conventional_memory, // ???
                    kernelMapPageCount,
                )));
                errdefer bs.freePages(this.memory_map.physical_page_buffer) catch unreachable;

                this.memory_map.virtual_page_buffer = @ptrCast(@alignCast(try bs.allocatePages(
                    std.os.uefi.tables.AllocateLocation.any,
                    std.os.uefi.tables.MemoryType.conventional_memory,
                    kernelMapVPageCount,
                )));
                errdefer bs.freePages(this.memory_map.virtual_page_buffer) catch unreachable;

                const updatedSlice = try bs.getMemoryMap(uefi_mm_buffer);
                var updatedIter = updatedSlice.iterator();

                for (updatedIter.next()) |desc| {
                    const info = convert_memory_type(desc.type);
                    const page_start_idx = desc.physical_start / PageSize;

                    for (0..desc.number_of_pages) |offset| {
                        this.memory_map.physical_page_buffer[page_start_idx + offset].reference_counter = 0;
                        this.memory_map.physical_page_buffer[page_start_idx + offset].status = info.kind;

                        // how to tell if descriptor is "live" or mapped?
                        // is it if virtual_start != 0?? virtual_start != 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF??
                        // attribute field?
                    }
                }
            } else {
                serial.runtime_error_norecover("WARNING: Boot services are unavailable. Memory initialization cannot proceed.\n", .{});
            }
        } else {
            serial.runtime_error_norecover("WARNING: InitMemoryMap called from a non-uefi context.\nThis either points to a bug (double-init) or an invalid (unimplemented use case).\nPlease investigate.", .{});
        }
    }

    fn convert_memory_type(@"type": std.os.uefi.tables.MemoryType) struct { kind: PageStatus, purpose: MemoryPurpose, level: PermissionLevel, flags: BootPageFlags } {
        const UefiMemT = std.os.uefi.tables.MemoryType;

        return switch (@"type") {
            UefiMemT.reserved_memory_type => .{ .reserved, .none, .kernel, .{ .persist = true, .acpi = .none } },
            UefiMemT.loader_code => .{ .live, .instruction, .kernel, .{ .persist = false, .acpi = .none } },
            UefiMemT.loader_data => .{ .live, .data, .kernel, .{ .persist = false, .acpi = .none } },
            UefiMemT.boot_services_code => .{ .live, .instruction, .kernel, .{ .persist = false, .acpi = .none } },
            UefiMemT.boot_services_data => .{ .live, .data, .kernel, .{ .persist = false, .acpi = .none } },
            UefiMemT.runtime_services_code => .{ .live, .instruction, .kernel, .{ .persist = true, .acpi = .none } },
            UefiMemT.runtime_services_data => .{ .live, .data, .kernel, .{ .persist = true, .acpi = .none } },
            UefiMemT.conventional_memory => .{ .free, .none, .kernel, .{ .persist = false, .acpi = .none } }, // since this is free the Kernel/User flag doesn't mean anything
            UefiMemT.unusable_memory => .{ .unusable, .none, .kernel, .{ .persist = true, .acpi = .none } },
            UefiMemT.memory_mapped_io, UefiMemT.memory_mapped_port_space => .{ .mmio, .unspecified, .kernel, .{ .persist = true, .acpi = .none } },
            UefiMemT.pal_code => .{ .reserved, .instruction, .kernel, .{ .persist = true, .acpi = .none } },
            UefiMemT.persistent_memory => .{ .reserved, .unspecified, .kernel, .{ .persist = true, .acpi = .none } },
            UefiMemT.unaccepted_memory => .{ .unusable, .none, .kernel, .{ .persist = true, .acpi = .none } },
            UefiMemT.acpi_reclaim_memory => .{ .live, .data, .kernel, .{ .persist = false, .acpi = .reclaim } },
            UefiMemT.acpi_memory_nvs => .{ .reserved, .unspecified, .kernel, .{ .persist = true, .acpi = .nvs } },
            else => .{ .unusable, .none, .kernel, .{ .persist = true, .acpi = .none } },
        };
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

pub const MemoryPurpose = enum(u8) {
    unspecified = 255,
    none = 0,
    data = 1,
    instruction = 2,
    unified = 3,
    _,

    pub fn is_unknown(this: @This()) bool {
        return @intFromEnum(this) > 3;
    }
};

pub const BootPageFlags = packed struct {
    persist: bool,
    acpi: enum { none, reclaim, nvs },
};

pub const CacheInfo = struct {
    level: u8,
    type: MemoryPurpose,
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

/// difference between live and reserved:
/// live can be freed if you have the same permission level:
/// .{ .live, .kernel } => can be freed if you are kernel
/// .{ .live, .user } => can be freed if you are user or kernel
/// reserved cannot be freed, but is still considered live
/// .{ .reserved, * } => cannot be freed
pub const PageStatus = enum(u8) {
    free,
    live,
    reserved,
    mmio,
    mmdisk,
    unusable,
};

pub const PermissionLevel = enum(u1) {
    kernel,
    user,
};

pub const PageFlags = packed struct(u32) {
    status: PageStatus, // 8 bits
    purpose: MemoryPurpose, // 8 bits
    read: bool,
    write: bool,
    execute: bool,
    cache_enable: bool,
    dirty: bool,
    level: PermissionLevel,
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

pub const MemoryMap = struct {
    physical_page_buffer: []PageDescriptor,
    virtual_page_buffer: []VirtualPageDescriptor,
};

pub const HypervisorInfo = struct {};
