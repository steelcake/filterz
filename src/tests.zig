const std = @import("std");
const SplitMix64 = std.Random.SplitMix64;

const sbbf = @import("sbbf.zig");
const xorf = @import("xorf.zig");
const ribbon = @import("ribbon.zig");

fn smoke_test(comptime Filter: type) !void {
    var rand = SplitMix64.init(0);
    const num_hashes = 100000;
    const alloc = std.testing.allocator;
    var hashes = try alloc.alloc(u64, num_hashes);
    defer alloc.free(hashes);

    for (0..num_hashes) |i| {
        hashes[i] = std.hash.XxHash3.hash(rand.next(), std.mem.asBytes(&rand.next()));
    }

    const filter = try Filter.init(alloc, hashes);
    defer filter.deinit();

    for (hashes) |h| {
        try std.testing.expect(filter.check(h));
    }
}

test "smoke" {
    inline for (FILTERS) |Filter| {
        try smoke_test(Filter);
    }
}

fn ToFuzz(comptime Filter: type) type {
    return struct {
        fn to_fuzz(input: []const u8) anyerror!void {
            if (input.len < 8) {
                return;
            }

            const alloc = std.testing.allocator;

            var hashes = try alloc.alloc(u64, input.len);
            defer alloc.free(hashes);

            var rand = SplitMix64.init(31);

            for (input, 0..) |_, i| {
                hashes[i] = rand.next();
            }

            var filter = try Filter.init(alloc, hashes);
            defer filter.deinit();

            for (hashes) |h| {
                try std.testing.expect(filter.check(h));
            }
        }
    };
}

const FILTERS = [_]type{
    sbbf.Filter(8),
    sbbf.Filter(10),
    sbbf.Filter(16),
    xorf.Filter(u16, 4),
    xorf.Filter(u16, 3),
    xorf.Filter(u8, 4),
    xorf.Filter(u8, 3),
    xorf.Filter(u32, 4),
    xorf.Filter(u32, 3),
};

test "fuzz" {
    inline for (FILTERS) |Filter| {
        try std.testing.fuzz(ToFuzz(Filter).to_fuzz, .{});
    }
}
