const std = @import("std");
const dom_node = @import("../dom/node.zig");
const css_tokenizer = @import("tokenizer.zig");
const config = @import("../config.zig");

pub const SelectorPart = struct {
    tag: ?[]const u8 = null,
    id: ?[]const u8 = null,
    classes: []const []const u8 = &.{},
    universal: bool = false,
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

        const max_parts = config.getConfig().css.max_selector_parts;

        while (components.items.len < max_parts) {
            const token = try tokenizer.next();
            if (token.type == .eof) break;

            if (token.type == .whitespace) {
                if (pending_combinator == .none) {
                    pending_combinator = .descendant;
                }
                continue;
            }

            if (token.type == .delim and std.mem.eql(u8, token.value, ">")) {
                pending_combinator = .child;
                continue;
            }

            if (token.type == .delim and std.mem.eql(u8, token.value, ",")) {
                break;
            }

            var part = SelectorPart{};
            var t = token;
            while (true) {
                if (t.type == .ident) {
                    part.tag = try allocator.dupe(u8, t.value);
                    spec_val.c += 1;
                } else if (t.type == .hash) {
                    const id_val = if (t.value[0] == '#') t.value[1..] else t.value;
                    part.id = try allocator.dupe(u8, id_val);
                    spec_val.a += 1;
                } else if (t.type == .delim and std.mem.eql(u8, t.value, ".")) {
                    const next_t = try tokenizer.next();
                    if (next_t.type == .ident) {
                        var classes: std.ArrayListUnmanaged([]const u8) = .empty;
                        for (part.classes) |c| try classes.append(allocator, c);
                        try classes.append(allocator, try allocator.dupe(u8, next_t.value));
                        part.classes = try classes.toOwnedSlice(allocator);
                        spec_val.b += 1;
                    }
                } else if (t.type == .delim and std.mem.eql(u8, t.value, "*")) {
                    part.universal = true;
                } else if (t.type == .colon) {
                    // Pseudo-class (e.g. :link, :visited, :hover)
                    // Skip the pseudo-class name token
                    const pseudo_t = try tokenizer.next();
                    _ = pseudo_t; // ignore the pseudo-class name
                    // Don't break — continue parsing additional parts
                }

                const next_t = try tokenizer.next();
                if (next_t.type == .eof or next_t.type == .whitespace or (next_t.type == .delim and (std.mem.eql(u8, next_t.value, ">") or std.mem.eql(u8, next_t.value, ",")))) {
                    tokenizer.pos -= next_t.value.len;
                    break;
                }
                t = next_t;
            }
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

        return true;
    }
};
