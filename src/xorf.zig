const std = @import("std");
const rotl = std.math.rotl;
const Allocator = std.mem.Allocator;
const SplitMix64 = std.Random.SplitMix64;

fn make_fingerprint(comptime Fingerprint: type, hash: u64) Fingerprint {
    return @truncate(hash ^ (hash >> 32));
}

fn reduce(len: u32, x: u32) u32 {
    return @truncate((@as(u64, len) * @as(u64, x)) >> 32);
}

fn make_subhashes(block_len: u32, h: u64) [3]u32 {
    const r0: u32 = @truncate(h);
    const r1: u32 = @truncate(rotl(h, 21));
    const r2: u32 = @truncate(rotl(h, 42));
    const h0 = reduce(block_len, r0);
    const h1 = reduce(block_len, r1) + block_len;
    const h2 = reduce(block_len, r2) + 2 * block_len;
    return .{h0, h1, h2};
}

pub fn check(comptime Fingerprint: type, fingerprints: []const Fingerprint, seed: u64, hash: u64) bool {
    const block_len: u32 = @intCast(fingerprints.len / 3);
    const h = hash ^ seed;
    const subhashes = make_subhashes(block_len, h);
    var f = make_fingerprint(Fingerprint, h);
    inline for (subhashes) |sh| {
        f ^= fingerprints[sh];
    }
    return f == 0;
}

const NUM_TRIES = 100;

pub const ConstructError = error{
    OutOfMemory,
    ConstructFail,
};

pub fn construct(comptime Fingerprint: type, alloc: Allocator, hashes: []u64, seed: *u64) ConstructError![]Fingerprint {
    const array_len: usize = @as(usize, @intFromFloat(32 + 1.23 * @as(f64, @floatFromInt(hashes.len)))) / 3 * 3;

    const needed_bytes = array_len * @typeInfo(Fingerprint).int.bits / 8 + array_len * 28;
    var buf = try alloc.alignedAlloc(u8, 8, array_len);
    defer alloc.free(buf);

    var fingerprints = try alloc.alloc(Fingerprint, array_len);
    
    var offset = 0;
    var counts = @as(*u32, @ptrCast(buf.ptr))[offset..array_len];
    offset += array_len * 4;
    var xormask = @as(*u64, @ptrCast(buf.ptr))[offset..

    var counts = try alloc.alloc(u32, array_len); 
    defer alloc.free(counts);
    var xormask = try alloc.alloc(Fingeprint, array_len);
    defer alloc.free(xormask);
    var stack_i = try alloc.alloc(u32, array_len);
    defer alloc.free(stack_i);
    var stack_h = try alloc.alloc(u64, array_len);
    defer alloc.free(stack_h);
    var queue_i = try alloc.alloc(u32, array_len);
    defer alloc.free(queue_i);
    var queue_h = try alloc.alloc(u64, array_len);
    defer alloc.free(queue_h);

    var rand = SplitMix64.init(seed.*);

    for (0..NUM_TRIES) |_| {
        const next_seed = rand.next();
        seed.* = next_seed;
        
        if (mapping_step(Fingerprint, next_seed, fingerprints, hashes)) {
            return .{ .fingerprints = fingerprints, .seed = seed };
        }
    }

    alloc.free(fingerprints);

    return .ConstructFail;
}

fn mapping_step(comptime Fingerprint: type, seed: u64, fingerprints: []Fingerprint, hashes: []u64) bool {
   return false; 
}
