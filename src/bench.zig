const std = @import("std");
const filterz = @import("filterz");
const File = std.fs.File;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Timer = std.time.Timer;
const xorf = filterz.xorf;
const sbbf = filterz.sbbf;
const ribbon = filterz.ribbon;
// const huge_alloc = @import("huge_alloc");
// const HugePageAlloc = huge_alloc.HugePageAlloc;
const hash_fn = std.hash.RapidHash.hash;

fn hash_addr(addr: []const u8) u64 {
    return hash_fn(0, addr);
}

// fn hash_addr(seed: u64, addr: []const u8) u64 {
//     var hash: [8]u8 align(8) = @bitCast(seed);

//     for (0..20) |i| {
//         hash[i % 8] ^= addr[i];
//     }

//     //     // for (0..2) |i| {
//     //     //     const ptr: *const u64 = @ptrCast(@alignCast(&addr[i * 8]));
//     //     //     hash ^= ptr.*;
//     //     // }

//     //     // const ptr: *const u32 = @ptrCast(@alignCast(&addr[16]));
//     //     // hash ^= @as(u64, ptr.*);

//     //     // for (0..addr.len % 8) |i| {
//     //     //     hash ^= @as(u64, addr[64 + i]) << (i * 8);
//     //     // }

//     return @bitCast(hash);
// }

const Address = [20]u8;

pub fn main() !void {
    // var ha_alloc = HugePageAlloc.init(.{ .budget_log2 = 34 });
    // defer ha_alloc.deinit();

    const alloc = std.heap.page_allocator; // ha_alloc.allocator();

    const indices = try read_file(alloc, "bench-data/addr.index", null);
    defer alloc.free(indices);

    std.debug.print("read addrs\n", .{});

    const raw_addrs = try read_file(alloc, "bench-data/addr.data", 10 * 1024 * 1024 * 1024);
    defer alloc.free(raw_addrs);

    std.debug.print("finished reading addrs\n", .{});

    const addrs: []const Address = @as([*]Address, @ptrCast(raw_addrs.ptr))[0 .. raw_addrs.len / 20];

    var start: usize = 0;
    var index_iter = std.mem.splitScalar(u8, indices[1..], ' ');

    var sections = ArrayList([]const Address).init(alloc);
    defer sections.deinit();

    std.debug.print("parsing sections\n", .{});

    while (index_iter.next()) |index| {
        const idx = try std.fmt.parseInt(usize, index, 10);
        const section = addrs[start .. start + idx];
        try sections.append(section);
        start += idx;
    }

    //try print_hex(alloc, sections.items[69][21]);

    std.debug.print("num_sections={d}\n", .{sections.items.len});

    var query_hashes = ArrayList(u64).init(alloc);
    defer query_hashes.deinit();

    var addr_scratch: Address align(64) = undefined;

    var args = std.process.args();
    _ = args.next() orelse unreachable;

    while (args.next()) |arg| {
        const addr = try std.fmt.hexToBytes(&addr_scratch, arg);
        if (addr.len != 20) {
            @panic("bad address");
        }
        const hash = hash_addr(addr);
        try query_hashes.append(hash);
    }

    var randy = std.Random.ChaCha.init(.{0} ** 32);
    for (0..4096) |_| {
        randy.fill(&addr_scratch);
        const hash = hash_addr(&addr_scratch);
        try query_hashes.append(hash);
    }

    inline for (FILTERS, FILTER_NAMES) |Filter, name| @"continue": {
        const stats = run_bench(Filter, alloc, sections.items, query_hashes.items) catch {
            std.debug.print("{s} FAILED\n", .{name});
            break :@"continue";
        };

        const estimate = @as(f64, @floatFromInt(stats.num_hits * 200000 + stats.query_time));

        const space_overhead = (@as(f64, @floatFromInt(stats.mem_usage)) - @as(f64, @floatFromInt(stats.ideal_mem_usage))) / @as(f64, @floatFromInt(stats.ideal_mem_usage));

        std.debug.print("{s}: {any} Estimated query cost: {d:.4}, Space Overhead: {d:.4}, Time per query: {d}\n", .{ name, stats, estimate, space_overhead, stats.query_time / stats.num_queries });
    }
}

const FILTERS = [_]type{
    // ribbon.Filter(u4),
    // ribbon.Filter(u5),
    // xorf.Filter(u4, 3),
    // xorf.Filter(u4, 4),
    // sbbf.Filter(16),
    // sbbf.Filter(18),
    // xorf.Filter(u16, 4),
    // xorf.Filter(u16, 3),
    // ribbon.Filter(u16),
    // sbbf.Filter(8),
    // sbbf.Filter(9),
    // ribbon.Filter(u8),
    // ribbon.Filter(u9),
    // ribbon.Filter(u10),
    // xorf.Filter(u8, 4),
    // xorf.Filter(u8, 3),
    // ribbon.Filter(u128, u6),
    // ribbon.Filter(u128, u7),
    // ribbon.Filter(u128, u8),
    // ribbon.Filter(u128, u9),
    // ribbon.Filter(u128, u10),
    ribbon.Filter(u128, u16),
    // ribbon.Filter(u64, u6),
    // ribbon.Filter(u64, u7),
    // ribbon.Filter(u64, u8),
    // ribbon.Filter(u64, u9),
    // ribbon.Filter(u64, u10),
    // xorf.Filter(u6, 3),
    // xorf.Filter(u6, 4),
    // xorf.Filter(u7, 3),
    // xorf.Filter(u7, 4),
    // xorf.Filter(u8, 3),
    // xorf.Filter(u8, 4),
    // xorf.Filter(u9, 3),
    // xorf.Filter(u9, 4),
    xorf.Filter(u16, 3),
    xorf.Filter(u16, 4),
    // sbbf.Filter(6),
    // sbbf.Filter(7),
    // sbbf.Filter(8),
    // sbbf.Filter(9),
    // sbbf.Filter(10),
    // sbbf.Filter(12),
    // sbbf.Filter(13),
    sbbf.Filter(24),
};

const FILTER_NAMES = [_][]const u8{
    // "ribbon4",
    // "ribbon5",
    // "xorf4_3",
    // "xorf4_4",
    // "sbbf16",
    // "sbbf18",
    // "xorf16_4",
    // "xorf16_3",
    // "ribbon16",
    // "sbbf8",
    // "sbbf9",
    // "ribbon8",
    // "ribbon9",
    // "ribbon10",
    // "xorf8_4",
    // "xorf8_3",
    // "ribbon128_6",
    // "ribbon128_7",
    // "ribbon128_8",
    // "ribbon128_9",
    // "ribbon128_10",
    "ribbon128_16",
    // "ribbon64_6",
    // "ribbon64_7",
    // "ribbon64_8",
    // "ribbon64_9",
    // "ribbon64_10",
    // "xorf3_6",
    // "xorf4_6",
    // "xorf3_7",
    // "xorf4_7",
    // "xorf3_8",
    // "xorf4_8",
    // "xorf3_9",
    // "xorf4_9",
    "xorf3_16",
    "xorf4_16",
    // "sbbf6",
    // "sbbf7",
    // "sbbf8",
    // "sbbf9",
    // "sbbf10",
    // "sbbf12",
    // "sbbf13",
    "sbbf24",
};

const BenchStats = struct {
    query_time: u64 = 0,
    construct_time: u64 = 0,
    mem_usage: usize = 0,
    ideal_mem_usage: usize = 0,
    num_hits: u64 = 0,
    num_queries: u64 = 0,
};

fn run_bench(comptime Filter: type, alloc: Allocator, sections: [][]const Address, query_hashes: []u64) !BenchStats {
    const hash_sections = try alloc.alloc([]u64, sections.len);
    defer alloc.free(hash_sections);

    for (sections, 0..) |section, i| {
        var len: usize = 0;
        const hashes = try hash_section(alloc, section, &len);
        hash_sections[i] = hashes[0..len];
    }

    defer for (hash_sections, 0..) |s, i| {
        alloc.free(s.ptr[0..sections[i].len]);
    };

    var timer = try Timer.start();

    const filters = try build_filters(Filter, alloc, hash_sections);
    defer alloc.free(filters);
    defer for (filters) |f| {
        f.deinit();
    };

    var stats: BenchStats = .{
        .construct_time = timer.lap(),
    };

    for (filters) |f| {
        stats.mem_usage += f.mem_usage();
        stats.ideal_mem_usage += f.ideal_mem_usage();
    }

    _ = timer.lap();

    for (filters) |f| {
        for (query_hashes) |h| {
            stats.num_hits +%= @intFromBool(f.check(h));
            stats.num_queries +%= 1;
        }
    }

    stats.query_time = timer.lap();

    return stats;
}

fn build_filters(comptime Filter: type, alloc: Allocator, hash_sections: [][]u64) ![]Filter {
    const filters = try alloc.alloc(Filter, hash_sections.len);
    errdefer alloc.free(filters);
    for (hash_sections, 0..) |section, i| {
        const filter = try build_filter(Filter, alloc, section);
        filters[i] = filter;
    }

    return filters;
}

fn build_filter(comptime Filter: type, alloc: Allocator, hashes: []u64) !Filter {
    if (try has_duplicate(alloc, hashes)) {
        @panic("failed deduplication");
    }
    return try Filter.init(alloc, hashes);
}

fn hash_section(alloc: Allocator, section: []const Address, len: *usize) ![]u64 {
    const hashes = try alloc.alloc(u64, section.len);
    errdefer alloc.free(hashes);

    for (0..section.len) |i| {
        hashes[i] = hash_addr(&section[i]);
    }

    std.mem.sort(u64, hashes, {}, std.sort.asc(u64));

    var write_idx: usize = 0;

    for (hashes[1..]) |h| {
        if (h != hashes[write_idx]) {
            write_idx += 1;
            hashes[write_idx] = h;
        }
    }

    len.* = write_idx + 1;

    return hashes;
}

fn has_duplicate(
    alloc: Allocator,
    hashes: []u64,
) !bool {
    var hm = std.AutoHashMap(u64, void).init(alloc);
    defer hm.deinit();

    for (hashes) |h| {
        const old = try hm.fetchPut(h, undefined);
        if (old != null) {
            return true;
        }
    }

    return false;
}

fn print_hex(alloc: Allocator, addr: Address) !void {
    var list = ArrayList(u8).init(alloc);
    defer list.deinit();

    var fmat = std.fmt.fmtSliceHexLower(&addr);

    try fmat.format(
        "{}",
        .{},
        list.writer(),
    );

    std.debug.print("{s}\n", .{list.items});
}

fn read_file(alloc: Allocator, path: []const u8, size_hint: ?usize) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    return try file.readToEndAllocOptions(
        alloc,
        std.math.maxInt(usize),
        size_hint,
        std.mem.Alignment.@"64",
        null,
    );
}
