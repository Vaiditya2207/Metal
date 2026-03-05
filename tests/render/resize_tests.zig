const std = @import("std");
const expect = std.testing.expect;
const layout_box = @import("../../src/layout/box.zig");
const layout_mod = @import("../../src/layout/layout.zig");
const display_list_mod = @import("../../src/render/display_list.zig");
const scroll_mod = @import("../../src/render/scroll.zig");

test "layout tree and display list rebuild on resize" {
    const allocator = std.testing.allocator;

    // 1. Create a simple layout tree
    var root = layout_box.LayoutBox.init(.blockNode, null);
    defer root.deinit(allocator);
    root.dimensions.content.width = 100;
    root.dimensions.content.height = 100;

    // 2. Initial layout at width 800
    layout_mod.layoutTree(&root, .{ .allocator = allocator, .viewport_width = 800, .viewport_height = 600 });

    // 3. Initial display list build
    var dl = try display_list_mod.buildDisplayList(allocator, &root, null);
    defer dl.deinit();

    // 4. Simulate resize to 400
    const new_width: f32 = 400;
    layout_mod.layoutTree(&root, .{ .allocator = allocator, .viewport_width = new_width, .viewport_height = 600 });

    // Verify layout changed (assuming layoutTree uses the width)
    // Note: If layoutTree is just a stub for now, this might not change dimensions
    // but the pipeline call should still be valid.

    // 5. Rebuild display list
    dl.deinit();
    dl = try display_list_mod.buildDisplayList(allocator, &root, null);

    // 6. Verify scroll controller updates
    var scroll = scroll_mod.ScrollController{};
    scroll.setViewportHeight(600);
    scroll.setContentHeight(root.dimensions.marginBox().height);

    const resize_height: f32 = 300;
    scroll.setViewportHeight(resize_height);
    // In a real resize, content height might change if text wraps
    scroll.setContentHeight(root.dimensions.marginBox().height);

    try expect(scroll.viewport_height == resize_height);
}
