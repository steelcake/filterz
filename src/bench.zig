const std = @import("std");
const filterz = @import("filterz");
const File = std.fs.File;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Address = [20]u8;

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    const indices = try read_file(alloc, "addr.index");
    defer alloc.free(indices);

    const raw_addrs = try read_file(alloc, "addr.data");
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

        std.debug.assert(section.len == idx);
    }

    try print_hex(alloc, sections.items[69][21]);
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
            hashes[write_idx] = h;
            write_idx += 1;
        }
    }

    len.* = write_idx;

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
