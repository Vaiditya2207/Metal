const std = @import("std");
const events = @import("../../src/platform/events.zig");

test "EventQueue wrap-around" {
    var queue = events.EventQueue{};

    // Fill queue
    var i: usize = 0;
    while (i < 255) : (i += 1) {
        queue.push(.{ .event_type = .mouse_down, .x = @as(f32, @floatFromInt(i)) });
    }

    // Attempting to push 256th should fail (no change in head)
    const prev_head = queue.head;
    queue.push(.{ .event_type = .mouse_up });
    try std.testing.expectEqual(prev_head, queue.head);

    // Pop one
    const first = queue.pop();
    try std.testing.expect(first != null);
    try std.testing.expectEqual(@as(f32, 0), first.?.x);

    // Push one to wrap around
    queue.push(.{ .event_type = .scroll, .y = 100 });
    try std.testing.expectEqual(@as(usize, 0), queue.head);
}

test "Renderer processEvents clamping" {
    const renderer_mod = @import("../../src/render/renderer.zig");
    var r = renderer_mod.Renderer{
        .device = undefined,
        .command_queue = undefined,
    };
    r.scroll.setScrollY(10);

    events.global_queue.push(.{ .event_type = .scroll, .y = -20 });
    r.processEvents();

    try std.testing.expectEqual(@as(f32, 0), r.scroll.scroll_y);
}
