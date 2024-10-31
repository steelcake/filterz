const std = @import("std");
const rotl = std.math.rotl;
const Allocator = std.mem.Allocator;
const getRandom = std.posix.getRandom;
const SplitMix64 = std.Random.SplitMix64;

fn make_fingerprint(comptime Fingerprint: type, hash: u64) Fingerprint {
    return @truncate(hash ^ (hash >> 32));
}

fn reduce(len: u32, x: u32) u32 {
    return @truncate((@as(u64, len) * @as(u64, x)) >> 32);
}

fn subhash(comptime idx: comptime_int, block_len: u32, h: u64) u32 {
    const r: u32 = rotl(h, idx * 21);
    return reduce(block_len, r) + idx * block_len;
}

pub fn check(comptime Fingerprint: type, fingerprints: []const Fingerprint, seed: u64, hash: u64) bool {
    const block_len = fingerprints.len / 3;
    const hash_h = seed ^ hash;
    var f = make_fingerprint(Fingerprint, hash);
    inline for (0..3) |i| {
        f ^= subhash(i, block_len, hash_h);
    }
    return f == 0;
}

const NUM_TRIES = 100;

pub fn construct(comptime Fingerprint: type, alloc: Allocator, hashes: []u64) ?struct { fingerprints: []Fingerprint, seed: u64 } {
    const array_len: usize = @intFromFloat(32 + 1.23 * @as(f64, @floatFromInt(hashes.len)));
    var fingerprints = try alloc.alloc(Fingerprint, array_len);
    

    var rand = SplitMix64.init(0);

    for (0..NUM_TRIES) |_| {
        const seed = rand.next();

        return .{ .fingerprints = fingerprints, .seed = seed };
    }

    alloc.free(fingerprints);

    return null;
}
