const std = @import("std");
const context_mod = @import("context.zig");

/// Append a single log message to the context's log buffer and print to stderr.
pub fn handleLogMessage(js_ctx: *context_mod.JsContext, message: []const u8) !void {
    try js_ctx.appendLog(message);
    std.debug.print("[JS] {s}\n", .{message});
}

/// Append a warning message to the context's log buffer and print to stderr.
pub fn handleWarnMessage(js_ctx: *context_mod.JsContext, message: []const u8) !void {
    try js_ctx.appendLog(message);
    std.debug.print("[JS WARN] {s}\n", .{message});
}

/// Append an error message to the context's log buffer and print to stderr.
pub fn handleErrorMessage(js_ctx: *context_mod.JsContext, message: []const u8) !void {
    try js_ctx.appendLog(message);
    std.debug.print("[JS ERROR] {s}\n", .{message});
}

/// Register a `console` object with log, warn, and error methods on the
/// JS global object. Each callback is stored as private data on the
/// corresponding JSC function object and invoked by the C trampoline.
pub fn bindConsole(
    js_ctx: *context_mod.JsContext,
    log_cb: ?*const anyopaque,
    warn_cb: ?*const anyopaque,
    error_cb: ?*const anyopaque,
) void {
    const bridge = js_ctx.bridge;
    const ctx = js_ctx.ctx;
    const global = bridge.global_object(ctx);
    const console_obj = bridge.make_object(ctx);
    const log_fn = bridge.make_function(ctx, "log", log_cb);
    bridge.object_set_property(ctx, console_obj, "log", log_fn);
    const warn_fn = bridge.make_function(ctx, "warn", warn_cb);
    bridge.object_set_property(ctx, console_obj, "warn", warn_fn);
    const error_fn = bridge.make_function(ctx, "error", error_cb);
    bridge.object_set_property(ctx, console_obj, "error", error_fn);
    bridge.object_set_property(ctx, global, "console", console_obj);
}
