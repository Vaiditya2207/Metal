const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Metal Browser Engine — Version 0.1.0-draft\n", .{});
    try stdout.print("Starting Phase 0 toolchain validation...\n", .{});
}

test "basic test" {
    try std.testing.expect(true);
}
