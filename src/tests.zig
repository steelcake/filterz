const std = @import("std");
const SplitMix64 = std.Random.SplitMix64;

const sbbf = @import("sbbf.zig");
const xorf = @import("xorf.zig");
const ribbon = @import("ribbon.zig");

fn failing_test(comptime Filter: type) !void {
    var hashes = [_]u64{ 72644917353746632, 642569258191439722, 880063444564840048, 936038340777039120, 1463140050281691778, 2534303452491416525, 2932506756478463233, 3162550684756043368, 3222824559290762320, 3304852325422999252, 3340896780712084771, 3576804163975317586, 5194252426355675670, 5285340030140706004, 6038449579595759498, 6129652247619811565, 7505361257740328928, 7624146440976401075, 8000835406817860068, 8865134243681972832, 8947054143473076092, 9184170327892905410, 9247810627123549518, 9428353589346381175, 9439589025481519798, 9726887461280574282, 10228453195936255633, 10409275278410212535, 10970487830014977086, 11056890753627467201, 11173871646086530417, 11200808152604239572, 11662532023175458543, 12578389580290726414, 13694005592234131760, 14036019601299503951, 14371822432590631259, 14751664096118349536, 15331668869258475036, 16078852908519881396, 16259148258571684489, 18009237999125136770 };
    var filter = try Filter.init(std.testing.allocator, &hashes);
    defer filter.deinit();
}

fn smoke_test(comptime Filter: type) !void {
    try failing_test(Filter);

    var rand = SplitMix64.init(0);
    const num_hashes = 10000;
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
        smoke_test(Filter) catch |e| {
            std.log.warn("Failed to run for filter {s}", .{@typeName(Filter)});
            return e;
        };
    }
}

fn ToFuzz(comptime Filter: type) type {
    return struct {
        fn to_fuzz(_: @TypeOf(.{}), input: []const u8) anyerror!void {
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
    xorf.Filter(u9, 4),
    xorf.Filter(u10, 3),
    xorf.Filter(u7, 4),
    ribbon.Filter(u64, u8),
    ribbon.Filter(u64, u16),
    ribbon.Filter(u64, u32),
    ribbon.Filter(u64, u10),
    ribbon.Filter(u64, u11),
    ribbon.Filter(u64, u12),
    ribbon.Filter(u64, u20),
    ribbon.Filter(u64, u7),
    ribbon.Filter(u128, u8),
    ribbon.Filter(u128, u16),
    ribbon.Filter(u128, u32),
    ribbon.Filter(u128, u10),
    ribbon.Filter(u128, u11),
    ribbon.Filter(u128, u12),
    ribbon.Filter(u128, u20),
    ribbon.Filter(u128, u7),
};

test "fuzz" {
    inline for (FILTERS) |Filter| {
        try std.testing.fuzz(.{}, ToFuzz(Filter).to_fuzz, .{});
    }
}
