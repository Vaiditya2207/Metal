const std = @import("std");
const node_wrap = @import("../../src/js/node_wrap.zig");
const context_mod = @import("../../src/js/context.zig");
const dom = @import("../../src/dom/mod.zig");

// --- Mock bridge ----------------------------------------------------------------

const sentinel: *anyopaque = @ptrFromInt(0xDEAD);
var class_instance_counter: usize = 0;

fn mockCreate() ?*anyopaque {
    return sentinel;
}
fn mockRelease(_: ?*anyopaque) void {}
fn mockEval(_: ?*anyopaque, _: [*]const u8, _: c_int) ?*anyopaque {
    return sentinel;
}
fn mockGlobal(_: ?*anyopaque) ?*anyopaque {
    return sentinel;
}
fn mockMakeObj(_: ?*anyopaque) ?*anyopaque {
    return sentinel;
}
fn mockSetProp(_: ?*anyopaque, _: ?*anyopaque, _: [*:0]const u8, _: ?*anyopaque) void {}
fn mockMakeFn(_: ?*anyopaque, _: [*:0]const u8, _: ?*const anyopaque) ?*anyopaque {
    return sentinel;
}
fn mockMakeStr(_: ?*anyopaque, _: [*:0]const u8) ?*anyopaque {
    return sentinel;
}
fn mockMakeUndef(_: ?*anyopaque) ?*anyopaque {
    return sentinel;
}
fn mockValToStr(_: ?*anyopaque, _: ?*anyopaque) ?*anyopaque {
    return sentinel;
}
fn mockStrGetUtf8(_: ?*anyopaque, _: [*]u8, _: c_int) c_int {
    return 0;
}
fn mockStrRelease(_: ?*anyopaque) void {}
fn mockValIsStr(_: ?*anyopaque, _: ?*anyopaque) c_int {
    return 0;
}
fn mockValueProtect(_: ?*anyopaque, _: ?*anyopaque) void {}
fn mockValueUnprotect(_: ?*anyopaque, _: ?*anyopaque) void {}

fn mockMakeClassInstance(_: ?*anyopaque, _: ?*anyopaque, _: ?*const anyopaque, _: ?*const anyopaque) ?*anyopaque {
    class_instance_counter += 1;
    return @ptrFromInt(0xC000 + class_instance_counter);
}

fn mockMakeClassInstanceNull(_: ?*anyopaque, _: ?*anyopaque, _: ?*const anyopaque, _: ?*const anyopaque) ?*anyopaque {
    return null;
}

var stored_private: ?*anyopaque = null;

fn mockObjectGetPrivate(obj: ?*anyopaque) ?*anyopaque {
    _ = obj;
    return stored_private;
}

fn mockObjectGetPrivateNull(_: ?*anyopaque) ?*anyopaque {
    return null;
}

fn mockObjectGetProperty(_: ?*anyopaque, _: ?*anyopaque, _: [*:0]const u8) ?*anyopaque {
    return @ptrFromInt(0xBEEF);
}
fn mockMakeNumberValue(_: ?*anyopaque, _: f64) ?*anyopaque {
    return @ptrFromInt(0xBEEF);
}
fn mockValueToNumber(_: ?*anyopaque, _: ?*anyopaque) f64 {
    return 0.0;
}
fn mockValueIsNumber(_: ?*anyopaque, _: ?*anyopaque) c_int {
    return 0;
}
fn mockMakeNull(_: ?*anyopaque) ?*anyopaque {
    return @ptrFromInt(0xBEEF);
}
fn mockCallFunction(_: ?*anyopaque, _: ?*anyopaque, _: ?*anyopaque, _: c_int, _: ?[*]const ?*anyopaque) ?*anyopaque {
    return @ptrFromInt(0xBEEF);
}
fn mockClassGetUserData(_: ?*anyopaque) ?*anyopaque {
    return stored_private;
}
fn mockClassGetUserDataNull(_: ?*anyopaque) ?*anyopaque {
    return null;
}
fn mockHasException(_: ?*anyopaque) c_int {
    return 0;
}

const mock_bridge = context_mod.JsBridge{
    .context_create = mockCreate,
    .context_release = mockRelease,
    .evaluate_script = mockEval,
    .global_object = mockGlobal,
    .make_object = mockMakeObj,
    .object_set_property = mockSetProp,
    .make_function = mockMakeFn,
    .make_string_value = mockMakeStr,
    .make_undefined = mockMakeUndef,
    .value_to_string = mockValToStr,
    .string_get_utf8 = mockStrGetUtf8,
    .string_release = mockStrRelease,
    .value_is_string = mockValIsStr,
    .value_protect = &mockValueProtect,
    .value_unprotect = &mockValueUnprotect,
    .make_class_instance = &mockMakeClassInstance,
    .object_get_private = &mockObjectGetPrivate,
    .object_get_property = &mockObjectGetProperty,
    .make_number_value = &mockMakeNumberValue,
    .value_to_number = &mockValueToNumber,
    .value_is_number = &mockValueIsNumber,
    .make_null = &mockMakeNull,
    .call_function = &mockCallFunction,
    .class_get_user_data = &mockClassGetUserData,
    .has_exception = &mockHasException,
};

// --- NodeRegistry tests ---------------------------------------------------------

test "NodeRegistry init and deinit" {
    var reg = node_wrap.NodeRegistry.init(std.testing.allocator);
    defer reg.deinit();
    const dummy_node = @as(*const dom.Node, @ptrFromInt(0x1000));
    try std.testing.expect(reg.lookup(dummy_node) == null);
}

test "NodeRegistry register and lookup" {
    var reg = node_wrap.NodeRegistry.init(std.testing.allocator);
    defer reg.deinit();
    const dummy_node = @as(*const dom.Node, @ptrFromInt(0x2000));
    const fake_handle: context_mod.JsHandle = @ptrFromInt(0xABCD);
    const node_ctx = try reg.allocator.create(node_wrap.NodeContext);
    node_ctx.* = .{ .node = @constCast(dummy_node), .registry = &reg, .js_ctx = undefined };
    try reg.register(dummy_node, fake_handle, node_ctx);
    const result = reg.lookup(dummy_node);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(fake_handle, result.?);
}

test "NodeRegistry unregister removes entry" {
    var reg = node_wrap.NodeRegistry.init(std.testing.allocator);
    defer reg.deinit();
    const dummy_node = @as(*const dom.Node, @ptrFromInt(0x3000));
    const fake_handle: context_mod.JsHandle = @ptrFromInt(0xABCE);
    const node_ctx = try reg.allocator.create(node_wrap.NodeContext);
    node_ctx.* = .{ .node = @constCast(dummy_node), .registry = &reg, .js_ctx = undefined };
    try reg.register(dummy_node, fake_handle, node_ctx);
    reg.unregister(dummy_node);
    try std.testing.expect(reg.lookup(dummy_node) == null);
}

test "NodeRegistry lookup returns null for unregistered node" {
    var reg = node_wrap.NodeRegistry.init(std.testing.allocator);
    defer reg.deinit();
    const a = @as(*const dom.Node, @ptrFromInt(0x4000));
    const b = @as(*const dom.Node, @ptrFromInt(0x5000));
    const handle: context_mod.JsHandle = @ptrFromInt(0xABCF);
    const node_ctx = try reg.allocator.create(node_wrap.NodeContext);
    node_ctx.* = .{ .node = @constCast(a), .registry = &reg, .js_ctx = undefined };
    try reg.register(a, handle, node_ctx);
    try std.testing.expect(reg.lookup(b) == null);
}

test "wrapNode returns cached handle on second call" {
    const alloc = std.testing.allocator;
    class_instance_counter = 0;
    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    var reg = node_wrap.NodeRegistry.init(alloc);
    defer reg.deinit();

    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const elem = try doc.createElement("div");

    const handle1 = try node_wrap.wrapNode(&js_ctx, &reg, elem);
    const handle2 = try node_wrap.wrapNode(&js_ctx, &reg, elem);
    try std.testing.expectEqual(handle1, handle2);
    try std.testing.expectEqual(@as(usize, 1), class_instance_counter);
}

test "wrapNode creates distinct handles for different nodes" {
    const alloc = std.testing.allocator;
    class_instance_counter = 0;
    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    var reg = node_wrap.NodeRegistry.init(alloc);
    defer reg.deinit();

    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const elem1 = try doc.createElement("div");
    const elem2 = try doc.createElement("span");

    const h1 = try node_wrap.wrapNode(&js_ctx, &reg, elem1);
    const h2 = try node_wrap.wrapNode(&js_ctx, &reg, elem2);
    try std.testing.expect(h1 != h2);
    try std.testing.expectEqual(@as(usize, 2), class_instance_counter);
}

test "wrapNode returns error when bridge returns null" {
    const alloc = std.testing.allocator;
    var null_bridge = mock_bridge;
    null_bridge.make_class_instance = &mockMakeClassInstanceNull;
    var js_ctx = try context_mod.JsContext.init(alloc, &null_bridge);
    defer js_ctx.deinit();
    var reg = node_wrap.NodeRegistry.init(alloc);
    defer reg.deinit();

    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const elem = try doc.createElement("div");

    const result = node_wrap.wrapNode(&js_ctx, &reg, elem);
    try std.testing.expectError(error.JsObjectCreationFailed, result);
}

test "unwrapNode returns null for null private data" {
    const alloc = std.testing.allocator;
    var null_priv_bridge = mock_bridge;
    null_priv_bridge.class_get_user_data = &mockClassGetUserDataNull;
    var js_ctx = try context_mod.JsContext.init(alloc, &null_priv_bridge);
    defer js_ctx.deinit();
    const fake_obj: context_mod.JsHandle = @ptrFromInt(0xF00D);
    const result = node_wrap.unwrapNode(&js_ctx, fake_obj);
    try std.testing.expect(result == null);
}

test "unwrapNode returns node context when private data is set" {
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const elem = try doc.createElement("p");

    var node_ctx = node_wrap.NodeContext{
        .node = elem,
        .registry = undefined,
        .js_ctx = undefined,
    };
    stored_private = @ptrCast(&node_ctx);
    defer {
        stored_private = null;
    }

    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    const result = node_wrap.unwrapNode(&js_ctx, @ptrFromInt(0xF00E));
    try std.testing.expect(result != null);
    try std.testing.expectEqual(elem, result.?.node);
}

test "unregister frees NodeContext allocation" {
    const alloc = std.testing.allocator;
    class_instance_counter = 0;
    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    var reg = node_wrap.NodeRegistry.init(alloc);
    defer reg.deinit();

    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const elem = try doc.createElement("div");

    const handle = try node_wrap.wrapNode(&js_ctx, &reg, elem);
    try std.testing.expect(handle != null);
    reg.unregister(elem);
    try std.testing.expect(reg.lookup(elem) == null);
}
