const std = @import("std");
const native_endian = @import("builtin").target.cpu.arch.endian();

const Block = switch (native_endian) {
    .little => @Vector(8, u32),
    .big => @compileError("big endian is not supported"),
};

pub const BLOCK_SIZE = 32;

pub fn block_index(num_blocks: u32, hash: u32) u32 {
    return @truncate((@as(u64, num_blocks) * @as(u64, hash)) >> 32);
}

pub fn block_check(block: [*]align(BLOCK_SIZE) const u8, hash: u32) bool {
    const block_ptr: *align(BLOCK_SIZE) const Block = @ptrCast(block);
    const mask = make_mask(hash);
    const v = mask & block_ptr.*;
    return std.simd.countElementsWithValue(v, 0) == 0;
}

pub fn block_insert(block: [*]align(BLOCK_SIZE) u8, hash: u32) void {
    const block_ptr: *align(BLOCK_SIZE) Block = @ptrCast(block);
    const mask = make_mask(hash);
    block_ptr.* |= mask;
}

pub fn block_insert_check(block: [*]align(BLOCK_SIZE) u8, hash: u32) bool {
    const block_ptr: *align(BLOCK_SIZE) Block = @ptrCast(block);
    const mask = make_mask(hash);
    const b = block_ptr.*;
    const v = mask & b;
    const res = std.simd.countElementsWithValue(v, 0) == 0;
    block_ptr.* = b | mask;
    return res;
}

fn bucket_ptr(filter: []align(BLOCK_SIZE) const u8, hash: u32) [*]align(BLOCK_SIZE) u8 {
    const block_idx = block_index(filter.len / BLOCK_SIZE, hash);
    const filter_ptr = @intFromPtr(filter.ptr);
    return @ptrFromInt(filter_ptr + block_idx * BLOCK_SIZE);
}

pub fn filter_check(filter: []align(BLOCK_SIZE) const u8, hash: u32) bool {
    return block_check(bucket_ptr(filter, hash), hash);
}

pub fn filter_insert(filter: []align(BLOCK_SIZE) u8, hash: u32) bool {
    return block_insert(bucket_ptr(filter, hash), hash);
}

pub fn filter_insert_check(filter: []align(BLOCK_SIZE) u8, hash: u32) bool {
    return block_insert_check(bucket_ptr(filter, hash), hash);
}

fn make_mask(hash: u32) Block {
    const shr_v: Block = @splat(27);
    const ones: Block = @splat(1);
    const hash_v: Block = @splat(hash);
    const x: Block = (hash_v *% SALT) >> shr_v;
    return ones << @truncate(x);
}

const SALT align(BLOCK_SIZE) = Block{ 0x47b6137b, 0x44974d91, 0x8824ad5b, 0xa2b7289d, 0x705495c7, 0x2df1424b, 0x9efc4947, 0x5c6bfb31 };
