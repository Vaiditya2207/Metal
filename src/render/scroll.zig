const std = @import("std");

pub const ScrollController = struct {
    scroll_y: f32 = 0,
    content_height: f32 = 0,
    viewport_height: f32 = 0,
    velocity_y: f32 = 0,

    // Configurable physics
    friction: f32 = 0.95, // Velocity multiplier per tick at reference rate
    velocity_threshold: f32 = 0.5, // Below this, snap velocity to 0
    scroll_sensitivity: f32 = 1.0, // Multiplier on input delta
    input_this_frame: bool = false,

    // Frame-rate-independent timing (I-5 FIX)
    last_tick_ns: i128 = 0,
    reference_dt_ns: i128 = 16_666_667, // ~60Hz reference frame time in nanoseconds

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
        const now_ns = std.time.nanoTimestamp();

        // I-5 FIX: Frame-rate-independent friction using delta time.
        // friction^(dt / reference_dt) ensures identical deceleration
        // regardless of whether tick() is called at 60Hz or 120Hz.
        var dt_ratio: f32 = 1.0;
        if (self.last_tick_ns != 0) {
            const elapsed_ns = now_ns - self.last_tick_ns;
            if (elapsed_ns > 0 and elapsed_ns < 200_000_000) { // Cap at 200ms to avoid jumps
                dt_ratio = @as(f32, @floatFromInt(elapsed_ns)) / @as(f32, @floatFromInt(self.reference_dt_ns));
            }
        }
        self.last_tick_ns = now_ns;

        if (!self.input_this_frame) {
            // Scale velocity application by dt_ratio for consistent distance
            self.scroll_y += self.velocity_y * dt_ratio;
        }
        // Apply friction scaled by dt_ratio: friction^(dt/reference_dt)
        self.velocity_y *= std.math.pow(f32, self.friction, dt_ratio);

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
