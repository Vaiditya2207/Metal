const std = @import("std");
const compositor = @import("../../src/render/compositor.zig");

test "compositor.isVisible" {
    // rect fully inside
    try std.testing.expect(compositor.isVisible(10, 10, 0, 100));
    // rect fully above
    try std.testing.expect(!compositor.isVisible(-20, 10, 0, 100));
    // rect fully below
    try std.testing.expect(!compositor.isVisible(110, 10, 0, 100));
    // rect partially visible top
    try std.testing.expect(compositor.isVisible(-5, 10, 0, 100));
    // rect partially visible bottom
    try std.testing.expect(compositor.isVisible(95, 10, 0, 100));
    // rect at exact boundary top (just outside)
    try std.testing.expect(!compositor.isVisible(-10, 10, 0, 100));
    // rect at exact boundary bottom (just outside)
    try std.testing.expect(!compositor.isVisible(100, 10, 0, 100));

    // with scroll
    // rect at 110, scroll 20 -> relative y is 90, visible in 100 height
    try std.testing.expect(compositor.isVisible(110, 10, 20, 100));
    // rect at 10, scroll 20 -> relative y is -10, height 10 -> relative bottom is 0, just outside
    try std.testing.expect(!compositor.isVisible(10, 10, 20, 100));
}
