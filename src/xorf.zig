const std = @import("std");
const math = std.math;
const rotl = math.rotl;
const Allocator = std.mem.Allocator;
const SplitMix64 = std.Random.SplitMix64;

fn make_fingerprint(comptime Fingerprint: type, hash: u64) Fingerprint {
    return @truncate(hash ^ (hash >> 32));
}

fn reduce(len: u32, x: u32) u32 {
    return @truncate((@as(u64, len) * @as(u64, x)) >> 32);
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
    const hl = reduce(header.segment_count_len, @truncate(h));

    var subhashes: [arity]u32 = undefined;
    comptime var rot = 0;
    inline for (0..arity) |i| {
        const rotated: u32 = @truncate(rotl(u64, h, rot));
        subhashes[i] = (hl + @as(u32, @truncate(i)) * header.segment_len) ^ (rotated & (header.segment_len - 1));
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

pub fn filter_check(comptime Fingerprint: type, comptime arity: comptime_int, header: *const Header, fingerprints: []const Fingerprint, hash: u64) bool {
    const h = hash ^ header.seed;
    const subhashes = make_subhashes(arity, header, h);
    var f = make_fingerprint(Fingerprint, h);
    inline for (subhashes) |sh| {
        f ^= fingerprints[sh];
    }
    return f == 0;
}

pub const ConstructError = error{
    OutOfMemory,
    ConstructFail,
};

fn calculate_segment_length_impl(size: u32, logdiv: f64, diff: f64) u32 {
    const float_size: f64 = @floatFromInt(size);
    const logres = @log(float_size) / @log(logdiv) + diff;
    const floored = @floor(logres);
    const int_val: u32 = @intFromFloat(floored);
    return math.shl(u32, 1, int_val);
}

fn calculate_segment_length(comptime arity: comptime_int, size: u32) u32 {
    switch (arity) {
        3 => {
            return calculate_segment_length_impl(size, 3.33, 2.25);
        },
        4 => {
            return calculate_segment_length_impl(size, 2.91, -0.5);
        },
        else => {
            @compileError("arity is not supported");
        },
    }
}

fn calculate_size_factor(comptime arity: comptime_int, size: u32) f64 {
    const sz = @max(size, 2);

    switch (arity) {
        3 => {
            return @max(1.125, 0.875 + 0.25 * @log(1000000.0) / @log(@as(f64, @floatFromInt(sz))));
        },
        4 => {
            return @max(1.075, 0.77 + 0.305 * @log(600000.0) / @log(@as(f64, @floatFromInt(size))));
        },
        else => {
            @compileError("arity is not supported");
        },
    }
}

fn next_power_of_two(comptime T: type, val: T) T {
    return std.math.shl(T, 1, (@typeInfo(T).int.bits - @clz(val -% @as(T, 1))));
}

fn calculate_size(num_hashes: usize, multiplier: usize) usize {
    return (num_hashes * multiplier + 99) / 100;
}

fn next_multiple_of(comptime T: type, a: T, b: T) T {
    return (a + b - 1) / b * b;
}

pub fn filter_construct(comptime Fingerprint: type, comptime arity: comptime_int, alloc: Allocator, hashes: []u64, seed: *u64, header: *Header) ConstructError![]Fingerprint {
    const MULTIPLIERS = [_]usize{ 104, 108, 116, 120, 124 };
    const NUM_TRIES = [_]usize{ 2, 4, 8, 16, 32 };
    for (MULTIPLIERS, NUM_TRIES) |multiplier, num_tries| {
        const size: u32 = @intCast(calculate_size(hashes.len, multiplier));

        for (0..num_tries) |_| {
            const num_segments: u32 = @max(arity, next_multiple_of(u32, (size + 4095) / 4096, arity));
            const segment_length: u32 = next_power_of_two(u32, size / num_segments);
            const segment_count_len: u32 = segment_length * num_segments;
            const array_len = segment_length * (num_segments + arity - 1);

            header.* = Header{
                .segment_count_len = segment_count_len,
                .segment_len = segment_length,
                .seed = 0,
            };

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

            const next_seed = rand.next();
            header.seed = next_seed;
            seed.* = next_seed;

            var stack_len: u32 = 0;
            var queue_len: u32 = 0;

            @memset(set_xormask, 0);
            @memset(set_count, 0);

            for (hashes) |hash| {
                const h = hash ^ next_seed;
                const subhashes = make_subhashes(arity, header, h);
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
                    const subhashes = make_subhashes(arity, header, h);
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
                const subhashes = make_subhashes(arity, header, h);
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
    }

    return ConstructError.ConstructFail;
}

pub fn Filter(comptime Fingerprint: type, comptime arity: comptime_int) type {
    return struct {
        const Self = @This();

        header: Header,
        fingerprints: []Fingerprint,
        alloc: Allocator,

        pub fn init(alloc: Allocator, hashes: []u64) !Self {
            var rand = SplitMix64.init(0);

            var seed = rand.next();
            var header: Header = undefined;
            const fingerprints = try filter_construct(Fingerprint, arity, alloc, hashes, &seed, &header);

            return Self{
                .header = header,
                .fingerprints = fingerprints,
                .alloc = alloc,
            };
        }

        pub fn deinit(self: Self) void {
            self.alloc.free(self.fingerprints);
        }

        pub fn check(self: *const Self, hash: u64) bool {
            return filter_check(Fingerprint, arity, &self.header, self.fingerprints, hash);
        }

        pub fn mem_usage(self: *const Self) usize {
            return self.fingerprints.len * @typeInfo(Fingerprint).int.bits / 8;
        }
    };
}
