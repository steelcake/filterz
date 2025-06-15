// The code in this module is ported from https://github.com/FastFilter/xor_singleheader/blob/master/include/binaryfusefilter.h
// See the XOR_SINGLEHEADER_LICENSE for license info

const std = @import("std");
const shr = std.math.shr;
const shl = std.math.shl;
const Allocator = std.mem.Allocator;

// The code assumes this value is 3, don't change it if you don't know what you are doing
const ARITY = 3;
const Fingerprint = u16;

// Apparently reaching this amount of tries is impossible since failure probability of a try is less than 1%
const POPULATE_MAX_ITER = 100;

fn make_hash(key: u64, seed: u64) u64 {
    var hash = key +% seed;
    hash ^= shr(u64, hash, 33);
    hash *%= @as(u64, 0xff51afd7ed558ccd);
    hash ^= shr(u64, hash, 33);
    hash *%= @as(u64, 0xc4ceb9fe1a85ec53);
    hash ^= shr(u64, hash, 33);
    return hash;
}

fn reduce(len: u32, x: u32) u32 {
    return @truncate((@as(u64, len) *% @as(u64, x)) >> 32);
}

fn reduce64(len: u64, x: u64) u64 {
    return @truncate((@as(u128, len) *% @as(u128, x)) >> 64);
}

fn make_fingerprint(hash: u64) Fingerprint {
    return @truncate(hash ^ shr(u64, hash, 32));
}

fn rng_next(seed: *u64) u64 {
    seed.* +%= @as(u64, 0x9E3779B97F4A7C15);
    var z = seed.*;
    z = (z ^ shr(u64, z, 30)) *% @as(u64, 0xBF58476D1CE4E5B9);
    z = (z ^ shr(u64, z, 27)) *% @as(u64, 0x94D049BB133111EB);
    return z ^ shr(u64, z, 31);
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

const Hashes = struct {
    h0: u32,
    h1: u32,
    h2: u32,
};

fn subhash_batch(hash: u64, header: *const Header) Hashes {
    const hi = reduce64(hash, header.segment_count_length);
    const h0 = @as(u32, @truncate(hi));
    var h1 = h0 +% header.segment_length;
    var h2 = h1 +% header.segment_length;
    h1 ^= @as(u32, @truncate(shr(u64, hash, 18))) & header.segment_length_mask;
    h2 ^= @as(u32, @truncate(hash)) & header.segment_length_mask;
    return .{ .h0 = h0, .h1 = h1, .h2 = h2 };
}

fn subhash(index: u64, hash: u64, header: *const Header) u32 {
    var h = reduce64(hash, header.segment_count_length);
    h +%= index *% @as(u64, header.segment_length);
    const hh = hash & @as(u64, (1 << 36) - 1);
    h ^= shr(hh, (36 - 18 * index)) & header.segment_length_mask;
    return @truncate(h);
}

pub fn contains(key: u64, header: *const Header, fingerprints: [*]const Fingerprint) bool {
    const hash = make_hash(key, header.seed);
    var f = make_fingerprint(hash);
    const hashes = subhash_batch(hash, header);
    f ^= fingerprints[hashes.h0] ^ fingerprints[hashes.h1] ^ fingerprints[hashes.h2];
    return f == 0;
}

fn calculate_segment_length(size: u32) u32 {
    const sz = @as(f64, @floatFromInt(size));
    const base = @as(u32, @intFromFloat(@floor(@log(sz) / @log(3.33) + 2.25)));
    return shl(u32, @as(u32, 1), base);
}

fn calculate_size_factor(size: u32) f64 {
    const sz = @as(f64, @floatFromInt(size));
    return @max(1.125, 0.875 + 0.25 * @log(1000000.0) / @log(sz));
}

pub fn calculate_header(num_keys: u32) Header {
    const size = num_keys;
    const segment_length = @min(
        if (size == 0) 4 else calculate_segment_length(size),
        262144,
    );
    const segment_length_mask = segment_length - 1;
    const size_factor = if (size <= 1) 0 else calculate_size_factor(size);
    const capacity = if (size <= 1) 0 else @as(u32, @intFromFloat(@round(@as(f64, @floatFromInt(size)) * size_factor)));
    const init_segment_count = (capacity + segment_length - 1) / segment_length - (ARITY - 1);
    const array_length_calc = (init_segment_count + ARITY - 1) * segment_length;
    const segment_count_calc = (array_length_calc + segment_length - 1) / segment_length;
    const segment_count = if (segment_count_calc <= ARITY - 1)
        1
    else
        segment_count_calc - (ARITY - 1);
    const array_length = (segment_count + ARITY - 1) * segment_length;
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

fn h012_mod(x: u8) u8 {
    return if (x > 2) x - 3 else x;
}

pub const Error = error{
    OutOfMemory,
};

pub fn populate(init_keys: []u64, header: *Header, allocator: Allocator, fingerprints: []Fingerprint) Error!void {
    std.debug.assert(init_keys.len == header.size);
    std.debug.assert(fingerprints.len == header.array_length);

    var rng_counter: u64 = 0x726b2b9d438b9d4d;

    const reverse_order = try allocator.alloc(u64, header.size + 1);
    defer allocator.free(reverse_order);

    const capacity = header.array_length;

    const alone = try allocator.alloc(u32, capacity);
    defer allocator.free(alone);

    const t2_count = try allocator.alloc(u8, capacity);
    defer allocator.free(t2_count);

    const reverse_h = try allocator.alloc(u8, header.size);
    defer allocator.free(reverse_h);

    const t2_hash = try allocator.alloc(u64, capacity);
    defer allocator.free(t2_hash);

    var block_bits = @as(u32, 1);
    while (shl(u32, 1, block_bits) < header.segment_count) {
        block_bits += 1;
    }
    const block = shl(u32, 1, block_bits);
    const start_pos = try allocator.alloc(u32, block);
    defer allocator.free(start_pos);

    var h012: [5]u32 = undefined;

    var keys = init_keys;

    var iter_no: u32 = 0;
    while (true) : (iter_no += 1) {
        if (iter_no + 1 > POPULATE_MAX_ITER) {
            unreachable;
        }

        @memset(reverse_order, 0);
        reverse_order[keys.len] = 1;
        @memset(t2_count, 0);
        @memset(t2_hash, 0);
        header.seed = rng_next(&rng_counter);

        for (0..block) |i| {
            start_pos.ptr[i] = @truncate(shr(u64, (@as(u64, i) *% @as(u64, keys.len)), block_bits));
        }

        const maskblock = block - 1;
        for (0..keys.len) |i| {
            const hash = make_hash(keys.ptr[i], header.seed);
            var segment_index = shr(u64, hash, 64 -% block_bits);
            while (reverse_order.ptr[start_pos.ptr[segment_index]] != 0) {
                segment_index +%= 1;
                segment_index &= maskblock;
            }
            reverse_order.ptr[start_pos.ptr[segment_index]] = hash;
            start_pos.ptr[segment_index] +%= 1;
        }

        var err = false;
        var duplicates: u32 = 0;

        for (0..keys.len) |i| {
            const hash = reverse_order.ptr[i];
            const hashes = subhash_batch(hash, header);
            t2_count.ptr[hashes.h0] +%= 4;
            t2_hash.ptr[hashes.h0] ^= hash;

            t2_count.ptr[hashes.h1] +%= 4;
            t2_count.ptr[hashes.h1] ^= 1;
            t2_hash.ptr[hashes.h1] ^= hash;

            t2_count.ptr[hashes.h2] +%= 4;
            t2_count.ptr[hashes.h2] ^= 2;
            t2_hash.ptr[hashes.h2] ^= hash;

            if (t2_hash.ptr[hashes.h0] & t2_hash.ptr[hashes.h1] & t2_hash.ptr[hashes.h2] == 0) {
                const h0_duplicate = t2_hash.ptr[hashes.h0] == 0 and t2_count.ptr[hashes.h0] == 8;
                const h1_duplicate = t2_hash.ptr[hashes.h1] == 0 and t2_count.ptr[hashes.h1] == 8;
                const h2_duplicate = t2_hash.ptr[hashes.h2] == 0 and t2_count.ptr[hashes.h2] == 8;
                if (h0_duplicate or h1_duplicate or h2_duplicate) {
                    duplicates +%= 1;
                    t2_count.ptr[hashes.h0] -%= 4;
                    t2_hash.ptr[hashes.h0] ^= hash;
                    t2_count.ptr[hashes.h1] -%= 4;
                    t2_count.ptr[hashes.h1] ^= 1;
                    t2_hash.ptr[hashes.h1] ^= hash;
                    t2_count.ptr[hashes.h2] -%= 4;
                    t2_count.ptr[hashes.h2] ^= 2;
                    t2_hash.ptr[hashes.h2] ^= hash;
                }
            }

            err = err or t2_count.ptr[hashes.h0] < 4;
            err = err or t2_count.ptr[hashes.h1] < 4;
            err = err or t2_count.ptr[hashes.h2] < 4;
        }
        if (err) {
            continue;
        }

        var q_size: u32 = 0;

        {
            var i: u32 = 0;
            while (i < capacity) : (i += 1) {
                alone.ptr[q_size] = i;
                q_size += if (shr(u32, t2_count.ptr[i], 2) == 1) 1 else 0;
            }
        }

        var stack_size: u32 = 0;

        while (q_size > 0) {
            q_size -= 1;
            const index = alone.ptr[q_size];
            if (shr(u32, t2_count.ptr[index], 2) == 1) {
                const hash = t2_hash.ptr[index];
                const h012_hashes = subhash_batch(hash, header);
                h012[1] = h012_hashes.h1;
                h012[2] = h012_hashes.h2;
                h012[3] = h012_hashes.h0;
                h012[4] = h012[1];
                const found: u8 = t2_count.ptr[index] & 3;
                reverse_h.ptr[stack_size] = found;
                reverse_order[stack_size] = hash;
                stack_size +%= 1;

                const other_index1 = h012[found +% 1];
                alone.ptr[q_size] = other_index1;
                q_size += @intFromBool((t2_count.ptr[other_index1] >> 2) == 2);
                t2_count.ptr[other_index1] -%= 4;
                t2_count.ptr[other_index1] ^= h012_mod(found +% 1);
                t2_hash.ptr[other_index1] ^= hash;

                const other_index2 = h012[found +% 2];
                alone.ptr[q_size] = other_index2;
                q_size += @intFromBool((t2_count.ptr[other_index2] >> 2) == 2);
                t2_count.ptr[other_index2] -%= 4;
                t2_count.ptr[other_index2] ^= h012_mod(found +% 2);
                t2_hash.ptr[other_index2] ^= hash;
            }
        }

        if (stack_size + duplicates == header.size) {
            keys = keys.ptr[0..stack_size];
            header.size = @intCast(keys.len);
            break;
        }

        // if (duplicates > 0) {
        //     keys = sort_and_remove_duplicates(keys);
        //     TODO
        //     unreachable;
        // }
    }

    var i = keys.len - 1;
    // This wraps the integer around to exit the loop
    // :)
    while (i < keys.len) : (i -%= 1) {
        const hash = reverse_order.ptr[i];
        const xor2 = make_fingerprint(hash);
        const found = reverse_h.ptr[i];
        const h012_hashes = subhash_batch(hash, header);
        h012[0] = h012_hashes.h0;
        h012[1] = h012_hashes.h1;
        h012[2] = h012_hashes.h2;
        h012[3] = h012[0];
        h012[4] = h012[1];

        fingerprints.ptr[h012[found]] = xor2 ^ fingerprints.ptr[h012[found +% 1]] ^ fingerprints.ptr[h012[found +% 2]];
    }
}

pub const Filter = struct {
    const Self = @This();

    header: Header,
    fingerprints: []Fingerprint,
    alloc: Allocator,
    num_hashes: usize,

    pub fn init(alloc: Allocator, hashes: []u64) !Self {
        var header = calculate_header(@intCast(hashes.len));

        const fingerprints = try alloc.alloc(Fingerprint, header.array_length);
        errdefer alloc.free(fingerprints);

        try populate(hashes, &header, alloc, fingerprints);

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
        return contains(hash, &self.header, self.fingerprints.ptr);
    }

    pub fn mem_usage(self: *const Self) usize {
        return self.fingerprints.len * @typeInfo(Fingerprint).int.bits / 8;
    }

    pub fn ideal_mem_usage(self: *const Self) usize {
        return self.num_hashes * @typeInfo(Fingerprint).int.bits / 8;
    }
};
