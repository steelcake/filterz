const std = @import("std");
const math = std.math;
const rotl = math.rotl;
const Allocator = std.mem.Allocator;
const SplitMix64 = std.Random.SplitMix64;

fn make_fingerprint(comptime Fingerprint: type, hash: u64) Fingerprint {
    return @truncate(hash ^ (hash >> 32));
}

fn reduce(len: u32, x: u32) u32 {
    return @truncate(math.shr(u64, (@as(u64, len) *% @as(u64, x)), 32));
}

pub const Header = struct {
    seed: u64,
    size: u32,
    segment_length: u32,
    segment_length_mask: u32,
    segment_count: u32,
    segment_count_length: u32,
    array_length: u32,
};

pub fn prepare_subhashes(comptime arity: comptime_int, header: *const Header, hash: u64) [arity]u32 {
    return make_subhashes(arity, header, hash ^ header.seed);
}

fn make_subhashes(comptime arity: comptime_int, header: *const Header, h: u64) [arity]u32 {
    const hl = reduce(header.segment_count_length, @truncate(h));

    var subhashes: [arity]u32 = undefined;
    comptime var rot = 0;
    inline for (0..arity) |i| {
        const rotated: u32 = @truncate(rotl(u64, h, rot));
        subhashes[i] = (hl +% @as(u32, @truncate(i)) *% header.segment_length) ^ (rotated & (header.segment_length -% 1));
        rot += 64 / arity;
    }
    return subhashes;
}

pub fn check_prepared(comptime Fingerprint: type, comptime arity: comptime_int, header: *const Header, fingerprints: [arity]Fingerprint, subhashes: [arity]u32, hash: u64) bool {
    const h = hash ^ header.seed;
    var f = make_fingerprint(Fingerprint, h);
    inline for (subhashes) |sh| {
        f ^= fingerprints.ptr[sh];
    }
    return f == 0;
}

pub fn filter_check(comptime Fingerprint: type, comptime arity: comptime_int, header: *const Header, fingerprints: []const Fingerprint, hash: u64) bool {
    const h = hash ^ header.seed;
    const subhashes = make_subhashes(arity, header, h);
    var f = make_fingerprint(Fingerprint, h);
    inline for (subhashes) |sh| {
        f ^= fingerprints.ptr[sh];
    }
    return f == 0;
}

pub const ConstructError = error{
    OutOfMemory,
    ConstructFail,
};

fn calculate_segment_length(size: u32) u32 {
    const sz = @as(f64, @floatFromInt(size));
    const base = @as(u32, @intFromFloat(@floor(@log(sz) / @log(3.33) + 2.25)));
    return std.math.shl(u32, @as(u32, 1), base);
}

fn calculate_size_factor(size: u32) f64 {
    const sz = @as(f64, @floatFromInt(size));
    return @max(1.125, 0.875 + 0.25 * @log(1000000.0) / @log(sz));
}

pub fn calculate_header(comptime arity: comptime_int, num_keys: u32) Header {
    const size = num_keys;
    const segment_length = @min(
        if (size == 0) 4 else calculate_segment_length(size),
        262144,
    );
    const segment_length_mask = segment_length - 1;
    const size_factor = if (size <= 1) 0 else calculate_size_factor(size);
    const capacity = if (size <= 1) 0 else @as(u32, @intFromFloat(@round(@as(f64, @floatFromInt(size)) * size_factor)));
    const init_segment_count = (capacity + segment_length - 1) / segment_length - (arity - 1);
    const array_length_calc = (init_segment_count + arity - 1) * segment_length;
    const segment_count_calc = (array_length_calc + segment_length - 1) / segment_length;
    const segment_count = if (segment_count_calc <= arity - 1)
        1
    else
        segment_count_calc - (arity - 1);
    const array_length = (segment_count + arity - 1) * segment_length;
    const segment_count_length = segment_count * segment_length;
    return Header{
        .seed = 0,
        .size = size,
        .segment_length = segment_length,
        .segment_length_mask = segment_length_mask,
        .segment_count_length = segment_count_length,
        .segment_count = segment_count,
        .array_length = array_length,
    };
}

pub fn filter_construct(comptime Fingerprint: type, comptime arity: comptime_int, alloc: Allocator, hashes: []u64, seed: *u64, header: *Header) ConstructError![]Fingerprint {
    header.* = calculate_header(arity, @intCast(hashes.len));
    const max_array_len = header.array_length;

    var set_xormask_storage = try alloc.alloc(u64, max_array_len);
    defer alloc.free(set_xormask_storage);

    var set_count_storage = try alloc.alloc(u32, max_array_len);
    defer alloc.free(set_count_storage);

    var queue_storage = try alloc.alloc(u32, max_array_len);
    defer alloc.free(queue_storage);

    var stack_h_storage = try alloc.alloc(u64, max_array_len);
    defer alloc.free(stack_h_storage);

    var stack_hi_storage = try alloc.alloc(u8, max_array_len);
    defer alloc.free(stack_hi_storage);

    var iter_no: u32 = 0;
    while (true) : (iter_no += 1) {
        if (iter_no + 1 > 100) {
            unreachable;
        }
        const array_len = header.array_length;
        var rand = SplitMix64.init(seed.*);

        const set_xormask = set_xormask_storage[0..array_len];
        const set_count = set_count_storage[0..array_len];
        const queue = queue_storage[0..array_len];
        const stack_h = stack_h_storage[0..array_len];
        const stack_hi = stack_hi_storage[0..array_len];

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

        const fingerprints = try alloc.alloc(Fingerprint, array_len);
        @memset(fingerprints, 0);

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

    return ConstructError.ConstructFail;
}

pub fn Filter(comptime Fingerprint: type, comptime arity: comptime_int) type {
    return struct {
        const Self = @This();

        header: Header,
        fingerprints: []Fingerprint,
        alloc: Allocator,
        num_hashes: usize,

        pub fn init(alloc: Allocator, hashes: []u64) !Self {
            var rand = SplitMix64.init(0);

            var seed = rand.next();
            var header: Header = undefined;
            const fingerprints = try filter_construct(Fingerprint, arity, alloc, hashes, &seed, &header);

            return Self{
                .header = header,
                .fingerprints = fingerprints,
                .alloc = alloc,
                .num_hashes = hashes.len,
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

        pub fn ideal_mem_usage(self: *const Self) usize {
            return self.num_hashes * @typeInfo(Fingerprint).int.bits / 8;
        }
    };
}
