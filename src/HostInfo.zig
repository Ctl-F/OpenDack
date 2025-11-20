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
        if (!parent.uefi) {
            serial.runtime_error_norecover("WARNING: InitMemoryMap called from a non-uefi context.\nThis either points to a bug (double-init) or an invalid (unimplemented use case).\nPlease investigate.", .{});
        }

        const bs = parent.uefi.?.table.boot_services orelse {
            serial.runtime_error_norecover("WARNING: Boot services are unavailable. Memory initialization cannot proceed.\n", .{});
        };

        // grab metadata about MemoryMap
        const mem_info = try bs.getMemoryMapInfo();

        const descriptor_count = mem_info.len;
        const uefi_buffer_len = descriptor_count * mem_info.descriptor_size;

        // allocate a buffer for a COPY of UEFI MemoryMap
        const uefi_mm_buffer: []align(std.os.uefi.tables.MemoryDescriptor) u8 = try bs.allocatePool(.loader_data, uefi_buffer_len);
        defer bs.freePool(uefi_mm_buffer.ptr) catch {};

        // get copy of map into buffer
        var memory_slice = try bs.getMemoryMap(uefi_mm_buffer);

        // iterate to total up all of the pages
        // switched to counting in a block like this
        // so that we can reuse some of these names in the next iteration
        const num_pages = ITER: {
            var counter: usize = 0;
            var iter = memory_slice.iterator();

            while (iter.next()) |desc| {
                counter += @intCast(desc.number_of_pages);
            }

            break :ITER counter;
        };
        const num_vpages = num_pages + NUM_AVAILABLE_EXTRA_VPAGES;

        const phys_desc_bytes = num_pages * @sizeOf(PageDescriptor);
        const phys_desc_pages = std.math.divCeil(usize, phys_desc_bytes, PageSize) catch unreachable; // only errors out if PageSize should be zero

        const virt_desc_bytes = num_vpages * @sizeOf(VirtualPageDescriptor);
        const virt_desc_pages = std.math.divCeil(usize, virt_desc_bytes, PageSize) catch unreachable;

        {
            const tables = std.os.uefi.tables;
            this.memory_map.physical_pages = try bs.allocatePages(
                tables.AllocateLocation.any,
                tables.MemoryType.loader_data,
                physical_desc_pages,
            );
            errdefer bs.freePages(this.memory_map.physical_pages) catch {};

            this.memory_map.virtual_pages = try bs.allocatePages(
                tables.AllocateLocation.any,
                tables.MemoryType.loader_data,
                virtual_desc_pages,
            );
            errdefer bs.freePages(this.memory_map.virtual_pages) catch {};
        }

        this.memory_map.physical_page_buffer = @as([*]PageDescriptor, @ptrCast(&this.memory_map.physical_pages[0][0]))[0..num_pages];
        this.memory_map.virtual_page_buffer = @as([*]VirtualPageDescriptor, @ptrCast(&this.memory_map.virtual_pages[0][0]))[0..num_vpages];

        this.memory_map.physical_page_allocator = MemoryMap.PhysicalPageAllocator.init(this.memory_map.physical_page_buffer);
        this.memory_map.virtual_page_allocator = MemoryMap.VirtualPageAllocator.init(this.memory_map.virtual_page_buffer);

        memory_slice = try bs.getMemoryMap(uefi_mm_buffer);
        var map_iterator = memory_slice.iterator();

        while (map_iterator.next()) |desc| {
            const info = convert_memory_type(desc.type);


        }
    }

    const OpaqueRange = struct {
        start_address: u64,
        end_address: u64,

        inline fn in_page(range: @This(), page_address: u64) bool {
            return (range.start_address <= page_address and page_address < range.end_address);
        }
    };

    fn convert_memory_type(@"type": std.os.uefi.tables.MemoryType) struct { kind: PageType, purpose: StorageType, level: PermissionLevel, flags: BootPageFlags } {
        const UefiMemT = std.os.uefi.tables.MemoryType;

        return switch (@"type") {
            UefiMemT.reserved_memory_type => .{ .reserved, .none, .kernel, .{ .persist = true, .acpi = .none } },
            UefiMemT.loader_code => .{ .conventional, .instruction, .kernel, .{ .persist = false, .acpi = .none } },
            UefiMemT.loader_data => .{ .conventional, .data, .kernel, .{ .persist = false, .acpi = .none } },
            UefiMemT.boot_services_code => .{ .conventional, .instruction, .kernel, .{ .persist = false, .acpi = .none } },
            UefiMemT.boot_services_data => .{ .conventional, .data, .kernel, .{ .persist = false, .acpi = .none } },
            UefiMemT.runtime_services_code => .{ .conventional, .instruction, .kernel, .{ .persist = true, .acpi = .none } },
            UefiMemT.runtime_services_data => .{ .conventional, .data, .kernel, .{ .persist = true, .acpi = .none } },
            UefiMemT.conventional_memory => .{ .conventional, .none, .kernel, .{ .persist = false, .acpi = .none } }, // since this is free the Kernel/User flag doesn't mean anything
            UefiMemT.unusable_memory => .{ .unusable, .none, .kernel, .{ .persist = true, .acpi = .none } },
            UefiMemT.memory_mapped_io, UefiMemT.memory_mapped_port_space => .{ .mmio, .unspecified, .kernel, .{ .persist = true, .acpi = .none } },
            UefiMemT.pal_code => .{ .reserved, .instruction, .kernel, .{ .persist = true, .acpi = .none } },
            UefiMemT.persistent_memory => .{ .reserved, .unspecified, .kernel, .{ .persist = true, .acpi = .none } },
            UefiMemT.unaccepted_memory => .{ .unusable, .none, .kernel, .{ .persist = true, .acpi = .none } },
            UefiMemT.acpi_reclaim_memory => .{ .conventional, .data, .kernel, .{ .persist = false, .acpi = .reclaim } },
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

pub const StorageType = enum(u8) {
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
    type: StorageType,
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
pub const PageType = enum(u8) {
    conventional,
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
    status: PageType, // 8 bits
    purpose: StorageType, // 8 bits
    read: bool,
    write: bool,
    execute: bool,
    cache_enable: bool,
    dirty: bool,
    level: PermissionLevel,
    reserved: u10,
};

pub const PageDescriptor = struct {
    physical_base_addr: u64,
    reference_counter: u16,
    status: PageType,
};

pub const VirtualPageDescriptor = struct {
    backing_page: u64, // backing physical page
    backing_offset: u64, // for use if we want to do disk mapping, otherwise keep this at zero
    flags: PageFlags,
    virtual_base: u64, // base offset in virtual address space
};

pub const MemoryMap = struct {
    pub const PhysicalPageAllocator = SimpleAllocator(PageDescriptor, 1024);
    pub const VirtualPageAllocator = SimpleAllocator(VirtualPageDescriptor, 1024);

    // uefi facing buffer
    physical_pages: []align(4096) Page,
    virtual_pages: []align(4096) Page,

    // reinterpreted buffers and allocators
    physical_page_buffer: []PageDescriptor,
    physical_page_allocator: PhysicalPageAllocator,
    virtual_page_buffer: []VirtualPageDescriptor,
    virtual_page_allocator: VirtualPageAllocator,
};

pub fn SimpleAllocator(comptime entity_t: type, comptime free_stack_size: usize) type {
    return struct {
        const This = @This();

        backing_buffer: []entity_t,
        head: usize,
        free_slots: [free_stack_size]usize,
        free_slots_head: usize = 0,

        pub fn init(buffer: []entity_t) This {
            return .{
                .backing_buffer = buffer,
                .head = 0,
                .free_slots = std.mem.zeroes([free_stack_size]usize),
                .free_slots_head = 0,
            };
        }


        /// enumerate the allocated entities into a buffer
        /// returns the number. this is designed to use the double-enumerate pattern:
        /// {
        ///     const count = try allocator.enumerate_allocated(null);
        ///     var buffer = try base_allocator.allocate_pool(entity_t*, count);
        ///     defer base_allocator.free(buffer);
        /// }
        pub fn enumerate_allocated(this: *const This, buffer: ?[]*entity_t) error{ BufferTooSmall }!usize {
            const allocated = this.count_allocated();

            if(buffer) |out| {
                if(allocated > out.len) {
                    return error.BufferTooSmall;
                }
                this.enumerate_and_populate(out);
            }

            return allocated;
        }

        /// NOTE: the assumption is that we've already validated the length of the buffer
        /// to be sufficient when we call this. (The only usage of this at time of implementation is in the
        /// enumerate_allocated method).
        fn enumerate_and_populate(buffer: []*entity_t) void {

        }

        fn count_allocated(this: *const This) usize {
            return this.head - this.free_slots_head;
        }


        pub fn alloc(this: *This) !*entity_t {
            if (this.has_free_slot()) {
                const index = this.pop_free() catch unreachable; // unreachable since we have checked if a free slot exists
                return &this.backing_buffer[index];
            }

            if (this.head == this.backing_buffer.len) {
                return error.OutOfMemory;
            }

            defer this.head += 1;
            return &this.backing_buffer[this.head];
        }

        pub fn free(this: *This, addr: *entity_t) void {
            var alloc_index: usize = 0;
            while (alloc_index < this.backing_buffer.len and &this.backing_buffer[alloc_index] != addr) : (alloc_index += 1) {}

            if (alloc_index == this.backing_buffer.len) {
                // bad usage, but zig philosophy maintains that we dont throw an error.
                // we will trap instead so that debug builds can be debugged
                unreachable;
            }

            this.push_free_distinct(alloc_index);
        }

        inline fn has_free_slot(this: This) bool {
            return this.free_slots_head > 0;
        }

        inline fn push_free_distinct(this: *This, index: usize) !void {
            var idx: usize = 0;
            while (idx < this.free_slots_head and this.free_slots[idx] != index) : (idx += 1) {}
            try this.push_free(index);
        }

        inline fn push_free(this: *This, index: usize) !void {
            if (this.free_slots_head == this.free_slots.len) return error.StackOverflow;
            this.free_slots[this.free_slots_head] = index;
            this.free_slots_head += 1;
        }

        inline fn pop_free(this: *This) !usize {
            if (this.free_slots_head == 0) return error.StackUndeflow;
            this.free_slots_head -= 1;
            return this.free_slots[this.free_slots_head];
        }
    };
}

pub const HypervisorInfo = struct {};
