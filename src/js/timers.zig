const std = @import("std");
const context = @import("context.zig");
const JsContext = context.JsContext;
const JsHandle = context.JsHandle;

pub const Timer = struct {
    id: u32,
    callback: JsHandle,
    fire_at_ms: i64,
    interval_ms: ?i64,
    cancelled: bool,
};

pub const TimerQueue = struct {
    timers: std.ArrayListUnmanaged(Timer),
    next_id: u32,
    js_ctx: *JsContext,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, js_ctx: *JsContext) TimerQueue {
        return .{
            .timers = .{},
            .next_id = 1,
            .js_ctx = js_ctx,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TimerQueue) void {
        for (self.timers.items) |timer| {
            if (!timer.cancelled) {
                self.js_ctx.bridge.value_unprotect(self.js_ctx.ctx, timer.callback);
            }
        }
        self.timers.deinit(self.allocator);
    }

    /// Schedule a one-shot timer. Returns timer ID.
    pub fn setTimeout(self: *TimerQueue, callback: JsHandle, delay_ms: i64, current_time_ms: i64) !u32 {
        const id = self.next_id;
        self.next_id += 1;
        self.js_ctx.bridge.value_protect(self.js_ctx.ctx, callback);
        try self.timers.append(self.allocator, .{
            .id = id,
            .callback = callback,
            .fire_at_ms = current_time_ms + delay_ms,
            .interval_ms = null,
            .cancelled = false,
        });
        return id;
    }

    /// Schedule a repeating timer. Returns timer ID.
    pub fn setInterval(self: *TimerQueue, callback: JsHandle, interval_ms: i64, current_time_ms: i64) !u32 {
        const id = self.next_id;
        self.next_id += 1;
        self.js_ctx.bridge.value_protect(self.js_ctx.ctx, callback);
        try self.timers.append(self.allocator, .{
            .id = id,
            .callback = callback,
            .fire_at_ms = current_time_ms + interval_ms,
            .interval_ms = interval_ms,
            .cancelled = false,
        });
        return id;
    }

    /// Cancel a timer by ID.
    pub fn clearTimer(self: *TimerQueue, timer_id: u32) void {
        for (self.timers.items) |*timer| {
            if (timer.id == timer_id and !timer.cancelled) {
                timer.cancelled = true;
                self.js_ctx.bridge.value_unprotect(self.js_ctx.ctx, timer.callback);
                return;
            }
        }
    }

    /// Process all expired timers. Call from the render loop.
    /// Fires callbacks for expired timers, reschedules intervals, removes one-shots.
    pub fn tick(self: *TimerQueue, current_time_ms: i64) void {
        var i: usize = 0;
        while (i < self.timers.items.len) {
            var timer = &self.timers.items[i];
            if (timer.cancelled) {
                _ = self.timers.orderedRemove(i);
                continue;
            }
            if (current_time_ms >= timer.fire_at_ms) {
                const callback = timer.callback;
                const bridge = self.js_ctx.bridge;
                _ = bridge.call_function(
                    self.js_ctx.ctx,
                    callback,
                    bridge.make_null(self.js_ctx.ctx),
                    0,
                    null,
                );
                if (timer.interval_ms) |interval| {
                    timer.fire_at_ms = current_time_ms + interval;
                    i += 1;
                } else {
                    bridge.value_unprotect(self.js_ctx.ctx, callback);
                    _ = self.timers.orderedRemove(i);
                }
            } else {
                i += 1;
            }
        }
    }

    /// Number of active (non-cancelled) timers.
    pub fn activeCount(self: *const TimerQueue) u32 {
        var count: u32 = 0;
        for (self.timers.items) |timer| {
            if (!timer.cancelled) count += 1;
        }
        return count;
    }
};

// Module-level reference for JS callbacks.
var g_timer_queue: ?*TimerQueue = null;

/// Register global timer functions (setTimeout, clearTimeout,
/// setInterval, clearInterval) on the JS context.
pub fn registerTimerGlobals(js_ctx: *JsContext, timer_queue: *TimerQueue) void {
    g_timer_queue = timer_queue;
    const global = js_ctx.globalObject();
    const bridge = js_ctx.bridge;

    const set_timeout_fn = bridge.make_function(js_ctx.ctx, "setTimeout", @ptrCast(&jsSetTimeout));
    bridge.object_set_property(js_ctx.ctx, global, "setTimeout", set_timeout_fn);

    const clear_timeout_fn = bridge.make_function(js_ctx.ctx, "clearTimeout", @ptrCast(&jsClearTimeout));
    bridge.object_set_property(js_ctx.ctx, global, "clearTimeout", clear_timeout_fn);

    const set_interval_fn = bridge.make_function(js_ctx.ctx, "setInterval", @ptrCast(&jsSetInterval));
    bridge.object_set_property(js_ctx.ctx, global, "setInterval", set_interval_fn);

    const clear_interval_fn = bridge.make_function(js_ctx.ctx, "clearInterval", @ptrCast(&jsClearInterval));
    bridge.object_set_property(js_ctx.ctx, global, "clearInterval", clear_interval_fn);
}

/// Reset module-level state (for tests).
pub fn resetGlobal() void {
    g_timer_queue = null;
}

/// setTimeout(callback, delay) -> timer_id
fn jsSetTimeout(
    ctx: JsHandle,
    _: JsHandle,
    _: JsHandle,
    arg_count: c_int,
    args: ?[*]const JsHandle,
) callconv(.c) JsHandle {
    return scheduleTimer(ctx, arg_count, args, false);
}

/// setInterval(callback, interval) -> timer_id
fn jsSetInterval(
    ctx: JsHandle,
    _: JsHandle,
    _: JsHandle,
    arg_count: c_int,
    args: ?[*]const JsHandle,
) callconv(.c) JsHandle {
    return scheduleTimer(ctx, arg_count, args, true);
}

fn scheduleTimer(ctx: JsHandle, arg_count: c_int, args: ?[*]const JsHandle, is_interval: bool) JsHandle {
    const tq = g_timer_queue orelse return null;
    const bridge = tq.js_ctx.bridge;
    if (arg_count < 1) return bridge.make_undefined(ctx);
    const arg_slice = args orelse return bridge.make_undefined(ctx);

    const callback = arg_slice[0];
    var delay_ms: i64 = 0;
    if (arg_count >= 2) {
        const delay_val = arg_slice[1];
        if (bridge.value_is_number(ctx, delay_val) != 0) {
            delay_ms = @intFromFloat(bridge.value_to_number(ctx, delay_val));
        }
    }

    const current_time = std.time.milliTimestamp();
    const id = if (is_interval)
        tq.setInterval(callback, delay_ms, current_time) catch return bridge.make_undefined(ctx)
    else
        tq.setTimeout(callback, delay_ms, current_time) catch return bridge.make_undefined(ctx);

    return bridge.make_number_value(ctx, @floatFromInt(id));
}

/// clearTimeout(timer_id) / clearInterval(timer_id)
fn jsClearTimeout(
    ctx: JsHandle,
    _: JsHandle,
    _: JsHandle,
    arg_count: c_int,
    args: ?[*]const JsHandle,
) callconv(.c) JsHandle {
    return clearTimerFromJs(ctx, arg_count, args);
}

fn jsClearInterval(
    ctx: JsHandle,
    _: JsHandle,
    _: JsHandle,
    arg_count: c_int,
    args: ?[*]const JsHandle,
) callconv(.c) JsHandle {
    return clearTimerFromJs(ctx, arg_count, args);
}

fn clearTimerFromJs(ctx: JsHandle, arg_count: c_int, args: ?[*]const JsHandle) JsHandle {
    const tq = g_timer_queue orelse return null;
    const bridge = tq.js_ctx.bridge;
    if (arg_count < 1) return bridge.make_undefined(ctx);
    const arg_slice = args orelse return bridge.make_undefined(ctx);

    const id_val = arg_slice[0];
    if (bridge.value_is_number(ctx, id_val) != 0) {
        const id_f = bridge.value_to_number(ctx, id_val);
        const id: u32 = @intFromFloat(id_f);
        tq.clearTimer(id);
    }
    return bridge.make_undefined(ctx);
}
