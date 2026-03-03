const std = @import("std");
const context_mod = @import("context.zig");

/// Append a single log message to the context's log buffer and print to stderr.
pub fn handleLogMessage(js_ctx: *context_mod.JsContext, message: []const u8) !void {
    try js_ctx.appendLog(message);
    std.debug.print("[JS] {s}\n", .{message});
}

/// Register a `console` object with a `log` method on the JS global object.
/// Uses the bridge vtable from the context; the actual callback is stored as
/// private data on the JSC function object and invoked by the C trampoline.
pub fn bindConsole(js_ctx: *context_mod.JsContext, callback: ?*const anyopaque) void {
    const bridge = js_ctx.bridge;
    const ctx = js_ctx.ctx;
    const global = bridge.global_object(ctx);
    const console_obj = bridge.make_object(ctx);
    const log_fn = bridge.make_function(ctx, "log", callback);
    bridge.object_set_property(ctx, console_obj, "log", log_fn);
    bridge.object_set_property(ctx, global, "console", console_obj);
}
