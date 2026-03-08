const std = @import("std");

/// Opaque handle to a JSC value, object, context, or string.
pub const JsHandle = ?*anyopaque;

/// Function-pointer types for the C bridge vtable.
pub const EvalFn = *const fn (JsHandle, [*]const u8, c_int) JsHandle;
pub const VoidHandleFn = *const fn (JsHandle) void;
pub const HandleFn = *const fn (JsHandle) JsHandle;
pub const SetPropFn = *const fn (JsHandle, JsHandle, [*:0]const u8, JsHandle) void;
pub const MakeFnFn = *const fn (JsHandle, [*:0]const u8, ?*const anyopaque) JsHandle;
pub const MakeStrValFn = *const fn (JsHandle, [*:0]const u8) JsHandle;
pub const ValueToStringFn = *const fn (JsHandle, JsHandle) JsHandle;
pub const StringGetUtf8Fn = *const fn (JsHandle, [*]u8, c_int) c_int;
pub const ValueIsStringFn = *const fn (JsHandle, JsHandle) c_int;
pub const GetExceptionFn = *const fn (JsHandle) JsHandle;
pub const ClearExceptionFn = *const fn (JsHandle) void;

/// Vtable of C bridge functions.  Wired by main.zig (real JSC) or by tests (mocks).
pub const JsBridge = struct {
    context_create: *const fn () JsHandle,
    context_release: VoidHandleFn,
    evaluate_script: EvalFn,
    global_object: HandleFn,
    make_object: HandleFn,
    object_set_property: SetPropFn,
    make_function: MakeFnFn,
    make_string_value: MakeStrValFn,
    make_undefined: HandleFn,
    value_to_string: ValueToStringFn,
    string_get_utf8: StringGetUtf8Fn,
    string_release: VoidHandleFn,
    value_is_string: ValueIsStringFn,
    value_protect: *const fn (JsHandle, JsHandle) void,
    value_unprotect: *const fn (JsHandle, JsHandle) void,
    make_class_instance: *const fn (JsHandle, ?*anyopaque, ?*const anyopaque, ?*const anyopaque) JsHandle,
    object_get_private: *const fn (JsHandle) ?*anyopaque,
    object_get_property: *const fn (JsHandle, JsHandle, [*:0]const u8) JsHandle,
    make_number_value: *const fn (JsHandle, f64) JsHandle,
    value_to_number: *const fn (JsHandle, JsHandle) f64,
    value_is_number: *const fn (JsHandle, JsHandle) c_int,
    make_null: *const fn (JsHandle) JsHandle,
    call_function: *const fn (JsHandle, JsHandle, JsHandle, c_int, ?[*]const JsHandle) JsHandle,
    class_get_user_data: *const fn (JsHandle) ?*anyopaque,
    has_exception: *const fn (JsHandle) c_int,
    get_exception: ?GetExceptionFn = null,
    clear_exception: ?ClearExceptionFn = null,
};

pub const JsContext = struct {
    ctx: JsHandle,
    bridge: *const JsBridge,
    allocator: std.mem.Allocator,
    log_buffer: std.ArrayListUnmanaged(u8),

    pub fn init(allocator: std.mem.Allocator, bridge: *const JsBridge) !JsContext {
        const ctx = bridge.context_create();
        if (ctx == null) return error.JsContextCreationFailed;
        return JsContext{
            .ctx = ctx,
            .bridge = bridge,
            .allocator = allocator,
            .log_buffer = .empty,
        };
    }

    pub fn deinit(self: *JsContext) void {
        self.log_buffer.deinit(self.allocator);
        self.bridge.context_release(self.ctx);
        self.ctx = null;
    }

    pub fn evaluateScript(self: *JsContext, script: []const u8) JsHandle {
        return self.bridge.evaluate_script(self.ctx, script.ptr, @intCast(script.len));
    }

    pub fn globalObject(self: *JsContext) JsHandle {
        return self.bridge.global_object(self.ctx);
    }

    pub fn appendLog(self: *JsContext, msg: []const u8) !void {
        try self.log_buffer.appendSlice(self.allocator, msg);
        try self.log_buffer.append(self.allocator, '\n');
    }

    pub fn getLogOutput(self: *const JsContext) []const u8 {
        return self.log_buffer.items;
    }

    pub fn hasException(self: *JsContext) bool {
        return self.bridge.has_exception(self.ctx) != 0;
    }

    pub fn clearException(self: *JsContext) void {
        if (self.bridge.clear_exception) |clear_ex| {
            clear_ex(self.ctx);
            return;
        }
        _ = self.bridge.evaluate_script(self.ctx, "".ptr, 0);
    }

    pub fn readExceptionString(self: *JsContext, buf: []u8) ?[]const u8 {
        const get_ex = self.bridge.get_exception orelse return null;
        const ex = get_ex(self.ctx);
        if (ex == null) return null;

        const ex_str = self.bridge.value_to_string(self.ctx, ex);
        if (ex_str == null) return null;
        defer self.bridge.string_release(ex_str);

        const len = self.bridge.string_get_utf8(ex_str, buf.ptr, @intCast(buf.len));
        if (len <= 1) return null;
        return buf[0..@as(usize, @intCast(len - 1))];
    }
};
