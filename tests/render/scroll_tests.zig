const std = @import("std");
const ScrollController = @import("../../src/render/scroll.zig").ScrollController;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "maxScroll returns 0 when content <= viewport" {
    var sc = ScrollController{
        .content_height = 500,
        .viewport_height = 600,
    };
    try expectEqual(@as(f32, 0), sc.maxScroll());

    sc.content_height = 600;
    try expectEqual(@as(f32, 0), sc.maxScroll());
}

test "maxScroll returns difference when content > viewport" {
    var sc = ScrollController{
        .content_height = 1000,
        .viewport_height = 600,
    };
    try expectEqual(@as(f32, 400), sc.maxScroll());
}

test "scrollBy clamps to 0" {
    var sc = ScrollController{
        .content_height = 1000,
        .viewport_height = 600,
    };
    sc.scrollBy(-100);
    try expectEqual(@as(f32, 0), sc.scroll_y);
}

test "scrollBy clamps to maxScroll" {
    var sc = ScrollController{
        .content_height = 1000,
        .viewport_height = 600,
    };
    sc.scrollBy(500);
    try expectEqual(@as(f32, 400), sc.scroll_y);
}

test "scrollBy with sensitivity" {
    var sc = ScrollController{
        .content_height = 1000,
        .viewport_height = 600,
        .scroll_sensitivity = 2.0,
    };
    sc.scrollBy(50);
    try expectEqual(@as(f32, 100), sc.scroll_y);
}

test "setScrollY clamps correctly" {
    var sc = ScrollController{
        .content_height = 1000,
        .viewport_height = 600,
    };
    sc.setScrollY(500);
    try expectEqual(@as(f32, 400), sc.scroll_y);
    try expectEqual(@as(f32, 0), sc.velocity_y);

    sc.setScrollY(-50);
    try expectEqual(@as(f32, 0), sc.scroll_y);
}

test "tick applies momentum and friction" {
    var sc = ScrollController{
        .content_height = 1000,
        .viewport_height = 600,
        .friction = 0.9,
    };
    sc.scrollBy(100); // Sets scroll_y to 100, velocity_y to 100, input_this_frame = true
    sc.tick();
    // After tick:
    // input_this_frame is true, so scroll_y stays 100
    // velocity_y *= 0.9 -> 90
    // input_this_frame becomes false
    try expectEqual(@as(f32, 100), sc.scroll_y);
    try expectEqual(@as(f32, 90), sc.velocity_y);
}

test "tick snaps velocity to 0 below threshold" {
    var sc = ScrollController{
        .content_height = 1000,
        .viewport_height = 600,
        .friction = 0.1,
        .velocity_threshold = 10.0,
    };
    sc.scrollBy(50); // scroll_y = 50, velocity_y = 50, input_this_frame = true
    sc.tick();
    // input_this_frame is true, so scroll_y stays 50
    // velocity_y = 50 * 0.1 = 5.0
    // 5.0 < 10.0 -> velocity_y = 0
    try expectEqual(@as(f32, 50), sc.scroll_y);
    try expectEqual(@as(f32, 0), sc.velocity_y);
}

test "setContentHeight re-clamps scroll_y" {
    var sc = ScrollController{
        .content_height = 1000,
        .viewport_height = 600,
    };
    sc.setScrollY(400);
    try expectEqual(@as(f32, 400), sc.scroll_y);

    sc.setContentHeight(800);
    // maxScroll is now 200
    try expectEqual(@as(f32, 200), sc.scroll_y);
}

test "setViewportHeight re-clamps scroll_y" {
    var sc = ScrollController{
        .content_height = 1000,
        .viewport_height = 600,
    };
    sc.setScrollY(400);
    try expectEqual(@as(f32, 400), sc.scroll_y);

    sc.setViewportHeight(800);
    // maxScroll is now 200
    try expectEqual(@as(f32, 200), sc.scroll_y);
}

test "isScrolling reflects velocity state" {
    var sc = ScrollController{};
    try expect(!sc.isScrolling());
    sc.scrollBy(10);
    try expect(sc.isScrolling());
    sc.tick(); // friction might make it stop if threshold is high, but default is low
    try expect(sc.isScrolling());
    sc.setScrollY(0);
    try expect(!sc.isScrolling());
}

test "scrollBy then tick does not double-apply" {
    var sc = ScrollController{
        .content_height = 1000,
        .viewport_height = 600,
    };
    sc.scrollBy(10);
    try expectEqual(@as(f32, 10), sc.scroll_y);
    sc.tick();
    try expectEqual(@as(f32, 10), sc.scroll_y);
}

test "momentum continues after input frame" {
    var sc = ScrollController{
        .content_height = 1000,
        .viewport_height = 600,
        .friction = 1.0, // No friction for easy math
    };
    sc.scrollBy(10); // scroll_y = 10, velocity_y = 10, input_this_frame = true
    // Simulate a proper 60Hz frame gap so dt_ratio ≈ 1.0 (I-5 frame-rate independence)
    sc.last_tick_ns = std.time.nanoTimestamp() - sc.reference_dt_ns;
    sc.tick(); // input frame: scroll_y stays 10, velocity_y stays 10, input_this_frame = false
    try expectEqual(@as(f32, 10), sc.scroll_y);
    sc.last_tick_ns = std.time.nanoTimestamp() - sc.reference_dt_ns;
    sc.tick(); // momentum frame: scroll_y += 10 -> 20
    try std.testing.expectApproxEqAbs(@as(f32, 20), sc.scroll_y, 0.01);
}
