const std = @import("std");
const filterz = @import("filterz");
const sbbf = filterz.sbbf;

pub fn main() void {
    var res = @as(u32, 0);
    var block align(sbbf.BLOCK_SIZE) = [_]u8{0} ** sbbf.BLOCK_SIZE;

    for (0..255) |i| {
        res += if (sbbf.block_insert_check(&block, @truncate(i))) 5 else 2;
    }

    std.debug.print("hello {d}\n", .{res});
}
