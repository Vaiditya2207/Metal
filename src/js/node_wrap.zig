const std = @import("std");
const context = @import("context.zig");
const JsContext = context.JsContext;
const JsHandle = context.JsHandle;
const node_mod = @import("../dom/node.zig");
const Node = node_mod.Node;
const node_props = @import("node_props.zig");

/// Bundles a DOM Node with the registry and JS context needed by property callbacks.
pub const NodeContext = struct {
    node: *Node,
    registry: *NodeRegistry,
    js_ctx: *JsContext,
};

const RegistryEntry = struct {
    handle: JsHandle,
    node_ctx: *NodeContext,
};

/// Maps DOM Node pointers to their JS object handles for identity-preserving wrapping.
pub const NodeRegistry = struct {
    map: std.AutoHashMapUnmanaged(usize, RegistryEntry),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) NodeRegistry {
        return .{ .map = .{}, .allocator = allocator };
    }

    pub fn deinit(self: *NodeRegistry) void {
        var it = self.map.valueIterator();
        while (it.next()) |entry| {
            self.allocator.destroy(entry.node_ctx);
        }
        self.map.deinit(self.allocator);
    }

    pub fn lookup(self: *const NodeRegistry, node: *const Node) ?JsHandle {
        const entry = self.map.get(@intFromPtr(node)) orelse return null;
        return entry.handle;
    }

    pub fn register(self: *NodeRegistry, node: *const Node, js_obj: JsHandle, node_ctx: *NodeContext) !void {
        try self.map.put(self.allocator, @intFromPtr(node), .{ .handle = js_obj, .node_ctx = node_ctx });
    }

    pub fn unregister(self: *NodeRegistry, node: *const Node) void {
        const entry = self.map.get(@intFromPtr(node)) orelse return;
        self.allocator.destroy(entry.node_ctx);
        _ = self.map.remove(@intFromPtr(node));
    }
};

/// Wrap a DOM Node as a JS object. Returns cached object if already wrapped.
pub fn wrapNode(js_ctx: *JsContext, registry: *NodeRegistry, node: *Node) !JsHandle {
    if (registry.lookup(node)) |existing| {
        return existing;
    }
    const node_ctx = try registry.allocator.create(NodeContext);
    errdefer registry.allocator.destroy(node_ctx);
    node_ctx.* = .{ .node = node, .registry = registry, .js_ctx = js_ctx };
    const js_obj = js_ctx.bridge.make_class_instance(
        js_ctx.ctx,
        @ptrCast(node_ctx),
        @ptrCast(&node_props.nodeGetProperty),
        @ptrCast(&node_props.nodeSetProperty),
    );
    if (js_obj == null) return error.JsObjectCreationFailed;
    try registry.register(node, js_obj, node_ctx);
    return js_obj;
}

/// Retrieve the NodeContext from a JS object handle via its private data.
pub fn unwrapNode(js_ctx: *JsContext, js_obj: JsHandle) ?*NodeContext {
    const ptr = js_ctx.bridge.class_get_user_data(js_obj);
    if (ptr == null) return null;
    return @ptrCast(@alignCast(ptr));
}
