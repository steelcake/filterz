const std = @import("std");
const filterz = @import("filterz");
const sbbf = filterz.sbbf;

pub fn main() void {
    var res = @as(u32, 0);
    var bucket align(32) = [_]u32{0} ** 8;

    for (0..255) |i| {
        res += if (sbbf.bucket_insert_check(&bucket, @truncate(i))) 5 else 2;
    }

    std.debug.print("hello {d}\n", .{res});
}
