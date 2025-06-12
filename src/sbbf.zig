const std = @import("std");
const native_endian = @import("builtin").target.cpu.arch.endian();
const Allocator = std.mem.Allocator;

const Block = @Vector(8, u64);

pub const BLOCK_SIZE = 64;

fn load_block(block: [*]align(BLOCK_SIZE) const u8) Block {
    const block_ptr: *align(BLOCK_SIZE) const Block = @ptrCast(block);
    const block_v = block_ptr.*;

    return switch (native_endian) {
        .little => block_v,
        .big => @byteSwap(block_v),
    };
}

fn store_block(block: [*]align(BLOCK_SIZE) u8, block_v: Block) void {
    const block_ptr: *align(BLOCK_SIZE) Block = @ptrCast(block);

    block_ptr.* = switch (native_endian) {
        .little => block_v,
        .big => @byteSwap(block_v),
    };
}

pub fn block_index(num_blocks: u32, hash: u32) u32 {
    return @truncate((@as(u64, num_blocks) * @as(u64, hash)) >> 32);
}

pub fn block_check(block: [*]align(BLOCK_SIZE) const u8, hash: u64) bool {
    const block_v = load_block(block);
    const mask = make_mask(hash);
    const v = mask & block_v;
    return std.simd.countElementsWithValue(v, 0) == 0;
}

pub fn block_insert(block: [*]align(BLOCK_SIZE) u8, hash: u64) void {
    const mask = make_mask(hash);
    const block_v = load_block(block);
    store_block(block, block_v | mask);
}

pub fn block_insert_check(block: [*]align(BLOCK_SIZE) u8, hash: u64) bool {
    const mask = make_mask(hash);
    const block_v = load_block(block);
    const v = mask & block_v;
    const res = std.simd.countElementsWithValue(v, 0) == 0;
    store_block(block, block_v | mask);
    return res;
}

fn filter_to_block_ptr(filter: []align(BLOCK_SIZE) const u8, hash: u64) [*]align(BLOCK_SIZE) u8 {
    const block_idx = block_index(@as(u32, @intCast(filter.len)) / BLOCK_SIZE, @truncate(hash));
    const filter_ptr = @intFromPtr(filter.ptr);
    return @ptrFromInt(filter_ptr +% block_idx *% BLOCK_SIZE);
}

pub fn filter_check(filter: []align(BLOCK_SIZE) const u8, hash: u64) bool {
    return block_check(filter_to_block_ptr(filter, hash), hash);
}

pub fn filter_insert(filter: []align(BLOCK_SIZE) u8, hash: u64) void {
    return block_insert(filter_to_block_ptr(filter, hash), hash);
}

pub fn filter_insert_check(filter: []align(BLOCK_SIZE) u8, hash: u64) bool {
    return block_insert_check(filter_to_block_ptr(filter, hash), hash);
}

fn make_mask(hash: u64) Block {
    const shr_v: Block = @splat(27);
    const ones: Block = @splat(1);
    const hash_v: Block = @splat(hash);
    const x: Block = (hash_v *% SALT) >> shr_v;
    return ones << @truncate(x);
}

const SALT align(BLOCK_SIZE) = Block{ 0x47b6137b, 0x44974d91, 0x8824ad5b, 0xa2b7289d, 0x705495c7, 0x2df1424b, 0x9efc4947, 0x5c6bfb31 };

fn next_multiple_of(l: usize, r: usize) usize {
    return (l + r - 1) / r * r;
}

pub fn Filter(comptime bits_per_key: comptime_int) type {
    return struct {
        const Self = @This();

        data: []align(BLOCK_SIZE) u8,
        alloc: Allocator,
        num_hashes: usize,

        pub fn init(alloc: Allocator, hashes: []u64) !Self {
            const bytes = try alloc.alignedAlloc(u8, std.mem.Alignment.@"64", next_multiple_of((bits_per_key * hashes.len + 7) / 8, BLOCK_SIZE));
            @memset(bytes, 0);

            for (hashes) |h| {
                filter_insert(bytes, h);
            }

            return Self{
                .data = bytes,
                .alloc = alloc,
                .num_hashes = hashes.len,
            };
        }

        pub fn deinit(self: Self) void {
            self.alloc.free(self.data);
        }

        pub fn check(self: *const Self, hash: u64) bool {
            return filter_check(self.data, hash);
        }

        pub fn mem_usage(self: *const Self) usize {
            return self.data.len;
        }

        pub fn ideal_mem_usage(self: *const Self) usize {
            return self.num_hashes * bits_per_key / 8;
        }
    };
}
