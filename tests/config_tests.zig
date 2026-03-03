const std = @import("std");
const config = @import("../src/config.zig");

test "config returns valid defaults" {
    const cfg = config.getConfig();
    try std.testing.expect(cfg.parser.max_tree_depth == 512);
    try std.testing.expect(cfg.parser.max_total_nodes == 1000000);
    try std.testing.expect(cfg.window.width == 1280);
    try std.testing.expect(cfg.renderer.target_fps == 120);
}
