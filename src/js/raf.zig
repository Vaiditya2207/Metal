const std = @import("std");
const context = @import("context.zig");
const JsContext = context.JsContext;
const JsHandle = context.JsHandle;

pub const RafEntry = struct {
    id: u32,
    callback: JsHandle,
    cancelled: bool,
};

pub const RafQueue = struct {
    entries: std.ArrayListUnmanaged(RafEntry),
    next_id: u32,
    js_ctx: *JsContext,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, js_ctx: *JsContext) RafQueue {
        return .{
            .entries = .{},
            .next_id = 1,
            .js_ctx = js_ctx,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RafQueue) void {
        for (self.entries.items) |entry| {
            if (!entry.cancelled) {
                self.js_ctx.bridge.value_unprotect(self.js_ctx.ctx, entry.callback);
            }
        }
        self.entries.deinit(self.allocator);
    }

    /// Queue a callback for the next frame. Returns rAF ID.
    pub fn requestAnimationFrame(self: *RafQueue, callback: JsHandle) !u32 {
        const id = self.next_id;
        self.next_id += 1;
        self.js_ctx.bridge.value_protect(self.js_ctx.ctx, callback);
        try self.entries.append(self.allocator, .{
            .id = id,
            .callback = callback,
            .cancelled = false,
        });
        return id;
    }

    /// Cancel a queued animation frame callback.
    pub fn cancelAnimationFrame(self: *RafQueue, raf_id: u32) void {
        for (self.entries.items) |*entry| {
            if (entry.id == raf_id and !entry.cancelled) {
                entry.cancelled = true;
                self.js_ctx.bridge.value_unprotect(self.js_ctx.ctx, entry.callback);
                return;
            }
        }
    }

    /// Fire all queued callbacks with the given timestamp, then clear.
    /// Called once per frame from the render loop.
    pub fn tick(self: *RafQueue, timestamp_ms: f64) void {
        const entries = self.entries.items;
        for (entries) |entry| {
            if (entry.cancelled) continue;
            const bridge = self.js_ctx.bridge;
            const ts_val = bridge.make_number_value(self.js_ctx.ctx, timestamp_ms);
            const args = [_]JsHandle{ts_val};
            _ = bridge.call_function(
                self.js_ctx.ctx,
                entry.callback,
                bridge.make_null(self.js_ctx.ctx),
                1,
                &args,
            );
            bridge.value_unprotect(self.js_ctx.ctx, entry.callback);
        }
        self.entries.clearRetainingCapacity();
    }

    pub fn pendingCount(self: *const RafQueue) u32 {
        var count: u32 = 0;
        for (self.entries.items) |e| {
            if (!e.cancelled) count += 1;
        }
        return count;
    }
};

var g_raf_queue: ?*RafQueue = null;

/// Register requestAnimationFrame and cancelAnimationFrame as globals.
pub fn registerRafGlobals(js_ctx: *JsContext, raf_queue: *RafQueue) void {
    g_raf_queue = raf_queue;
    const global = js_ctx.globalObject();
    const bridge = js_ctx.bridge;

    const raf_fn = bridge.make_function(
        js_ctx.ctx,
        "requestAnimationFrame",
        @ptrCast(&jsRequestAnimationFrame),
    );
    bridge.object_set_property(js_ctx.ctx, global, "requestAnimationFrame", raf_fn);

    const caf_fn = bridge.make_function(
        js_ctx.ctx,
        "cancelAnimationFrame",
        @ptrCast(&jsCancelAnimationFrame),
    );
    bridge.object_set_property(js_ctx.ctx, global, "cancelAnimationFrame", caf_fn);
}

/// Reset module-level state (for tests).
pub fn resetGlobal() void {
    g_raf_queue = null;
}

fn jsRequestAnimationFrame(
    ctx: JsHandle,
    _: JsHandle,
    _: JsHandle,
    arg_count: c_int,
    args: ?[*]const JsHandle,
) callconv(.c) JsHandle {
    const rq = g_raf_queue orelse return null;
    if (arg_count < 1) return rq.js_ctx.bridge.make_undefined(ctx);
    const arg_slice = args orelse return rq.js_ctx.bridge.make_undefined(ctx);
    const callback = arg_slice[0];
    const id = rq.requestAnimationFrame(callback) catch
        return rq.js_ctx.bridge.make_undefined(ctx);
    return rq.js_ctx.bridge.make_number_value(ctx, @floatFromInt(id));
}

fn jsCancelAnimationFrame(
    ctx: JsHandle,
    _: JsHandle,
    _: JsHandle,
    arg_count: c_int,
    args: ?[*]const JsHandle,
) callconv(.c) JsHandle {
    const rq = g_raf_queue orelse return null;
    if (arg_count < 1) return rq.js_ctx.bridge.make_undefined(ctx);
    const arg_slice = args orelse return rq.js_ctx.bridge.make_undefined(ctx);
    if (rq.js_ctx.bridge.value_is_number(ctx, arg_slice[0]) != 0) {
        const id: u32 = @intFromFloat(
            rq.js_ctx.bridge.value_to_number(ctx, arg_slice[0]),
        );
        rq.cancelAnimationFrame(id);
    }
    return rq.js_ctx.bridge.make_undefined(ctx);
}
