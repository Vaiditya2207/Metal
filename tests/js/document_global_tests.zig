const std = @import("std");
const document_global = @import("../../src/js/document_global.zig");
const node_wrap = @import("../../src/js/node_wrap.zig");
const context_mod = @import("../../src/js/context.zig");
const dom = @import("../../src/dom/mod.zig");

// --- Mock bridge ----------------------------------------------------------------

const sentinel: *anyopaque = @ptrFromInt(0xDEAD);
var class_instance_counter: usize = 0;
var set_prop_log: [32]SetPropEntry = undefined;
var set_prop_count: usize = 0;
var mock_str_content: []const u8 = "default";
var last_string_made: ?[*:0]const u8 = null;
var last_null_returned: bool = false;

const SetPropEntry = struct {
    obj: ?*anyopaque,
    name: [64]u8,
    name_len: usize,
};

fn mockCreate() ?*anyopaque {
    return sentinel;
}
fn mockRelease(_: ?*anyopaque) void {}
fn mockEval(_: ?*anyopaque, _: [*]const u8, _: c_int) ?*anyopaque {
    return sentinel;
}
fn mockGlobal(_: ?*anyopaque) ?*anyopaque {
    return @ptrFromInt(0xA100);
}

var make_obj_counter: usize = 0;

fn mockMakeObj(_: ?*anyopaque) ?*anyopaque {
    make_obj_counter += 1;
    return @ptrFromInt(0xD000 + make_obj_counter);
}

fn mockSetProp(_: ?*anyopaque, obj: ?*anyopaque, name: [*:0]const u8, _: ?*anyopaque) void {
    if (set_prop_count < set_prop_log.len) {
        var entry = &set_prop_log[set_prop_count];
        entry.obj = obj;
        const span = std.mem.span(name);
        const copy_len = @min(span.len, entry.name.len);
        @memcpy(entry.name[0..copy_len], span[0..copy_len]);
        entry.name_len = copy_len;
        set_prop_count += 1;
    }
}

var make_fn_counter: usize = 0;

fn mockMakeFn(_: ?*anyopaque, _: [*:0]const u8, _: ?*const anyopaque) ?*anyopaque {
    make_fn_counter += 1;
    return @ptrFromInt(0xF000 + make_fn_counter);
}

fn mockMakeStr(_: ?*anyopaque, name: [*:0]const u8) ?*anyopaque {
    last_string_made = name;
    return @ptrFromInt(0xA000);
}

fn mockMakeUndef(_: ?*anyopaque) ?*anyopaque {
    return sentinel;
}

fn mockValToStr(_: ?*anyopaque, _: ?*anyopaque) ?*anyopaque {
    return @ptrFromInt(0xE000);
}

fn mockStrGetUtf8(_: ?*anyopaque, buf: [*]u8, max_len: c_int) c_int {
    const src = mock_str_content;
    const copy_len = @min(src.len, @as(usize, @intCast(max_len)) -| 1);
    for (src[0..copy_len], 0..) |c, i| {
        buf[i] = c;
    }
    buf[copy_len] = 0;
    return @intCast(copy_len + 1);
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

fn mockObjectGetPrivate(obj: ?*anyopaque) ?*anyopaque {
    return obj;
}

fn mockObjectGetProperty(_: ?*anyopaque, _: ?*anyopaque, _: [*:0]const u8) ?*anyopaque {
    return @ptrFromInt(0xBEEF);
}
fn mockMakeNumberValue(_: ?*anyopaque, _: f64) ?*anyopaque {
    return @ptrFromInt(0xB000);
}
fn mockValueToNumber(_: ?*anyopaque, _: ?*anyopaque) f64 {
    return 0.0;
}
fn mockValueIsNumber(_: ?*anyopaque, _: ?*anyopaque) c_int {
    return 0;
}
fn mockMakeNull(_: ?*anyopaque) ?*anyopaque {
    last_null_returned = true;
    return @ptrFromInt(0xD000);
}
fn mockCallFunction(_: ?*anyopaque, _: ?*anyopaque, _: ?*anyopaque, _: c_int, _: ?[*]const ?*anyopaque) ?*anyopaque {
    return @ptrFromInt(0xBEEF);
}
fn mockClassGetUserData(_: ?*anyopaque) ?*anyopaque {
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

fn resetState() void {
    set_prop_count = 0;
    make_obj_counter = 0;
    make_fn_counter = 0;
    class_instance_counter = 0;
    mock_str_content = "default";
    last_string_made = null;
    last_null_returned = false;
    document_global.resetBinding();
}

fn getPropName(entry: *const SetPropEntry) []const u8 {
    return entry.name[0..entry.name_len];
}

// --- Tests ----------------------------------------------------------------------

test "registerDocument sets document property on global object" {
    resetState();
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();

    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    var reg = node_wrap.NodeRegistry.init(alloc);
    defer reg.deinit();

    try document_global.registerDocument(&js_ctx, doc, &reg, alloc);
    defer document_global.freeBinding(alloc);

    // 5 method properties set on doc_obj + 1 "document" property on global
    try std.testing.expect(set_prop_count >= 6);

    // The last set_property call should set "document" on the global object
    const last = &set_prop_log[set_prop_count - 1];
    try std.testing.expectEqualStrings("document", getPropName(last));

    // Verify method names were set
    var found_get_by_id = false;
    var found_qs = false;
    var found_qsa = false;
    var found_ce = false;
    var found_ctn = false;
    for (set_prop_log[0..set_prop_count]) |entry| {
        const name = getPropName(&entry);
        if (std.mem.eql(u8, name, "getElementById")) found_get_by_id = true;
        if (std.mem.eql(u8, name, "querySelector")) found_qs = true;
        if (std.mem.eql(u8, name, "querySelectorAll")) found_qsa = true;
        if (std.mem.eql(u8, name, "createElement")) found_ce = true;
        if (std.mem.eql(u8, name, "createTextNode")) found_ctn = true;
    }
    try std.testing.expect(found_get_by_id);
    try std.testing.expect(found_qs);
    try std.testing.expect(found_qsa);
    try std.testing.expect(found_ce);
    try std.testing.expect(found_ctn);
}

test "jsGetElementById returns wrapped node for existing id" {
    resetState();
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();

    const div = try doc.createElement("div");
    try div.setAttribute("id", "main");
    try doc.root.appendChild(div, doc.limits);

    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    var reg = node_wrap.NodeRegistry.init(alloc);
    defer reg.deinit();

    try document_global.registerDocument(&js_ctx, doc, &reg, alloc);
    defer document_global.freeBinding(alloc);

    mock_str_content = "main";
    const arg: ?*anyopaque = @ptrFromInt(0x1111);
    const args = [_]?*anyopaque{arg};

    const result = document_global.jsGetElementById(
        js_ctx.ctx,
        null,
        null,
        1,
        @ptrCast(&args),
    );
    // Should return a non-null handle (the wrapped node)
    try std.testing.expect(result != null);
}

test "jsGetElementById returns null for missing id" {
    resetState();
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();

    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    var reg = node_wrap.NodeRegistry.init(alloc);
    defer reg.deinit();

    try document_global.registerDocument(&js_ctx, doc, &reg, alloc);
    defer document_global.freeBinding(alloc);

    last_null_returned = false;
    mock_str_content = "nonexistent";
    const arg: ?*anyopaque = @ptrFromInt(0x2222);
    const args = [_]?*anyopaque{arg};

    const result = document_global.jsGetElementById(
        js_ctx.ctx,
        null,
        null,
        1,
        @ptrCast(&args),
    );
    // Should return the null sentinel from make_null
    try std.testing.expect(result != null);
    try std.testing.expect(last_null_returned);
}

test "jsCreateElement creates and wraps new element" {
    resetState();
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();

    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    var reg = node_wrap.NodeRegistry.init(alloc);
    defer reg.deinit();

    try document_global.registerDocument(&js_ctx, doc, &reg, alloc);
    defer document_global.freeBinding(alloc);

    const initial_count = doc.node_count;
    mock_str_content = "span";
    const arg: ?*anyopaque = @ptrFromInt(0x3333);
    const args = [_]?*anyopaque{arg};

    const result = document_global.jsCreateElement(
        js_ctx.ctx,
        null,
        null,
        1,
        @ptrCast(&args),
    );
    try std.testing.expect(result != null);
    // Document node count should have increased
    try std.testing.expect(doc.node_count > initial_count);
}

test "jsCreateTextNode creates and wraps new text node" {
    resetState();
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();

    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    var reg = node_wrap.NodeRegistry.init(alloc);
    defer reg.deinit();

    try document_global.registerDocument(&js_ctx, doc, &reg, alloc);
    defer document_global.freeBinding(alloc);

    const initial_count = doc.node_count;
    mock_str_content = "hello world";
    const arg: ?*anyopaque = @ptrFromInt(0x4444);
    const args = [_]?*anyopaque{arg};

    const result = document_global.jsCreateTextNode(
        js_ctx.ctx,
        null,
        null,
        1,
        @ptrCast(&args),
    );
    try std.testing.expect(result != null);
    try std.testing.expect(doc.node_count > initial_count);
}

test "jsQuerySelector finds element by tag selector" {
    resetState();
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();

    const div = try doc.createElement("div");
    try doc.root.appendChild(div, doc.limits);
    const span = try doc.createElement("span");
    try div.appendChild(span, doc.limits);

    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    var reg = node_wrap.NodeRegistry.init(alloc);
    defer reg.deinit();

    try document_global.registerDocument(&js_ctx, doc, &reg, alloc);
    defer document_global.freeBinding(alloc);

    mock_str_content = "span";
    const arg: ?*anyopaque = @ptrFromInt(0x5555);
    const args = [_]?*anyopaque{arg};

    const result = document_global.jsQuerySelector(
        js_ctx.ctx,
        null,
        null,
        1,
        @ptrCast(&args),
    );
    // Should find the span and return a wrapped handle
    try std.testing.expect(result != null);
    // Verify it did not return JS null
    try std.testing.expect(!last_null_returned);
}

test "jsQuerySelector returns null for no match" {
    resetState();
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();

    const div = try doc.createElement("div");
    try doc.root.appendChild(div, doc.limits);

    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    var reg = node_wrap.NodeRegistry.init(alloc);
    defer reg.deinit();

    try document_global.registerDocument(&js_ctx, doc, &reg, alloc);
    defer document_global.freeBinding(alloc);

    last_null_returned = false;
    mock_str_content = "article";
    const arg: ?*anyopaque = @ptrFromInt(0x6666);
    const args = [_]?*anyopaque{arg};

    const result = document_global.jsQuerySelector(
        js_ctx.ctx,
        null,
        null,
        1,
        @ptrCast(&args),
    );
    try std.testing.expect(result != null);
    try std.testing.expect(last_null_returned);
}
