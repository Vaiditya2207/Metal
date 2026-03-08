const std = @import("std");
const context = @import("context.zig");
const JsHandle = context.JsHandle;
const JsBridge = context.JsBridge;
const node_methods = @import("node_methods.zig");
const node_event_methods = @import("node_event_methods.zig");

/// Method name-to-callback mapping table.
const MethodEntry = struct {
    name: []const u8,
    callback: ?*const anyopaque,
};

const method_table = [_]MethodEntry{
    .{ .name = "appendChild", .callback = @ptrCast(&node_methods.jsAppendChild) },
    .{ .name = "removeChild", .callback = @ptrCast(&node_methods.jsRemoveChild) },
    .{ .name = "setAttribute", .callback = @ptrCast(&node_methods.jsSetAttribute) },
    .{ .name = "getAttribute", .callback = @ptrCast(&node_methods.jsGetAttribute) },
    .{ .name = "removeAttribute", .callback = @ptrCast(&node_methods.jsRemoveAttribute) },
    .{ .name = "hasAttribute", .callback = @ptrCast(&node_methods.jsHasAttribute) },
    .{ .name = "matches", .callback = @ptrCast(&node_methods.jsMatches) },
    .{ .name = "closest", .callback = @ptrCast(&node_methods.jsClosest) },
    .{ .name = "addEventListener", .callback = @ptrCast(&node_event_methods.jsAddEventListener) },
    .{ .name = "removeEventListener", .callback = @ptrCast(&node_event_methods.jsRemoveEventListener) },
};

/// Look up a method name and return a JS function handle for it,
/// or null if the name is not a recognized method.
pub fn getMethodFunction(bridge: *const JsBridge, ctx: JsHandle, prop: []const u8) ?JsHandle {
    for (&method_table) |*entry| {
        if (std.mem.eql(u8, prop, entry.name)) {
            var name_buf: [64]u8 = undefined;
            const name_z = nullTerminate(entry.name, &name_buf) orelse return null;
            return bridge.make_function(ctx, name_z, entry.callback);
        }
    }
    return null;
}

/// Null-terminate a slice into a stack buffer.
fn nullTerminate(src: []const u8, buf: []u8) ?[*:0]const u8 {
    if (src.len >= buf.len) return null;
    @memcpy(buf[0..src.len], src);
    buf[src.len] = 0;
    return buf[0..src.len :0];
}
