const std = @import("std");
const context = @import("context.zig");
const JsHandle = context.JsHandle;
const JsBridge = context.JsBridge;
const JsContext = context.JsContext;
const node_wrap = @import("node_wrap.zig");
const NodeContext = node_wrap.NodeContext;
const node_mod = @import("../dom/node.zig");
const Node = node_mod.Node;
const config = @import("../config.zig");
const pipeline = @import("pipeline.zig");
const css_selector = @import("../css/selector.zig");
const Selector = css_selector.Selector;

var g_bridge: ?*const JsBridge = null;

pub fn setBridge(bridge: *const JsBridge) void {
    g_bridge = bridge;
}

pub fn resetBridge() void {
    g_bridge = null;
}

/// Read a JS string argument into a provided buffer.
fn readJsString(bridge: *const JsBridge, ctx: JsHandle, value: JsHandle, buf: []u8) ?[]const u8 {
    const str_handle = bridge.value_to_string(ctx, value);
    if (str_handle == null) return null;
    defer bridge.string_release(str_handle);
    const len = bridge.string_get_utf8(str_handle, buf.ptr, @intCast(buf.len));
    if (len <= 0) return null;
    return buf[0..@intCast(len - 1)];
}

/// Cast a raw pointer to NodeContext via bridge's class_get_user_data.
fn castNodeContext(ptr: ?*anyopaque) ?*NodeContext {
    const bridge = g_bridge orelse return null;
    const data = bridge.class_get_user_data(ptr);
    if (data == null) return null;
    return @ptrCast(@alignCast(data));
}

/// Extract the NodeContext from a JS object handle via the bridge's class user data.
fn extractNodeContext(bridge: *const JsBridge, js_obj: ?*anyopaque) ?*NodeContext {
    const ptr = bridge.class_get_user_data(js_obj);
    if (ptr == null) return null;
    return @ptrCast(@alignCast(ptr));
}

fn extractBoundNodeContext(bridge: *const JsBridge, ctx: JsHandle, this_obj: ?*anyopaque) ?*NodeContext {
    if (this_obj == null) return null;
    const node_obj = bridge.object_get_property(ctx, this_obj, "__node");
    return extractNodeContext(bridge, node_obj);
}

/// Read an argument value from the args pointer at the given index.
fn readArg(arg_count: c_int, args: ?*const JsHandle, index: usize) ?JsHandle {
    if (args == null) return null;
    if (index >= @as(usize, @intCast(arg_count))) return null;
    const arg_slice: [*]const JsHandle = @ptrCast(args.?);
    return arg_slice[index];
}

/// JS-callable: node.appendChild(child)
pub fn jsAppendChild(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    arg_count: c_int,
    args: ?*const JsHandle,
) callconv(.c) ?*anyopaque {
    const node_ctx = castNodeContext(this_obj) orelse return null;
    const bridge = node_ctx.js_ctx.bridge;

    const child_arg = readArg(arg_count, args, 0) orelse return bridge.make_undefined(ctx);
    const child_ctx = extractNodeContext(bridge, child_arg) orelse return bridge.make_undefined(ctx);

    const cfg = config.getConfig();
    const limits = .{
        .max_children = cfg.parser.max_children_per_node,
        .max_depth = cfg.parser.max_tree_depth,
    };
    node_ctx.node.appendChild(child_ctx.node, limits) catch return bridge.make_undefined(ctx);
    pipeline.notifyDirty();
    return child_arg;
}

/// JS-callable: node.removeChild(child)
pub fn jsRemoveChild(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    arg_count: c_int,
    args: ?*const JsHandle,
) callconv(.c) ?*anyopaque {
    const node_ctx = castNodeContext(this_obj) orelse return null;
    const bridge = node_ctx.js_ctx.bridge;

    const child_arg = readArg(arg_count, args, 0) orelse return bridge.make_undefined(ctx);
    const child_ctx = extractNodeContext(bridge, child_arg) orelse return bridge.make_undefined(ctx);

    node_ctx.node.removeChild(child_ctx.node);
    pipeline.notifyDirty();
    return child_arg;
}

/// JS-callable: node.setAttribute(name, value)
pub fn jsSetAttribute(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    arg_count: c_int,
    args: ?*const JsHandle,
) callconv(.c) ?*anyopaque {
    const node_ctx = castNodeContext(this_obj) orelse return null;
    const bridge = node_ctx.js_ctx.bridge;

    const name_arg = readArg(arg_count, args, 0) orelse return bridge.make_undefined(ctx);
    const value_arg = readArg(arg_count, args, 1) orelse return bridge.make_undefined(ctx);

    var name_buf: [256]u8 = undefined;
    var val_buf: [1024]u8 = undefined;
    const attr_name = readJsString(bridge, ctx, name_arg, &name_buf) orelse return bridge.make_undefined(ctx);
    const attr_val = readJsString(bridge, ctx, value_arg, &val_buf) orelse return bridge.make_undefined(ctx);

    node_ctx.node.setAttribute(attr_name, attr_val) catch return bridge.make_undefined(ctx);
    pipeline.notifyDirty();
    return bridge.make_undefined(ctx);
}

/// JS-callable: node.getAttribute(name)
pub fn jsGetAttribute(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    arg_count: c_int,
    args: ?*const JsHandle,
) callconv(.c) ?*anyopaque {
    const node_ctx = castNodeContext(this_obj) orelse return null;
    const bridge = node_ctx.js_ctx.bridge;

    const name_arg = readArg(arg_count, args, 0) orelse return bridge.make_null(ctx);
    var name_buf: [256]u8 = undefined;
    const attr_name = readJsString(bridge, ctx, name_arg, &name_buf) orelse return bridge.make_null(ctx);

    const val = node_ctx.node.getAttribute(attr_name) orelse return bridge.make_null(ctx);

    var val_buf: [1024]u8 = undefined;
    if (val.len < val_buf.len) {
        @memcpy(val_buf[0..val.len], val);
        val_buf[val.len] = 0;
        return bridge.make_string_value(ctx, val_buf[0..val.len :0]);
    }
    return bridge.make_null(ctx);
}

/// JS-callable: node.removeAttribute(name)
pub fn jsRemoveAttribute(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    arg_count: c_int,
    args: ?*const JsHandle,
) callconv(.c) ?*anyopaque {
    const node_ctx = castNodeContext(this_obj) orelse return null;
    const bridge = node_ctx.js_ctx.bridge;

    const name_arg = readArg(arg_count, args, 0) orelse return bridge.make_undefined(ctx);
    var name_buf: [256]u8 = undefined;
    const attr_name = readJsString(bridge, ctx, name_arg, &name_buf) orelse return bridge.make_undefined(ctx);

    node_ctx.node.removeAttribute(attr_name);
    pipeline.notifyDirty();
    return bridge.make_undefined(ctx);
}

/// JS-callable: node.hasAttribute(name)
pub fn jsHasAttribute(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    arg_count: c_int,
    args: ?*const JsHandle,
) callconv(.c) ?*anyopaque {
    const node_ctx = castNodeContext(this_obj) orelse return null;
    const bridge = node_ctx.js_ctx.bridge;

    const name_arg = readArg(arg_count, args, 0) orelse return bridge.make_number_value(ctx, 0.0);
    var name_buf: [256]u8 = undefined;
    const attr_name = readJsString(bridge, ctx, name_arg, &name_buf) orelse {
        return bridge.make_number_value(ctx, 0.0);
    };

    const has = node_ctx.node.hasAttribute(attr_name);
    return bridge.make_number_value(ctx, if (has) 1.0 else 0.0);
}

/// JS-callable: node.matches(selector)
pub fn jsMatches(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    arg_count: c_int,
    args: ?*const JsHandle,
) callconv(.c) ?*anyopaque {
    const node_ctx = castNodeContext(this_obj) orelse return null;
    const bridge = node_ctx.js_ctx.bridge;
    const sel_arg = readArg(arg_count, args, 0) orelse return bridge.make_number_value(ctx, 0.0);

    var sel_buf: [512]u8 = undefined;
    const sel_str = readJsString(bridge, ctx, sel_arg, &sel_buf) orelse return bridge.make_number_value(ctx, 0.0);
    if (node_ctx.node.node_type != .element) return bridge.make_number_value(ctx, 0.0);

    var arena = std.heap.ArenaAllocator.init(node_ctx.node.allocator);
    defer arena.deinit();
    const sel = Selector.parse(arena.allocator(), sel_str) catch return bridge.make_number_value(ctx, 0.0);
    const matches = sel.matchesNode(node_ctx.node);
    return bridge.make_number_value(ctx, if (matches) 1.0 else 0.0);
}

/// JS-callable: node.closest(selector)
pub fn jsClosest(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    arg_count: c_int,
    args: ?*const JsHandle,
) callconv(.c) ?*anyopaque {
    const node_ctx = castNodeContext(this_obj) orelse return null;
    const bridge = node_ctx.js_ctx.bridge;
    const sel_arg = readArg(arg_count, args, 0) orelse return bridge.make_null(ctx);

    var sel_buf: [512]u8 = undefined;
    const sel_str = readJsString(bridge, ctx, sel_arg, &sel_buf) orelse return bridge.make_null(ctx);

    var arena = std.heap.ArenaAllocator.init(node_ctx.node.allocator);
    defer arena.deinit();
    const sel = Selector.parse(arena.allocator(), sel_str) catch return bridge.make_null(ctx);

    var current: ?*Node = node_ctx.node;
    while (current) |n| {
        if (n.node_type == .element and sel.matchesNode(n)) {
            return node_wrap.wrapNode(node_ctx.js_ctx, node_ctx.registry, n) catch bridge.make_null(ctx);
        }
        current = n.parent;
    }
    return bridge.make_null(ctx);
}

fn normalizeCssProperty(name: []const u8, out_buf: []u8) []const u8 {
    var j: usize = 0;
    for (name) |c| {
        if (j >= out_buf.len) break;
        if (c >= 'A' and c <= 'Z') {
            if (j + 1 >= out_buf.len) break;
            out_buf[j] = '-';
            out_buf[j + 1] = c + 32;
            j += 2;
        } else if (c == '_') {
            out_buf[j] = '-';
            j += 1;
        } else {
            out_buf[j] = std.ascii.toLower(c);
            j += 1;
        }
    }
    return out_buf[0..j];
}

fn hasClass(node: *const Node, class_name: []const u8) bool {
    const class_attr = node.getAttribute("class") orelse return false;
    var it = std.mem.tokenizeAny(u8, class_attr, " \t\n\r");
    while (it.next()) |token| {
        if (std.mem.eql(u8, token, class_name)) return true;
    }
    return false;
}

fn setClassList(node: *Node, classes: []const []const u8) bool {
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(node.allocator);
    for (classes, 0..) |c, idx| {
        if (idx > 0) out.append(node.allocator, ' ') catch return false;
        out.appendSlice(node.allocator, c) catch return false;
    }
    node.setAttribute("class", out.items) catch return false;
    return true;
}

fn collectClasses(node: *const Node, allocator: std.mem.Allocator) ![]const []const u8 {
    const class_attr = node.getAttribute("class") orelse return &[_][]const u8{};
    var classes = std.ArrayListUnmanaged([]const u8){};
    errdefer {
        for (classes.items) |c| allocator.free(c);
        classes.deinit(allocator);
    }
    var it = std.mem.tokenizeAny(u8, class_attr, " \t\n\r");
    while (it.next()) |token| {
        if (token.len == 0) continue;
        try classes.append(allocator, try allocator.dupe(u8, token));
    }
    return try classes.toOwnedSlice(allocator);
}

fn freeClassSlice(allocator: std.mem.Allocator, classes: []const []const u8) void {
    for (classes) |c| allocator.free(c);
    allocator.free(classes);
}

fn findStyleProperty(style_attr: []const u8, prop_name: []const u8) ?[]const u8 {
    var parts = std.mem.splitScalar(u8, style_attr, ';');
    while (parts.next()) |part| {
        const decl = std.mem.trim(u8, part, " \t\r\n");
        if (decl.len == 0) continue;
        var kv = std.mem.splitScalar(u8, decl, ':');
        const k = std.mem.trim(u8, kv.next() orelse continue, " \t\r\n");
        const v = std.mem.trim(u8, kv.next() orelse continue, " \t\r\n");
        if (std.ascii.eqlIgnoreCase(k, prop_name)) return v;
    }
    return null;
}

fn writeStyleProperty(node: *Node, prop_name: []const u8, value_opt: ?[]const u8) bool {
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(node.allocator);
    const style_attr = node.getAttribute("style") orelse "";

    var found = false;
    var parts = std.mem.splitScalar(u8, style_attr, ';');
    while (parts.next()) |part| {
        const decl = std.mem.trim(u8, part, " \t\r\n");
        if (decl.len == 0) continue;
        var kv = std.mem.splitScalar(u8, decl, ':');
        const k = std.mem.trim(u8, kv.next() orelse continue, " \t\r\n");
        const v = std.mem.trim(u8, kv.next() orelse "", " \t\r\n");

        if (std.ascii.eqlIgnoreCase(k, prop_name)) {
            found = true;
            if (value_opt) |value| {
                if (out.items.len > 0) out.append(node.allocator, ';') catch return false;
                out.appendSlice(node.allocator, prop_name) catch return false;
                out.appendSlice(node.allocator, ": ") catch return false;
                out.appendSlice(node.allocator, value) catch return false;
            }
        } else {
            if (out.items.len > 0) out.append(node.allocator, ';') catch return false;
            out.appendSlice(node.allocator, k) catch return false;
            out.appendSlice(node.allocator, ": ") catch return false;
            out.appendSlice(node.allocator, v) catch return false;
        }
    }

    if (!found) {
        if (value_opt) |value| {
            if (out.items.len > 0) out.append(node.allocator, ';') catch return false;
            out.appendSlice(node.allocator, prop_name) catch return false;
            out.appendSlice(node.allocator, ": ") catch return false;
            out.appendSlice(node.allocator, value) catch return false;
        }
    }

    node.setAttribute("style", std.mem.trim(u8, out.items, " \t\r\n")) catch return false;
    return true;
}

pub fn jsClassListContains(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    arg_count: c_int,
    args: ?*const JsHandle,
) callconv(.c) ?*anyopaque {
    const bridge = g_bridge orelse return null;
    const node_ctx = extractBoundNodeContext(bridge, ctx, this_obj) orelse return bridge.make_number_value(ctx, 0.0);
    const token_arg = readArg(arg_count, args, 0) orelse return bridge.make_number_value(ctx, 0.0);

    var token_buf: [256]u8 = undefined;
    const token = readJsString(bridge, ctx, token_arg, &token_buf) orelse return bridge.make_number_value(ctx, 0.0);
    return bridge.make_number_value(ctx, if (hasClass(node_ctx.node, token)) 1.0 else 0.0);
}

pub fn jsClassListAdd(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    arg_count: c_int,
    args: ?*const JsHandle,
) callconv(.c) ?*anyopaque {
    const bridge = g_bridge orelse return null;
    const node_ctx = extractBoundNodeContext(bridge, ctx, this_obj) orelse return bridge.make_undefined(ctx);
    if (arg_count <= 0) return bridge.make_undefined(ctx);

    var changed = false;
    var i: usize = 0;
    while (i < @as(usize, @intCast(arg_count))) : (i += 1) {
        const token_arg = readArg(arg_count, args, i) orelse continue;
        var token_buf: [256]u8 = undefined;
        const token = readJsString(bridge, ctx, token_arg, &token_buf) orelse continue;
        if (token.len == 0) continue;
        if (hasClass(node_ctx.node, token)) continue;

        const classes = collectClasses(node_ctx.node, node_ctx.node.allocator) catch continue;
        defer freeClassSlice(node_ctx.node.allocator, classes);

        const expanded = node_ctx.node.allocator.alloc([]const u8, classes.len + 1) catch continue;
        defer node_ctx.node.allocator.free(expanded);
        for (classes, 0..) |c, idx| expanded[idx] = c;
        expanded[classes.len] = token;

        if (!setClassList(node_ctx.node, expanded)) continue;
        changed = true;
    }

    if (changed) pipeline.notifyDirty();
    return bridge.make_undefined(ctx);
}

pub fn jsClassListRemove(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    arg_count: c_int,
    args: ?*const JsHandle,
) callconv(.c) ?*anyopaque {
    const bridge = g_bridge orelse return null;
    const node_ctx = extractBoundNodeContext(bridge, ctx, this_obj) orelse return bridge.make_undefined(ctx);
    if (arg_count <= 0) return bridge.make_undefined(ctx);

    var changed = false;
    var i: usize = 0;
    while (i < @as(usize, @intCast(arg_count))) : (i += 1) {
        const token_arg = readArg(arg_count, args, i) orelse continue;
        var token_buf: [256]u8 = undefined;
        const token = readJsString(bridge, ctx, token_arg, &token_buf) orelse continue;
        if (token.len == 0) continue;

        const classes = collectClasses(node_ctx.node, node_ctx.node.allocator) catch continue;
        defer freeClassSlice(node_ctx.node.allocator, classes);
        var filtered = std.ArrayListUnmanaged([]const u8){};
        defer filtered.deinit(node_ctx.node.allocator);

        var removed = false;
        for (classes) |c| {
            if (std.mem.eql(u8, c, token)) {
                removed = true;
                continue;
            }
            filtered.append(node_ctx.node.allocator, c) catch break;
        }
        if (!removed) continue;
        if (!setClassList(node_ctx.node, filtered.items)) continue;
        changed = true;
    }

    if (changed) pipeline.notifyDirty();
    return bridge.make_undefined(ctx);
}

pub fn jsClassListToggle(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    arg_count: c_int,
    args: ?*const JsHandle,
) callconv(.c) ?*anyopaque {
    const bridge = g_bridge orelse return null;
    const node_ctx = extractBoundNodeContext(bridge, ctx, this_obj) orelse return bridge.make_number_value(ctx, 0.0);
    const token_arg = readArg(arg_count, args, 0) orelse return bridge.make_number_value(ctx, 0.0);

    var token_buf: [256]u8 = undefined;
    const token = readJsString(bridge, ctx, token_arg, &token_buf) orelse return bridge.make_number_value(ctx, 0.0);
    if (token.len == 0) return bridge.make_number_value(ctx, 0.0);

    if (hasClass(node_ctx.node, token)) {
        _ = jsClassListRemove(ctx, null, this_obj, arg_count, args);
        return bridge.make_number_value(ctx, 0.0);
    }
    _ = jsClassListAdd(ctx, null, this_obj, arg_count, args);
    return bridge.make_number_value(ctx, 1.0);
}

pub fn jsClassListReplace(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    arg_count: c_int,
    args: ?*const JsHandle,
) callconv(.c) ?*anyopaque {
    const bridge = g_bridge orelse return null;
    const node_ctx = extractBoundNodeContext(bridge, ctx, this_obj) orelse return bridge.make_number_value(ctx, 0.0);
    const old_arg = readArg(arg_count, args, 0) orelse return bridge.make_number_value(ctx, 0.0);
    const new_arg = readArg(arg_count, args, 1) orelse return bridge.make_number_value(ctx, 0.0);

    var old_buf: [256]u8 = undefined;
    var new_buf: [256]u8 = undefined;
    const old_token = readJsString(bridge, ctx, old_arg, &old_buf) orelse return bridge.make_number_value(ctx, 0.0);
    const new_token = readJsString(bridge, ctx, new_arg, &new_buf) orelse return bridge.make_number_value(ctx, 0.0);
    if (old_token.len == 0 or new_token.len == 0) return bridge.make_number_value(ctx, 0.0);
    if (!hasClass(node_ctx.node, old_token)) return bridge.make_number_value(ctx, 0.0);

    const classes = collectClasses(node_ctx.node, node_ctx.node.allocator) catch return bridge.make_number_value(ctx, 0.0);
    defer freeClassSlice(node_ctx.node.allocator, classes);
    var replaced = std.ArrayListUnmanaged([]const u8){};
    defer replaced.deinit(node_ctx.node.allocator);

    var did_replace = false;
    for (classes) |c| {
        if (std.mem.eql(u8, c, old_token)) {
            if (!hasClass(node_ctx.node, new_token)) {
                replaced.append(node_ctx.node.allocator, new_token) catch return bridge.make_number_value(ctx, 0.0);
            }
            did_replace = true;
        } else {
            replaced.append(node_ctx.node.allocator, c) catch return bridge.make_number_value(ctx, 0.0);
        }
    }

    if (!did_replace) return bridge.make_number_value(ctx, 0.0);
    if (!setClassList(node_ctx.node, replaced.items)) return bridge.make_number_value(ctx, 0.0);
    pipeline.notifyDirty();
    return bridge.make_number_value(ctx, 1.0);
}

pub fn jsStyleSetProperty(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    arg_count: c_int,
    args: ?*const JsHandle,
) callconv(.c) ?*anyopaque {
    const bridge = g_bridge orelse return null;
    const node_ctx = extractBoundNodeContext(bridge, ctx, this_obj) orelse return bridge.make_undefined(ctx);
    const name_arg = readArg(arg_count, args, 0) orelse return bridge.make_undefined(ctx);
    const value_arg = readArg(arg_count, args, 1) orelse return bridge.make_undefined(ctx);

    var name_buf: [256]u8 = undefined;
    var value_buf: [1024]u8 = undefined;
    const name_raw = readJsString(bridge, ctx, name_arg, &name_buf) orelse return bridge.make_undefined(ctx);
    const value = readJsString(bridge, ctx, value_arg, &value_buf) orelse return bridge.make_undefined(ctx);

    var norm_buf: [256]u8 = undefined;
    const prop_name = normalizeCssProperty(name_raw, &norm_buf);
    if (!writeStyleProperty(node_ctx.node, prop_name, value)) return bridge.make_undefined(ctx);
    pipeline.notifyDirty();
    return bridge.make_undefined(ctx);
}

pub fn jsStyleGetPropertyValue(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    arg_count: c_int,
    args: ?*const JsHandle,
) callconv(.c) ?*anyopaque {
    const bridge = g_bridge orelse return null;
    const node_ctx = extractBoundNodeContext(bridge, ctx, this_obj) orelse return bridge.make_string_value(ctx, "");
    const name_arg = readArg(arg_count, args, 0) orelse return bridge.make_string_value(ctx, "");

    var name_buf: [256]u8 = undefined;
    const name_raw = readJsString(bridge, ctx, name_arg, &name_buf) orelse return bridge.make_string_value(ctx, "");
    var norm_buf: [256]u8 = undefined;
    const prop_name = normalizeCssProperty(name_raw, &norm_buf);

    const style_attr = node_ctx.node.getAttribute("style") orelse return bridge.make_string_value(ctx, "");
    const value = findStyleProperty(style_attr, prop_name) orelse return bridge.make_string_value(ctx, "");

    var out: [1024]u8 = undefined;
    if (value.len < out.len) {
        @memcpy(out[0..value.len], value);
        out[value.len] = 0;
        return bridge.make_string_value(ctx, out[0..value.len :0]);
    }
    return bridge.make_string_value(ctx, "");
}

pub fn jsStyleRemoveProperty(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    arg_count: c_int,
    args: ?*const JsHandle,
) callconv(.c) ?*anyopaque {
    const bridge = g_bridge orelse return null;
    const node_ctx = extractBoundNodeContext(bridge, ctx, this_obj) orelse return bridge.make_string_value(ctx, "");
    const name_arg = readArg(arg_count, args, 0) orelse return bridge.make_string_value(ctx, "");

    var name_buf: [256]u8 = undefined;
    const name_raw = readJsString(bridge, ctx, name_arg, &name_buf) orelse return bridge.make_string_value(ctx, "");
    var norm_buf: [256]u8 = undefined;
    const prop_name = normalizeCssProperty(name_raw, &norm_buf);

    const style_attr = node_ctx.node.getAttribute("style") orelse return bridge.make_string_value(ctx, "");
    const prev = findStyleProperty(style_attr, prop_name) orelse "";
    _ = writeStyleProperty(node_ctx.node, prop_name, null);
    pipeline.notifyDirty();

    var out: [1024]u8 = undefined;
    if (prev.len < out.len) {
        @memcpy(out[0..prev.len], prev);
        out[prev.len] = 0;
        return bridge.make_string_value(ctx, out[0..prev.len :0]);
    }
    return bridge.make_string_value(ctx, "");
}
