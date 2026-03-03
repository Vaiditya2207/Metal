const std = @import("std");

pub const ScrollController = struct {
    scroll_y: f32 = 0,
    content_height: f32 = 0,
    viewport_height: f32 = 0,
    velocity_y: f32 = 0,

    // Configurable physics
    friction: f32 = 0.95, // Velocity multiplier per tick (0.0 = instant stop, 1.0 = no friction)
    velocity_threshold: f32 = 0.5, // Below this, snap velocity to 0
    scroll_sensitivity: f32 = 1.0, // Multiplier on input delta
    input_this_frame: bool = false,

    pub fn maxScroll(self: *const ScrollController) f32 {
        const diff = self.content_height - self.viewport_height;
        if (diff < 0) return 0;
        return diff;
    }

    pub fn scrollBy(self: *ScrollController, delta_y: f32) void {
        const input = delta_y * self.scroll_sensitivity;
        self.scroll_y += input;
        self.velocity_y = input;
        self.input_this_frame = true;
        self.clamp();
    }

    pub fn setScrollY(self: *ScrollController, y: f32) void {
        self.scroll_y = y;
        self.velocity_y = 0;
        self.clamp();
    }

    pub fn tick(self: *ScrollController) void {
        if (!self.input_this_frame) {
            self.scroll_y += self.velocity_y;
        }
        self.velocity_y *= self.friction;

        if (@abs(self.velocity_y) < self.velocity_threshold) {
            self.velocity_y = 0;
        }

        self.input_this_frame = false;
        self.clamp();
    }

    pub fn setContentHeight(self: *ScrollController, height: f32) void {
        self.content_height = height;
        self.clamp();
    }

    pub fn setViewportHeight(self: *ScrollController, height: f32) void {
        self.viewport_height = height;
        self.clamp();
    }

    pub fn isScrolling(self: *const ScrollController) bool {
        return self.velocity_y != 0;
    }

    fn clamp(self: *ScrollController) void {
        const max = self.maxScroll();
        if (self.scroll_y < 0) {
            self.scroll_y = 0;
        } else if (self.scroll_y > max) {
            self.scroll_y = max;
        }
    }
};
