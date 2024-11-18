const std = @import("std");
const filterz = @import("filterz");
const File = std.fs.File;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Address = [20]u8;

pub fn main() !void {
    const alloc = std.heap.page_allocator;

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

    var total_mem_usage: usize = 0;

    for (sections.items) |section| {
        var len: usize = 0;
        const hashes = try hash_section(alloc, section, &len);
        defer alloc.free(hashes);

        total_mem_usage += try filter_mem_usage(alloc, hashes[0..len]);
    }

    std.debug.print("total_mem_usage={d}\n", .{total_mem_usage});
}

fn filter_mem_usage(alloc: Allocator, hashes: []u64) !usize {
    for (1..hashes.len) |i| {
        std.debug.assert(hashes[i - 1] != hashes[i]);
    }
    const filter = try filterz.ribbon.Filter(u16).init(alloc, hashes);
    //const filter = try filterz.xorf.Filter(u16, 3).init(alloc, hashes);
    defer filter.deinit();
    return filter.mem_usage();
}

fn hash_section(alloc: Allocator, section: []const Address, len: *usize) ![]u64 {
    const hashes = try alloc.alloc(u64, section.len);
    errdefer alloc.free(hashes);

    for (0..section.len) |i| {
        hashes[i] = std.hash.XxHash3.hash(0, &section[i]);
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
