const std = @import("std");
const app = @import("platform/app.zig");
const window = @import("platform/window.zig");
const renderer = @import("render/renderer.zig");

pub fn main() !void {
    // 1. Initialize Application
    const my_app = try app.App.init();
    _ = my_app;

    // 2. Initialize Renderer (Metal Device & Queue)
    var my_renderer = try renderer.Renderer.init();

    // 3. Create Window
    var my_window = try window.Window.init("Metal", 1280, 800);

    // 4. Setup Metal View
    const view = try my_window.setMetalView(my_renderer.device);

    // 5. Connect Renderer to View Delegate
    app.objc.set_metal_delegate(view, &my_renderer, renderer.Renderer.draw);

    std.debug.print("Metal Browser Engine — Version 0.1.0-draft\n", .{});
    std.debug.print("Phase 1: Window initialized and Metal surface ready.\n", .{});

    // 6. Run Application Loop
    app.objc.run_application();
}

test "basic test" {
    try std.testing.expect(true);
}
