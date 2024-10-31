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

    var fingerprints = alloc.alloc(Fingerprint, array_len);
    errdefer alloc.free(fingerprints);

    var set_xormask = alloc.alloc(Fingerprint, array_len);
    defer alloc.free(set_xormask);

    var set_count = alloc.alloc(u32, array_len);
    defer alloc.free(set_count);

    var queue_i = alloc.alloc(u32, array_len);
    defer alloc.free(queue_i);

    var queue_h = alloc.alloc(u64, array_len);
    defer alloc.free(queue_h);

    var stack_i = alloc.alloc(u32, array_len);
    defer alloc.free(stack_i);

    var stack_h = alloc.alloc(u64, array_len);
    defer alloc.free(stack_h);

    var rand = SplitMix64.init(seed.*);

    for (0..NUM_TRIES) |_| {
        const next_seed = rand.next();
        seed.* = next_seed;
        
        if (mapping_step(Fingerprint, next_seed, fingerprints, hashes, queue_i, queue_h, stack_i, stack_h, set_xormask, set_count)) {
            return .{ .fingerprints = fingerprints, .seed = seed };
        }
    }

    return .ConstructFail;
}

fn mapping_step(comptime Fingerprint: type, seed: u64, fingerprints: []Fingerprint, hashes: []u64, queue_i: []u32, queue_h: []u64, stack_i: []u32, stack_h: []u64, set_xormask: []Fingerprint, set_count: []u32) bool {
    var stack_len: u32 = 0;
    var queue_len: u32 = 0;

    @memset(set_xormask, 0);
    @memset(set_count, 0);

    const block_len = fingerprints.len / 3;

    for (hashes) |hash| {
        const h = hash ^ seed;
        const subhashes = make_subhashes(block_len, h);
        set_xormask[subhashes[0]] ^= h;
        set_xormask[subhashes[1]] ^= h;
        set_xormask[subhashes[2]] ^= h;
        set_counts[subhashes[0]] += 1;
        set_counts[subhashes[1]] += 1;
        set_counts[subhashes[2]] += 1;
    }

    for (set_count, 0..) |count, i| {
        if (count == 1) {
            queue_i[queue_len] = i;
            queue_h[queue_len] = set_xormask[i];
            queue_len += 1;
        }
    }

    while (queue_len > 0) {
        queue_len -= 1;
        const i = queue_i[queue_len];
        const h = queue_h[queue_len];
        if (set_count[i] == 1) {
            const subhashes = make_subhashes(block_len, h);
            const 
            stack_i[stack_len] = i;

        }
    }

    return false; 
}
