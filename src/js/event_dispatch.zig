const std = @import("std");
const context = @import("context.zig");
const JsContext = context.JsContext;
const JsHandle = context.JsHandle;
const CallbackRegistry = @import("callback_registry.zig").CallbackRegistry;
const node_mod = @import("../dom/node.zig");
const Node = node_mod.Node;
const node_wrap = @import("node_wrap.zig");
const NodeRegistry = node_wrap.NodeRegistry;

/// Result of dispatching an event.
pub const DispatchResult = struct {
    default_prevented: bool,
};

/// Creates JS event objects and dispatches them through the DOM tree
/// with a bubble phase.
pub const EventDispatcher = struct {
    js_ctx: *JsContext,
    callback_registry: *CallbackRegistry,
    node_registry: *NodeRegistry,

    pub fn init(
        js_ctx: *JsContext,
        callback_registry: *CallbackRegistry,
        node_registry: *NodeRegistry,
    ) EventDispatcher {
        return .{
            .js_ctx = js_ctx,
            .callback_registry = callback_registry,
            .node_registry = node_registry,
        };
    }

    /// Create a JS event object with type, target, bubbles, defaultPrevented,
    /// _stopped, and stopPropagation fields.
    pub fn createEvent(self: *EventDispatcher, event_type: []const u8, target: *Node) JsHandle {
        const bridge = self.js_ctx.bridge;
        const ctx = self.js_ctx.ctx;
        const event_obj = bridge.make_object(ctx);

        var type_buf: [128]u8 = undefined;
        const type_z = nullTerminate(event_type, &type_buf) orelse return event_obj;
        bridge.object_set_property(ctx, event_obj, "type", bridge.make_string_value(ctx, type_z));

        const target_js = node_wrap.wrapNode(self.js_ctx, self.node_registry, target) catch
            bridge.make_null(ctx);
        bridge.object_set_property(ctx, event_obj, "target", target_js);
        bridge.object_set_property(ctx, event_obj, "bubbles", bridge.make_number_value(ctx, 1.0));
        bridge.object_set_property(ctx, event_obj, "defaultPrevented", bridge.make_number_value(ctx, 0.0));
        bridge.object_set_property(ctx, event_obj, "_stopped", bridge.make_number_value(ctx, 0.0));
        bridge.object_set_property(ctx, event_obj, "stopPropagation", bridge.make_function(ctx, "stopPropagation", @ptrCast(&jsStopPropagation)));

        return event_obj;
    }

    /// Dispatch an event on a node. Fires listeners on the target, then bubbles
    /// up through ancestor nodes. Returns whether default was prevented.
    pub fn dispatchEvent(self: *EventDispatcher, target: *Node, event_type: []const u8) DispatchResult {
        const event_obj = self.createEvent(event_type, target);

        self.fireListeners(target, event_type, event_obj);

        if (!self.isPropagationStopped(event_obj)) {
            var current: ?*Node = target.parent;
            while (current) |ancestor| {
                self.fireListeners(ancestor, event_type, event_obj);
                if (self.isPropagationStopped(event_obj)) break;
                current = ancestor.parent;
            }
        }

        const prevented_val = self.js_ctx.bridge.object_get_property(
            self.js_ctx.ctx,
            event_obj,
            "defaultPrevented",
        );
        const is_prevented = if (self.js_ctx.bridge.value_is_number(self.js_ctx.ctx, prevented_val) != 0)
            self.js_ctx.bridge.value_to_number(self.js_ctx.ctx, prevented_val) != 0.0
        else
            false;

        return .{ .default_prevented = is_prevented };
    }

    /// Check whether propagation has been stopped on the event object.
    fn isPropagationStopped(self: *EventDispatcher, event_obj: JsHandle) bool {
        const stopped_val = self.js_ctx.bridge.object_get_property(
            self.js_ctx.ctx,
            event_obj,
            "_stopped",
        );
        if (self.js_ctx.bridge.value_is_number(self.js_ctx.ctx, stopped_val) != 0) {
            return self.js_ctx.bridge.value_to_number(self.js_ctx.ctx, stopped_val) != 0.0;
        }
        return false;
    }

    /// Fire all listeners registered on a node for the given event type.
    fn fireListeners(self: *EventDispatcher, node: *Node, event_type: []const u8, event_obj: JsHandle) void {
        for (node.event_target.listeners.items) |listener| {
            if (!std.mem.eql(u8, listener.event_type, event_type)) continue;
            const callback = self.callback_registry.get(listener.callback_id) orelse continue;
            _ = self.callJsFunction(callback, event_obj);
        }
    }

    /// Call a JS function with a single argument (the event object).
    fn callJsFunction(self: *EventDispatcher, callback: JsHandle, event_obj: JsHandle) JsHandle {
        const args = [_]JsHandle{event_obj};
        return self.js_ctx.bridge.call_function(
            self.js_ctx.ctx,
            callback,
            self.js_ctx.bridge.make_null(self.js_ctx.ctx),
            1,
            &args,
        );
    }
};

/// Null-terminate a slice into a stack buffer.
fn nullTerminate(src: []const u8, buf: []u8) ?[*:0]const u8 {
    if (src.len >= buf.len) return null;
    @memcpy(buf[0..src.len], src);
    buf[src.len] = 0;
    return buf[0..src.len :0];
}

/// C-callable: event.stopPropagation()
/// Sets this._stopped = 1 on the event object.
fn jsStopPropagation(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    _: c_int,
    _: ?*const JsHandle,
) callconv(.c) ?*anyopaque {
    if (g_bridge) |bridge| {
        bridge.object_set_property(ctx, this_obj, "_stopped", bridge.make_number_value(ctx, 1.0));
        return bridge.make_undefined(ctx);
    }
    return null;
}

/// Module-level bridge reference for the stopPropagation callback.
var g_bridge: ?*const context.JsBridge = null;

/// Set the module-level bridge reference. Call before dispatching events.
pub fn setBridge(bridge: *const context.JsBridge) void {
    g_bridge = bridge;
}

/// Reset module-level state (for tests).
pub fn resetBridge() void {
    g_bridge = null;
}
