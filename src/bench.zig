const std = @import("std");
const filterz = @import("filterz");
const File = std.fs.File;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Timer = std.time.Timer;
const xorf = filterz.xorf;
const sbbf = filterz.sbbf;
const ribbon = filterz.ribbon;
const hash_addr = std.hash.XxHash3.hash;
const huge_alloc = @import("huge_alloc");
const HugePageAlloc = huge_alloc.HugePageAlloc;

const Address = [20]u8;

pub fn main() !void {
    var ha_alloc = HugePageAlloc.init(.{ .budget_log2 = 40 });
    defer ha_alloc.deinit();

    const alloc = ha_alloc.allocator();

    const indices = try read_file(alloc, "bench-data/addr.index");
    defer alloc.free(indices);

    const raw_addrs = try read_file(alloc, "bench-data/addr.data");
    defer alloc.free(raw_addrs);

    const addrs: []const Address = @as([*]Address, @ptrCast(raw_addrs.ptr))[0 .. raw_addrs.len / 20];

    var start: usize = 0;
    var index_iter = std.mem.splitScalar(u8, indices[1..], ' ');

    var sections = ArrayList([]const Address).init(alloc);
    defer sections.deinit();

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

    var addr_scratch: Address = undefined;

    var args = std.process.args();
    _ = args.next() orelse unreachable;

    while (args.next()) |arg| {
        const addr = try std.fmt.hexToBytes(&addr_scratch, arg);
        if (addr.len != 20) {
            @panic("bad address");
        }
        const hash = hash_addr(0, addr);
        try query_hashes.append(hash);
    }

    inline for (FILTERS, FILTER_NAMES) |Filter, name| {
        const stats = try run_bench(Filter, alloc, sections.items, query_hashes.items);

        std.debug.print("{s}: {any}\n", .{ name, stats });
    }
}

const FILTERS = [_]type{
    sbbf.Filter(16),
    sbbf.Filter(18),
    //xorf.Filter(u16, 4),
    //xorf.Filter(u16, 3),
    ribbon.Filter(u16),
    sbbf.Filter(8),
    sbbf.Filter(9),
    ribbon.Filter(u8),
};

const FILTER_NAMES = [_][]const u8{
    "sbbf16",
    "sbbf18",
    //"xorf4",
    //"xorf3",
    "ribbon",
    "sbbf8",
    "sbbf9",
    "ribbon8",
};

const BenchStats = struct {
    query_time: u64 = 0,
    construct_time: u64 = 0,
    mem_usage: usize = 0,
    num_hits: u64 = 0,
};

fn run_bench(comptime Filter: type, alloc: Allocator, sections: [][]const Address, query_hashes: []u64) !BenchStats {
    var timer = try Timer.start();

    const filters = try build_filters(Filter, alloc, sections);
    defer alloc.free(filters);
    defer for (filters) |f| {
        f.deinit();
    };

    var stats: BenchStats = .{
        .construct_time = timer.lap(),
    };

    for (filters) |f| {
        stats.mem_usage += f.mem_usage();
    }

    _ = timer.lap();

    for (filters) |f| {
        for (query_hashes) |h| {
            stats.num_hits += @intFromBool(f.check(h));
        }
    }

    stats.query_time = timer.lap();

    return stats;
}

fn build_filters(comptime Filter: type, alloc: Allocator, sections: [][]const Address) ![]Filter {
    const filters = try alloc.alloc(Filter, sections.len);
    errdefer alloc.free(filters);
    for (sections, 0..) |section, i| {
        var len: usize = 0;
        const hashes = try hash_section(alloc, section, &len);
        defer alloc.free(hashes);

        const filter = try build_filter(Filter, alloc, hashes[0..len]);
        filters[i] = filter;
    }

    return filters;
}

fn build_filter(comptime Filter: type, alloc: Allocator, hashes: []u64) !Filter {
    for (1..hashes.len) |i| {
        std.debug.assert(hashes[i - 1] != hashes[i]);
    }
    return try Filter.init(alloc, hashes);
}

fn hash_section(alloc: Allocator, section: []const Address, len: *usize) ![]u64 {
    const hashes = try alloc.alloc(u64, section.len);
    errdefer alloc.free(hashes);

    for (0..section.len) |i| {
        hashes[i] = hash_addr(0, &section[i]);
    }

    std.sort.pdq(u64, hashes, {}, std.sort.asc(u64));

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

fn read_file(alloc: Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    return try file.readToEndAlloc(
        alloc,
        std.math.maxInt(usize),
    );
}
