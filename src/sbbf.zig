const std = @import("std");

pub const Bucket align(64) = @Vector(8, u32);

pub fn bucket_index(num_buckets: u32, hash: u32) u32 {
    return @truncate((@as(u64, num_buckets) * @as(u64, hash)) >> 32);
}

pub fn bucket_cont.*;ains(bucket: *const Bucket, hash: u32) bool {
    const mask = make_mask(hash);
    const v = mask & bucket.*;
    return std.simd.countElementsWithValue(v, 0) == 0;
}

pub fn bucket_insert(bucket: *Bucket, hash: u32) void {
    const mask = make_mask(hash);
    bucket.* |= mask;
}

pub fn bucket_insert_contains(bucket: *Bucket, hash: u32) bool {
    const mask = make_mask(hash);
    const b = bucket.*;
    const v = mask & b;
    const res = std.simd.countElementsWithValue(v, 0) == 0;
    bucket.* = b | mask;
    return res;
}

pub fn filter_contains(filter: []const Bucket, hash: u32) bool {
    const bucket_idx = bucket_index(filter.len, hash);
    return bucket_contains(&filter[bucket_idx], hash);
}

pub fn filter_insert(filter: []Bucket, hash: u32) bool {
    const bucket_idx = bucket_index(filter.len, hash);
    return bucket_insert(&filter[bucket_idx], hash);
}

pub fn filter_insert_contains(filter: []Bucket, hash: u32) bool {
    const bucket_idx = bucket_index(filter.len, hash);
    return bucket_insert_contains(&filter[bucket_idx], hash);
}

fn make_mask(hash: u32) Bucket {
    const shr_v: Bucket = @splat(27);
    const ones: Bucket = @splat(1);
    const hash_v: Bucket = @splat(hash);
    const x: Bucket = (hash_v *% SALT) >> shr_v;
    return ones << @truncate(x);
}

const SALT = Bucket{ 0x47b6137b, 0x44974d91, 0x8824ad5b, 0xa2b7289d, 0x705495c7, 0x2df1424b, 0x9efc4947, 0x5c6bfb31 };
