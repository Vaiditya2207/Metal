const std = @import("std");
const dom_node = @import("../dom/node.zig");
const css_tokenizer = @import("tokenizer.zig");
const config = @import("../config.zig");

pub const AttributeMatch = enum { exists, equals };

pub const AttributeSelector = struct {
    name: []const u8,
    value: ?[]const u8 = null,
    op: AttributeMatch = .exists,
};

pub const SelectorPart = struct {
    tag: ?[]const u8 = null,
    id: ?[]const u8 = null,
    classes: []const []const u8 = &.{},
    attributes: []const AttributeSelector = &.{},
    universal: bool = false,
    is_root: bool = false,
    not_selectors: []const SelectorPart = &.{},
    any_selectors: []const SelectorPart = &.{},
};

pub const Combinator = enum { descendant, child, none };

pub const SelectorComponent = struct {
    part: SelectorPart,
    combinator: Combinator,
};

pub const Specificity = struct {
    a: u16 = 0,
    b: u16 = 0,
    c: u16 = 0,

    pub fn toScore(self: Specificity) u64 {
        return (@as(u64, self.a) << 32) | (@as(u64, self.b) << 16) | @as(u64, self.c);
    }

    pub fn greaterThan(self: Specificity, other: Specificity) bool {
        return self.toScore() > other.toScore();
    }
};

pub const Selector = struct {
    components: []const SelectorComponent,
    specificity: Specificity,

    pub fn parse(allocator: std.mem.Allocator, input: []const u8) !Selector {
        var tokenizer = css_tokenizer.CssTokenizer.init(allocator, input);
        var spec_val = Specificity{};

        var components: std.ArrayListUnmanaged(SelectorComponent) = .empty;
        var pending_combinator: Combinator = .none;
        var pushed: ?css_tokenizer.CssToken = null;

        const max_parts = config.getConfig().css.max_selector_parts;

        while (components.items.len < max_parts) {
            const token = if (pushed) |t| blk: {
                pushed = null;
                break :blk t;
            } else try tokenizer.next();
            if (token.type == .eof) break;

            if (token.type == .whitespace) {
                if (pending_combinator == .none) pending_combinator = .descendant;
                continue;
            }
            if (token.type == .delim and std.mem.eql(u8, token.value, ">")) {
                pending_combinator = .child;
                continue;
            }
            if (token.type == .comma or (token.type == .delim and std.mem.eql(u8, token.value, ","))) {
                break;
            }

            var part = SelectorPart{};
            var t = token;
            while (true) {
                switch (t.type) {
                    .ident => {
                        part.tag = try allocator.dupe(u8, t.value);
                        spec_val.c += 1;
                    },
                    .hash => {
                        const id_val = if (t.value.len > 0 and t.value[0] == '#') t.value[1..] else t.value;
                        part.id = try allocator.dupe(u8, id_val);
                        spec_val.a += 1;
                    },
                    .delim => {
                        if (std.mem.eql(u8, t.value, ".")) {
                            const class_tok = if (pushed) |pt| blk: {
                                pushed = null;
                                break :blk pt;
                            } else try tokenizer.next();
                            if (class_tok.type == .ident) {
                                var classes: std.ArrayListUnmanaged([]const u8) = .empty;
                                for (part.classes) |c| try classes.append(allocator, c);
                                try classes.append(allocator, try allocator.dupe(u8, class_tok.value));
                                part.classes = try classes.toOwnedSlice(allocator);
                                spec_val.b += 1;
                            } else {
                                pushed = class_tok;
                            }
                        } else if (std.mem.eql(u8, t.value, "*")) {
                            part.universal = true;
                        }
                    },
                    .left_bracket => {
                        try parseAttributeSelector(allocator, &tokenizer, &pushed, &part, &spec_val);
                    },
                    .colon => {
                        try parsePseudo(allocator, &tokenizer, &pushed, &part, &spec_val);
                    },
                    else => {},
                }

                const next_t = if (pushed) |pt| blk: {
                    pushed = null;
                    break :blk pt;
                } else try tokenizer.next();

                if (next_t.type == .eof or
                    next_t.type == .whitespace or
                    next_t.type == .comma or
                    (next_t.type == .delim and
                    (std.mem.eql(u8, next_t.value, ",") or std.mem.eql(u8, next_t.value, ">"))))
                {
                    pushed = next_t;
                    break;
                }
                t = next_t;
            }

            if (isEmptyPart(part)) continue;
            try components.append(allocator, .{ .part = part, .combinator = pending_combinator });
            pending_combinator = .none;
        }

        return Selector{ .components = try components.toOwnedSlice(allocator), .specificity = spec_val };
    }

    pub fn matchesNode(self: Selector, node: *const dom_node.Node) bool {
        if (self.components.len == 0) return false;
        var current_node: ?*const dom_node.Node = node;
        var i: usize = self.components.len - 1;

        if (current_node == null or !matchPart(self.components[i].part, current_node.?)) return false;

        while (i > 0) {
            const combinator = self.components[i].combinator;
            i -= 1;
            const target_part = self.components[i].part;

            if (combinator == .child) {
                current_node = current_node.?.parent;
                if (current_node == null or !matchPart(target_part, current_node.?)) return false;
            } else if (combinator == .descendant) {
                var found = false;
                while (current_node.?.parent) |p| {
                    current_node = p;
                    if (matchPart(target_part, current_node.?)) {
                        found = true;
                        break;
                    }
                }
                if (!found) return false;
            } else {
                return false;
            }
        }
        return true;
    }

    fn matchPart(part: SelectorPart, node: *const dom_node.Node) bool {
        if (node.node_type != .element) return false;

        if (part.is_root) {
            if (node.tag != .html) return false;
        }

        if (part.tag) |tag| {
            var tag_match = false;
            if (node.tag_name_str) |node_tag| {
                if (std.ascii.eqlIgnoreCase(tag, node_tag)) tag_match = true;
            } else {
                const tag_name = @tagName(node.tag);
                if (!std.mem.eql(u8, tag_name, "unknown") and std.ascii.eqlIgnoreCase(tag, tag_name)) {
                    tag_match = true;
                }
            }
            if (!tag_match) return false;
        }

        if (part.id) |id| {
            var id_found = false;
            for (node.attributes.items) |attr| {
                if (std.mem.eql(u8, attr.name, "id") and std.mem.eql(u8, attr.value, id)) {
                    id_found = true;
                    break;
                }
            }
            if (!id_found) return false;
        }

        if (part.classes.len > 0) {
            const class_attr = node.getAttribute("class");
            if (class_attr) |val| {
                for (part.classes) |cls| {
                    var found = false;
                    var iter = std.mem.tokenizeAny(u8, val, " \t\n\r");
                    while (iter.next()) |token| {
                        if (std.mem.eql(u8, token, cls)) {
                            found = true;
                            break;
                        }
                    }
                    if (!found) return false;
                }
            } else {
                return false;
            }
        }

        if (part.attributes.len > 0) {
            for (part.attributes) |a| {
                const attr_val = node.getAttribute(a.name);
                switch (a.op) {
                    .exists => if (attr_val == null) return false,
                    .equals => {
                        const expected = a.value orelse return false;
                        const actual = attr_val orelse return false;
                        if (!std.mem.eql(u8, expected, actual)) return false;
                    },
                }
            }
        }

        if (part.any_selectors.len > 0) {
            var any_ok = false;
            for (part.any_selectors) |arg| {
                if (matchPart(arg, node)) {
                    any_ok = true;
                    break;
                }
            }
            if (!any_ok) return false;
        }

        if (part.not_selectors.len > 0) {
            for (part.not_selectors) |arg| {
                if (matchPart(arg, node)) return false;
            }
        }

        return true;
    }
};

fn isEmptyPart(part: SelectorPart) bool {
    return !part.universal and
        !part.is_root and
        part.tag == null and
        part.id == null and
        part.classes.len == 0 and
        part.attributes.len == 0 and
        part.not_selectors.len == 0 and
        part.any_selectors.len == 0;
}

fn tokenToText(tok: css_tokenizer.CssToken, out: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator) !void {
    switch (tok.type) {
        .hash => {
            try out.append(allocator, '#');
            try out.appendSlice(allocator, tok.value);
        },
        .colon => try out.append(allocator, ':'),
        .left_bracket => try out.append(allocator, '['),
        .right_bracket => try out.append(allocator, ']'),
        .delim, .ident, .string => try out.appendSlice(allocator, tok.value),
        else => {},
    }
}

fn parseSimplePart(allocator: std.mem.Allocator, raw_in: []const u8) !SelectorPart {
    const raw = std.mem.trim(u8, raw_in, " \t\n\r");
    var part = SelectorPart{};
    if (raw.len == 0) return part;

    if (std.mem.eql(u8, raw, ":root")) {
        part.is_root = true;
        return part;
    }

    var i: usize = 0;
    while (i < raw.len) {
        if (raw[i] == '#') {
            i += 1;
            const start = i;
            while (i < raw.len and (std.ascii.isAlphanumeric(raw[i]) or raw[i] == '-' or raw[i] == '_')) : (i += 1) {}
            if (i > start) part.id = try allocator.dupe(u8, raw[start..i]);
            continue;
        }
        if (raw[i] == '.') {
            i += 1;
            const start = i;
            while (i < raw.len and (std.ascii.isAlphanumeric(raw[i]) or raw[i] == '-' or raw[i] == '_')) : (i += 1) {}
            if (i > start) {
                var classes: std.ArrayListUnmanaged([]const u8) = .empty;
                for (part.classes) |c| try classes.append(allocator, c);
                try classes.append(allocator, try allocator.dupe(u8, raw[start..i]));
                part.classes = try classes.toOwnedSlice(allocator);
            }
            continue;
        }
        if (raw[i] == '[') {
            const start = i;
            while (i < raw.len and raw[i] != ']') : (i += 1) {}
            if (i < raw.len and raw[i] == ']') i += 1;
            const inside = std.mem.trim(u8, raw[start + 1 .. i - 1], " \t\n\r");
            if (inside.len > 0) {
                var attrs: std.ArrayListUnmanaged(AttributeSelector) = .empty;
                for (part.attributes) |a| try attrs.append(allocator, a);

                if (std.mem.indexOfScalar(u8, inside, '=')) |eq_idx| {
                    const name = std.mem.trim(u8, inside[0..eq_idx], " \t\n\r");
                    var val = std.mem.trim(u8, inside[eq_idx + 1 ..], " \t\n\r");
                    if (val.len >= 2 and ((val[0] == '"' and val[val.len - 1] == '"') or (val[0] == '\'' and val[val.len - 1] == '\''))) {
                        val = val[1 .. val.len - 1];
                    }
                    try attrs.append(allocator, .{
                        .name = try allocator.dupe(u8, name),
                        .value = try allocator.dupe(u8, val),
                        .op = .equals,
                    });
                } else {
                    try attrs.append(allocator, .{
                        .name = try allocator.dupe(u8, inside),
                        .op = .exists,
                    });
                }
                part.attributes = try attrs.toOwnedSlice(allocator);
            }
            continue;
        }
        if (raw[i] == '*') {
            part.universal = true;
            i += 1;
            continue;
        }
        if (std.ascii.isAlphabetic(raw[i])) {
            const start = i;
            while (i < raw.len and (std.ascii.isAlphanumeric(raw[i]) or raw[i] == '-' or raw[i] == '_')) : (i += 1) {}
            part.tag = try allocator.dupe(u8, raw[start..i]);
            continue;
        }
        i += 1;
    }
    return part;
}

fn parsePseudoFunctionArgs(allocator: std.mem.Allocator, tokenizer: *css_tokenizer.CssTokenizer, pushed: *?css_tokenizer.CssToken) ![]const SelectorPart {
    var parts: std.ArrayListUnmanaged(SelectorPart) = .empty;
    var arg: std.ArrayListUnmanaged(u8) = .empty;
    defer arg.deinit(allocator);
    var depth: usize = 1;

    while (true) {
        const tok = if (pushed.*) |pt| blk: {
            pushed.* = null;
            break :blk pt;
        } else try tokenizer.next();
        if (tok.type == .eof) break;

        if (tok.type == .left_paren) {
            depth += 1;
            try tokenToText(tok, &arg, allocator);
            continue;
        }
        if (tok.type == .right_paren) {
            depth -= 1;
            if (depth == 0) {
                const parsed = try parseSimplePart(allocator, arg.items);
                if (!isEmptyPart(parsed)) try parts.append(allocator, parsed);
                break;
            }
            try tokenToText(tok, &arg, allocator);
            continue;
        }
        if (depth == 1 and tok.type == .comma) {
            const parsed = try parseSimplePart(allocator, arg.items);
            if (!isEmptyPart(parsed)) try parts.append(allocator, parsed);
            arg.clearRetainingCapacity();
            continue;
        }
        if (tok.type == .whitespace) {
            if (arg.items.len > 0) try arg.append(allocator, ' ');
            continue;
        }
        try tokenToText(tok, &arg, allocator);
    }
    return try parts.toOwnedSlice(allocator);
}

fn parsePseudo(
    allocator: std.mem.Allocator,
    tokenizer: *css_tokenizer.CssTokenizer,
    pushed: *?css_tokenizer.CssToken,
    part: *SelectorPart,
    spec: *Specificity,
) !void {
    const pseudo_tok = if (pushed.*) |pt| blk: {
        pushed.* = null;
        break :blk pt;
    } else try tokenizer.next();

    if (pseudo_tok.type == .colon) {
        _ = if (pushed.*) |pt| blk: {
            pushed.* = null;
            break :blk pt;
        } else try tokenizer.next();
        spec.c += 1;
        return;
    }
    if (pseudo_tok.type != .ident) {
        pushed.* = pseudo_tok;
        return;
    }

    const name = pseudo_tok.value;
    const next_tok = if (pushed.*) |pt| blk: {
        pushed.* = null;
        break :blk pt;
    } else try tokenizer.next();

    if (next_tok.type == .left_paren) {
        const args = try parsePseudoFunctionArgs(allocator, tokenizer, pushed);
        if (std.mem.eql(u8, name, "not")) {
            part.not_selectors = args;
            spec.b += 1;
        } else if (std.mem.eql(u8, name, "is") or std.mem.eql(u8, name, "where")) {
            part.any_selectors = args;
            if (!std.mem.eql(u8, name, "where")) spec.b += 1;
        } else {
            spec.b += 1;
        }
        return;
    }

    pushed.* = next_tok;
    if (std.mem.eql(u8, name, "root")) {
        part.is_root = true;
    }
    spec.b += 1;
}

fn parseAttributeSelector(
    allocator: std.mem.Allocator,
    tokenizer: *css_tokenizer.CssTokenizer,
    pushed: *?css_tokenizer.CssToken,
    part: *SelectorPart,
    spec: *Specificity,
) !void {
    var name_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer name_buf.deinit(allocator);
    var value_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer value_buf.deinit(allocator);
    var seen_eq = false;

    while (true) {
        const tok = if (pushed.*) |pt| blk: {
            pushed.* = null;
            break :blk pt;
        } else try tokenizer.next();
        if (tok.type == .eof or tok.type == .right_bracket) break;
        if (tok.type == .whitespace) continue;

        if (!seen_eq and tok.type == .delim and std.mem.eql(u8, tok.value, "=")) {
            seen_eq = true;
            continue;
        }

        if (!seen_eq) {
            try name_buf.appendSlice(allocator, tok.value);
        } else {
            if (tok.type == .string) {
                try value_buf.appendSlice(allocator, tok.value);
            } else {
                try value_buf.appendSlice(allocator, tok.value);
            }
        }
    }

    const name = std.mem.trim(u8, name_buf.items, " \t\n\r");
    if (name.len == 0) return;

    var attrs: std.ArrayListUnmanaged(AttributeSelector) = .empty;
    for (part.attributes) |a| try attrs.append(allocator, a);

    if (seen_eq) {
        const val = std.mem.trim(u8, value_buf.items, " \t\n\r");
        try attrs.append(allocator, .{
            .name = try allocator.dupe(u8, name),
            .value = try allocator.dupe(u8, val),
            .op = .equals,
        });
    } else {
        try attrs.append(allocator, .{
            .name = try allocator.dupe(u8, name),
            .op = .exists,
        });
    }
    part.attributes = try attrs.toOwnedSlice(allocator);
    spec.b += 1;
}
