const std = @import("std");

/// Alternative to modulo operation. Maps random number x to range [0..y)
pub fn reduce(x: u32, y: u32) u32 {
    return @truncate((@as(u64, x) * @as(u64, y)) >> 32);
}

/// Alternative to modulo operation. Maps random number x to range [0..y)
pub fn reduce64(x: u64, y: u64) u64 {
    return @truncate((@as(u128, x) * @as(u128, y)) >> 32);
}
