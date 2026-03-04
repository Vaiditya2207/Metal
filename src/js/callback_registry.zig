const std = @import("std");
const context = @import("context.zig");
const JsContext = context.JsContext;
const JsHandle = context.JsHandle;

/// Stores JS function handles protected from garbage collection.
/// Each registered callback gets a unique u64 id used to reference it
/// from the DOM EventTarget listener storage.
pub const CallbackRegistry = struct {
    callbacks: std.AutoHashMapUnmanaged(u64, JsHandle),
    next_id: u64,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CallbackRegistry {
        return .{
            .callbacks = .{},
            .next_id = 1,
            .allocator = allocator,
        };
    }

    /// Release all remaining callbacks and free internal storage.
    pub fn deinit(self: *CallbackRegistry, js_ctx: *JsContext) void {
        var it = self.callbacks.valueIterator();
        while (it.next()) |handle_ptr| {
            js_ctx.bridge.value_unprotect(js_ctx.ctx, handle_ptr.*);
        }
        self.callbacks.deinit(self.allocator);
    }

    /// Register a JS function handle. Protects it from GC.
    /// Returns a unique callback_id.
    pub fn register(self: *CallbackRegistry, js_ctx: *JsContext, js_function: JsHandle) !u64 {
        const id = self.next_id;
        self.next_id += 1;
        js_ctx.bridge.value_protect(js_ctx.ctx, js_function);
        try self.callbacks.put(self.allocator, id, js_function);
        return id;
    }

    /// Remove a callback by id. Unprotects the JS handle for GC.
    pub fn unregister(self: *CallbackRegistry, js_ctx: *JsContext, callback_id: u64) void {
        if (self.callbacks.fetchRemove(callback_id)) |entry| {
            js_ctx.bridge.value_unprotect(js_ctx.ctx, entry.value);
        }
    }

    /// Look up a callback handle by id.
    pub fn get(self: *const CallbackRegistry, callback_id: u64) ?JsHandle {
        return self.callbacks.get(callback_id);
    }

    /// Find the callback_id for a given JS handle (reverse lookup).
    /// Returns null if no matching handle is registered.
    pub fn findIdByHandle(self: *const CallbackRegistry, handle: JsHandle) ?u64 {
        var it = self.callbacks.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* == handle) return entry.key_ptr.*;
        }
        return null;
    }

    /// Number of registered callbacks.
    pub fn count(self: *const CallbackRegistry) u32 {
        return self.callbacks.count();
    }
};
