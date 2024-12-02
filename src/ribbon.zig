const std = @import("std");
const Allocator = std.mem.Allocator;
const SplitMix = std.Random.SplitMix64;

fn reduce(len: u32, x: u32) u32 {
    return @truncate((@as(u64, len) * @as(u64, x)) >> 32);
}

fn calculate_start_pos(comptime CoeffRow: type, seed: u64, n: u32, hash: u64) u32 {
    const coeff_bits = @typeInfo(CoeffRow).int.bits;
    const W = coeff_bits / 4;
    const hash0 = seed ^ hash;
    const h: u32 = @truncate(hash0 ^ (hash0 >> 32));
    const smash_pos = reduce(n + W * 2, h);
    const pos = smash_pos -| W;
    return @min(n - 1, pos);
}

const coeff_factor0: u64 = 0x876f170be4f1fcb9;
const coeff_factor1: u64 = 0xf0433a4aecda4c5f;

fn calculate_coeff_row(comptime CoeffRow: type, seed: u64, hash: u64) CoeffRow {
    if (CoeffRow == u64) {
        return (seed ^ hash) | 1;
    } else if (CoeffRow == u32) {
        return @truncate((seed ^ hash) | 1);
    } else if (CoeffRow == u128) {
        const a: u128 = (seed *% coeff_factor0) ^ hash;
        const b: u128 = (seed *% coeff_factor1) ^ @byteSwap(hash);
        const row = (a << 64) | b;
        return row | 1;
    } else {
        @compileError("unimplemented coeffrow");
    }
}

fn calculate_size(comptime CoeffRow: type, num_hashes: usize, multiplier: usize) usize {
    return (num_hashes * multiplier + 99) / 100 + @typeInfo(CoeffRow).int.bits - 1;
}

const ConstructError = error{
    OutOfMemory,
    Fail,
};

fn calculate_result_row(comptime ResultRow: type, seed: u64, hash: u64) ResultRow {
    const h = seed ^ hash;
    return @truncate((h >> 32) ^ h);
}

pub fn construct(comptime CoeffRow: type, comptime ResultRow: type, alloc: Allocator, hashes: []u64, seed: *u64) ConstructError![]ResultRow {
    const MIN_MULTIPLIER = 102; // % space overhead
    const MAX_MULTIPLIER = 140;

    const max_size = calculate_size(CoeffRow, hashes.len, MAX_MULTIPLIER);
    const coeff_matrix_storage = try alloc.alloc(CoeffRow, max_size);
    defer alloc.free(coeff_matrix_storage);
    const result_matrix_storage = try alloc.alloc(ResultRow, max_size);
    defer alloc.free(result_matrix_storage);

    var random = SplitMix.init(seed.*);

    for (MIN_MULTIPLIER..MAX_MULTIPLIER + 1) |multiplier| {
        const size: u32 = @intCast(calculate_size(CoeffRow, hashes.len, multiplier));
        const start_range = size + 1 - @typeInfo(CoeffRow).int.bits;
        // const num_tries = multiplier - MIN_MULTIPLIER + 1;
        const num_tries = 1;

        const coeff_matrix = coeff_matrix_storage[0..size];
        const result_matrix = result_matrix_storage[0..size];

        tries: for (0..num_tries) |_| {
            const new_seed = random.next();
            @memset(coeff_matrix, 0);
            @memset(result_matrix, 0);

            for (hashes) |hash| {
                var start_pos = calculate_start_pos(CoeffRow, new_seed, start_range, hash);
                var coeff_row = calculate_coeff_row(CoeffRow, new_seed, hash);
                var result_row = calculate_result_row(ResultRow, new_seed, hash);

                while (true) {
                    const existing = coeff_matrix[start_pos];

                    if (existing == 0) {
                        coeff_matrix[start_pos] = coeff_row;
                        result_matrix[start_pos] = result_row;
                        break;
                    }

                    coeff_row ^= existing;
                    result_row ^= result_matrix[start_pos];
                    if (coeff_row == 0) {
                        if (result_row == 0) {
                            break;
                        } else {
                            continue :tries;
                        }
                    }
                    const leading_zeroes = @ctz(coeff_row);
                    start_pos += leading_zeroes;
                    coeff_row = std.math.shr(CoeffRow, coeff_row, leading_zeroes);
                }
            }

            seed.* = new_seed;

            const solution_matrix = try alloc.alloc(ResultRow, size);

            const result_bits = @typeInfo(ResultRow).int.bits;

            var state: [result_bits]CoeffRow = undefined;
            @memset(state[0..result_bits], 0);

            var i = size;
            while (i > 0) {
                i -= 1;

                var solution_row: ResultRow = 0;
                const coeff_row = coeff_matrix[i];
                const result_row = result_matrix[i];

                for (0..result_bits) |j| {
                    var tmp: CoeffRow = std.math.shl(CoeffRow, state[j], 1);
                    const bit = bit_parity(CoeffRow, tmp & coeff_row) ^ (((std.math.shr(ResultRow, result_row, j))) & 1);
                    tmp |= @as(CoeffRow, bit);
                    state[j] = tmp;
                    solution_row |= std.math.shl(ResultRow, @as(ResultRow, @intCast(bit)), j);
                }

                solution_matrix[i] = solution_row;
            }

            return solution_matrix;
        }
    }

    return ConstructError.Fail;
}

fn check_filter(comptime CoeffRow: type, comptime RealResultRow: type, solution_matrix: []const RealResultRow, seed: u64, hash: u64) bool {
    const rr_bits = @typeInfo(RealResultRow).int.bits;
    const ResultRow = if (rr_bits > 32)
        @compileError("bad result row type")
    else if (rr_bits > 16)
        u32
    else if (rr_bits > 8)
        u16
    else if (rr_bits > 0)
        u8
    else
        @compileError("impossible");

    const coeff_bits = @typeInfo(CoeffRow).int.bits;

    const start_range: u32 = @intCast(solution_matrix.len + 1 - coeff_bits);
    const start_pos = calculate_start_pos(CoeffRow, seed, start_range, hash);
    const coeff_row = calculate_coeff_row(CoeffRow, seed, hash);
    const expected_result_row = calculate_result_row(RealResultRow, seed, hash);

    const num_rows_per_vec = @divExact(256, @typeInfo(ResultRow).int.bits);
    const num_vecs = @divExact(coeff_bits, num_rows_per_vec);

    const Vec = @Vector(num_rows_per_vec, ResultRow);

    var data: [coeff_bits]ResultRow align(64) = undefined;
    for (0..coeff_bits) |i| {
        // use raw pointer here since compiler can't remove the bounds check
        data[i] = solution_matrix.ptr[start_pos + i];
    }

    const sol_matrix_v = @as([*]Vec, @ptrCast(&data))[0..num_vecs];
    var result_rows: Vec = @splat(0);

    for (0..num_vecs) |i| {
        const idx = i * num_rows_per_vec;

        var rr: Vec = undefined;
        for (0..num_rows_per_vec) |j| {
            rr[j] = @truncate(std.math.shr(CoeffRow, coeff_row, idx + j));
        }

        const sol_v = sol_matrix_v.ptr[i];

        const zeroes: Vec = @splat(0);
        const ones: Vec = @splat(1);

        result_rows ^= sol_v & (zeroes -% (rr & ones));
    }

    return expected_result_row == @as(RealResultRow, @truncate(@reduce(.Xor, result_rows)));
}

fn bit_parity(comptime CoeffRow: type, val: CoeffRow) u8 {
    return @popCount(val) & 1;
}

pub fn Filter(comptime CoeffRow: type, comptime ResultRow: type) type {
    return struct {
        const Self = @This();

        seed: u64,
        solution_matrix: []ResultRow,
        alloc: Allocator,
        num_hashes: usize,

        pub fn init(alloc: Allocator, hashes: []u64) !Self {
            var seed: u64 = 12;
            const solution_matrix = try construct(CoeffRow, ResultRow, alloc, hashes, &seed);

            return Self{
                .seed = seed,
                .solution_matrix = solution_matrix,
                .alloc = alloc,
                .num_hashes = hashes.len,
            };
        }

        pub fn deinit(self: Self) void {
            self.alloc.free(self.solution_matrix);
        }

        pub fn check(self: *const Self, hash: u64) bool {
            return check_filter(CoeffRow, ResultRow, self.solution_matrix, self.seed, hash);
        }

        pub fn mem_usage(self: *const Self) usize {
            return self.solution_matrix.len * @typeInfo(ResultRow).int.bits / 8;
        }

        pub fn ideal_mem_usage(self: *const Self) usize {
            return self.num_hashes * @typeInfo(ResultRow).int.bits / 8;
        }
    };
}
