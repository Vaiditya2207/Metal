const std = @import("std");

pub fn main() !void {
    // Using std.debug.print for initial toolchain validation (Zig 0.15.2)
    std.debug.print("Metal Browser Engine — Version 0.1.0-draft\n", .{});
    std.debug.print("Starting Phase 0 toolchain validation...\n", .{});
}

test "basic test" {
    try std.testing.expect(true);
}
