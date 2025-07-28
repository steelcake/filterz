const std = @import("std");
const Allocator = std.mem.Allocator;
const hash_fn = std.hash.RapidHash.hash;

const xorf = @import("xorf.zig");

fn to_fuzz(_: void, data: []const u8) anyerror!void {
    var general_purpose_allocator: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const gpa = general_purpose_allocator.allocator();
    defer {
        switch (general_purpose_allocator.deinit()) {
            .ok => {},
            .leak => |l| {
                std.debug.panic("LEAK: {any}", .{l});
            },
        }
    }

    if (data.len == 0) return;

    const num_keys: usize = data[0];

    if (data.len < num_keys + 1) return;

    const lengths = data[1 .. num_keys + 1];

    var total_len: usize = 0;
    for (lengths) |len| {
        total_len += len;
    }
    if (data.len < num_keys + 1 + total_len) return;

    const keys = try gpa.alloc([]const u8, num_keys);
    defer gpa.free(keys);

    var start: usize = num_keys + 1;
    for (lengths, 0..) |len, key_idx| {
        keys[key_idx] = data[start .. start + len];
        start += len;
    }

    var num_hashes: usize = 0;
    const hashes_buf = try prepare_keys(gpa, keys, &num_hashes);
    defer gpa.free(hashes_buf);
    const hashes = hashes_buf[0..num_hashes];

    const filter = try xorf.Filter(u16, 3).init(gpa, hashes);
    defer filter.deinit();

    for (hashes) |h| {
        std.debug.assert(filter.check(h));
    }
}

fn prepare_keys(alloc: Allocator, keys: []const []const u8, len: *usize) ![]u64 {
    if (keys.len == 0) {
        len.* = 0;
        return &.{};
    }

    const hashes = try alloc.alloc(u64, keys.len);
    errdefer alloc.free(hashes);

    for (0..keys.len) |i| {
        hashes[i] = hash_key(keys[i]);
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

fn hash_key(key: []const u8) u64 {
    return hash_fn(0, key);
}

test "fuzz" {
    try std.testing.fuzz({}, to_fuzz, .{});
}
