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

fn reduce64(len: 64, x: 64) 64 {
    return @truncate((@as(u128, len) * @as(u128, x)) >> 64);
}

pub const Header = struct {
    seed: u64,
    segment_len: u32,
    segment_count_len: u32,
};

pub fn prepare_subhashes(comptime arity: comptime_int, header: *const Header, hash: u64) [arity]u32 {
    return make_subhashes(arity, header, hash ^ header.seed);
}

fn make_subhashes(comptime arity: comptime_int, header: *const Header, h: u64) [arity]u32 {
    const hl = reduce64(@as(u64, header.segment_count_len), h);

    var subhashes: [arity]u32 = undefined;
    comptime var rot = 0;
    inline for (0..arity) |i| {
        subhashes[i] = (hl + i * @as(u64, header.segment_len)) ^ (rotl(u64, h, rot) & (header.segment_len - 1));
        rot += 64 / arity;
    }
    return subhashes;
}

pub fn check_prepared(comptime Fingerprint: type, comptime arity: comptime_int, header: *const Header, fingerprints: [arity]Fingerprint, subhashes: [arity]u32, hash: u64) bool {
    const h = hash ^ header.seed;
    var f = make_fingerprint(Fingerprint, h);
    inline for (subhashes) |sh| {
        f ^= fingerprints[sh];
    }
    return f == 0;
}

pub fn check(comptime Fingerprint: type, comptime arity: comptime_int, header: *const Header, fingerprints: []const Fingerprint, hash: u64) bool {
    const h = hash ^ header.seed;
    const subhashes = make_subhashes(arity, header, h);
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

pub fn construct(comptime Fingerprint: type, comptime arity: comptime_int, alloc: Allocator, hashes: []u64, seed: *u64, header: *Header) ConstructError![]Fingerprint {
    const array_len: usize = @as(usize, @intFromFloat(32 + 1.23 * @as(f64, @floatFromInt(hashes.len))));

    var fingerprints = try alloc.alloc(Fingerprint, array_len);
    errdefer alloc.free(fingerprints);

    @memset(fingerprints, 0);

    var set_xormask = try alloc.alloc(u64, array_len);
    defer alloc.free(set_xormask);

    var set_count = try alloc.alloc(u32, array_len);
    defer alloc.free(set_count);

    var queue = try alloc.alloc(u32, array_len);
    defer alloc.free(queue);

    var stack_h = try alloc.alloc(u64, array_len);
    defer alloc.free(stack_h);

    var stack_hi = try alloc.alloc(u8, array_len);
    defer alloc.free(stack_hi);

    var rand = SplitMix64.init(seed.*);

    for (0..NUM_TRIES) |_| {
        const next_seed = rand.next();
        seed.* = next_seed;

        var stack_len: u32 = 0;
        var queue_len: u32 = 0;

        @memset(set_xormask, 0);
        @memset(set_count, 0);

        const block_len: u32 = @intCast(fingerprints.len / arity);

        for (hashes) |hash| {
            const h = hash ^ next_seed;
            const subhashes = make_subhashes(arity, block_len, h);
            for (subhashes) |subh| {
                set_xormask[subh] ^= h;
                set_count[subh] += 1;
            }
        }

        for (set_count, 0..) |count, i| {
            if (count == 1) {
                queue[queue_len] = @intCast(i);
                queue_len += 1;
            }
        }

        while (queue_len > 0) {
            queue_len -= 1;
            const i = queue[queue_len];
            if (set_count[i] == 1) {
                const h = set_xormask[i];
                const subhashes = make_subhashes(arity, block_len, h);
                stack_h[stack_len] = h;
                inline for (subhashes, 0..) |subh, hi| {
                    set_xormask[subh] ^= h;
                    set_count[subh] -= 1;
                    if (subh == i) {
                        stack_hi[stack_len] = hi;
                    } else if (set_count[subh] == 1) {
                        queue[queue_len] = subh;
                        queue_len += 1;
                    }
                }
                stack_len += 1;
            }
        }

        if (stack_len < hashes.len) {
            continue;
        }

        while (stack_len > 0) {
            stack_len -= 1;
            const h = stack_h[stack_len];
            const hi = stack_hi[stack_len];
            const subhashes = make_subhashes(arity, block_len, h);
            var f = make_fingerprint(Fingerprint, h);
            var to_change: u32 = undefined;
            inline for (subhashes, 0..) |subh, shi| {
                if (shi == hi) {
                    to_change = subh;
                } else {
                    f ^= fingerprints[subh];
                }
            }
            fingerprints[to_change] = f;
        }

        return fingerprints;
    }

    return ConstructError.ConstructFail;
}

test "smoke" {
    var rand = SplitMix64.init(0);
    const num_hashes = 10000;
    const alloc = std.testing.allocator;
    var hashes = try alloc.alloc(u64, num_hashes);
    defer alloc.free(hashes);

    for (0..num_hashes) |i| {
        hashes[i] = std.hash.XxHash3.hash(rand.next(), std.mem.asBytes(&rand.next()));
    }

    var seed = rand.next();
    const fingerprints = try construct(u16, 3, alloc, hashes, &seed);
    defer alloc.free(fingerprints);

    for (hashes) |h| {
        try std.testing.expect(check(u16, 3, fingerprints, seed, h));
    }
}

fn to_fuzz(input: []const u8) anyerror!void {
    if (input.len < 8) {
        return;
    }

    const alloc = std.testing.allocator;

    var hashes = try alloc.alloc(u64, input.len);
    defer alloc.free(hashes);

    var rand = SplitMix64.init(0);

    for (input, 0..) |*b, i| {
        const h = std.hash.XxHash3.hash(rand.next(), b[0..1]);
        hashes[i] = h;
    }

    var seed = rand.next();
    const fingerprints = try construct(u8, 3, alloc, hashes, &seed);
    defer alloc.free(fingerprints);

    for (hashes) |h| {
        try std.testing.expect(check(u8, 3, fingerprints, seed, h));
    }

    for (0..1000) |x| {
        const h = std.hash.XxHash3.hash(rand.next(), std.mem.toBytes(x));
        if (!check(u8, 3, fingerprints, seed, h)) {
            try std.testing.expect(!contains(u64, hashes, h));
        }
    }
}

fn contains(comptime T: type, slice: []T, v: T) bool {
    for (slice) |x| {
        if (x == v) {
            return true;
        }
    }

    return false;
}

test "fuzz" {
    try std.testing.fuzz(to_fuzz, .{});
}
