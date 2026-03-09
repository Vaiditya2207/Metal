const std = @import("std");
const dom = @import("../dom/mod.zig");
const parser_mod = @import("parser.zig");
const selector_mod = @import("selector.zig");
const properties_mod = @import("properties.zig");

pub const StyledNode = struct {
    node: *const dom.Node,
    style: properties_mod.ComputedStyle,
    children: []const *StyledNode,
};

const MatchedDeclaration = struct {
    declaration: parser_mod.Declaration,
    specificity: selector_mod.Specificity,
    source_order: u32,
    is_inline: bool = false,
};

fn compareMatchedDeclarations(_: void, a: MatchedDeclaration, b: MatchedDeclaration) bool {
    // !important has highest precedence
    if (!a.declaration.is_important and b.declaration.is_important) return true;
    if (a.declaration.is_important and !b.declaration.is_important) return false;

    // inline styles override non-inline styles (unless overturned by !important above)
    if (!a.is_inline and b.is_inline) return true;
    if (a.is_inline and !b.is_inline) return false;

    const a_score = a.specificity.toScore();
    const b_score = b.specificity.toScore();
    if (a_score != b_score) return a_score < b_score;
    return a.source_order < b.source_order;
}

pub const StyleResolver = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) StyleResolver {
        return .{ .allocator = allocator };
    }

    pub fn resolve(self: *StyleResolver, root: *const dom.Node, stylesheets: []const parser_mod.Stylesheet) !?*StyledNode {
        return try self.resolveNode(root, null, stylesheets);
    }

    fn resolveNode(self: *StyleResolver, node: *const dom.Node, parent_style: ?*const properties_mod.ComputedStyle, stylesheets: []const parser_mod.Stylesheet) !?*StyledNode {
        var style = properties_mod.ComputedStyle{};

        if (parent_style) |ps| {
            style.color = ps.color;
            style.font_size = ps.font_size;
            style.font_family = ps.font_family;
            style.font_weight = ps.font_weight;
            
            // Inherit custom properties
            var it = ps.custom_properties.iterator();
            while (it.next()) |entry| {
                try style.custom_properties.put(self.allocator, try self.allocator.dupe(u8, entry.key_ptr.*), try self.allocator.dupe(u8, entry.value_ptr.*));
            }
        }

        const matched = try self.collectMatchingDeclarations(node, stylesheets);
        defer self.allocator.free(matched);

        // Pass 1: Collect custom properties
        for (matched) |m| {
            if (std.mem.startsWith(u8, m.declaration.property, "--")) {
                try style.applyProperty(m.declaration.property, m.declaration.value, self.allocator);
            }
        }

        // Pass 2: Substitute and apply all other properties
        for (matched) |m| {
            if (!std.mem.startsWith(u8, m.declaration.property, "--")) {
                const substituted = try self.substituteVariables(m.declaration.value, &style);
                defer self.allocator.free(substituted);
                try style.applyProperty(m.declaration.property, substituted, self.allocator);
            }
        }

        // Force hidden inputs to not display
        if (node.node_type == .element) {
            if (node.tag == .input) {
                if (node.getAttribute("type")) |t| {
                    if (std.mem.eql(u8, t, "hidden")) {
                        style.display = .none;
                    }
                }
            }
        }
        
        if (style.display == .none) return null;

        // Resolve font-size to absolute px values.
        // em/rem/% font-sizes are relative to the parent's computed font-size.
        const parent_fs: f32 = if (parent_style) |ps| ps.font_size.value else 16.0;
        switch (style.font_size.unit) {
            .em => {
                style.font_size = .{ .value = style.font_size.value * parent_fs, .unit = .px };
            },
            .rem => {
                // rem is relative to root font size (default 16px)
                style.font_size = .{ .value = style.font_size.value * 16.0, .unit = .px };
            },
            .percent => {
                style.font_size = .{ .value = (style.font_size.value / 100.0) * parent_fs, .unit = .px };
            },
            else => {},
        }

        var children_list = std.ArrayListUnmanaged(*StyledNode).empty;
        errdefer {
            for (children_list.items) |child| self.freeStyledNode(@constCast(child));
            children_list.deinit(self.allocator);
        }

        for (node.children.items) |child| {
            if (try self.resolveNode(child, &style, stylesheets)) |styled_child| {
                try children_list.append(self.allocator, styled_child);
            }
        }

        const sn = try self.allocator.create(StyledNode);
        sn.* = .{
            .node = node,
            .style = style,
            .children = try children_list.toOwnedSlice(self.allocator),
        };
        return sn;
    }

    fn substituteVariables(self: *StyleResolver, value: []const u8, style: *const properties_mod.ComputedStyle) ![]const u8 {
        return try self.substituteVariablesRecursive(value, style, 0);
    }

    fn substituteVariablesRecursive(self: *StyleResolver, value: []const u8, style: *const properties_mod.ComputedStyle, depth: usize) ![]const u8 {
        if (depth > 16) return try self.allocator.dupe(u8, "");
        if (std.mem.indexOf(u8, value, "var(") == null) {
            return try self.allocator.dupe(u8, value);
        }

        var result = std.ArrayListUnmanaged(u8){};
        defer result.deinit(self.allocator);

        var i: usize = 0;
        while (i < value.len) {
            if (std.mem.startsWith(u8, value[i..], "var(")) {
                const call_start = i;
                i += 4;
                const content_start = i;
                var paren_depth: usize = 1;
                while (i < value.len and paren_depth > 0) : (i += 1) {
                    if (value[i] == '(') paren_depth += 1;
                    if (value[i] == ')') paren_depth -= 1;
                }
                
                if (paren_depth == 0) {
                    const var_content = value[content_start .. i - 1];
                    var comma_idx: ?usize = null;
                    
                    // Find top-level comma for fallback
                    var search_depth: usize = 0;
                    for (var_content, 0..) |c, idx| {
                        if (c == '(') search_depth += 1;
                        if (c == ')') search_depth -= 1;
                        if (c == ',' and search_depth == 0) {
                            comma_idx = idx;
                            break;
                        }
                    }
                    
                    const var_name = std.mem.trim(u8, if (comma_idx) |idx| var_content[0..idx] else var_content, " \t\n\r");
                    const fallback = if (comma_idx) |idx| std.mem.trim(u8, var_content[idx + 1 ..], " \t\n\r") else null;
                    
                    if (style.custom_properties.get(var_name)) |resolved| {
                        // Variables themselves can contain var()
                        const sub_resolved = try self.substituteVariablesRecursive(resolved, style, depth + 1);
                        defer self.allocator.free(sub_resolved);
                        try result.appendSlice(self.allocator, sub_resolved);
                    } else if (fallback) |f| {
                        const sub_fallback = try self.substituteVariablesRecursive(f, style, depth + 1);
                        defer self.allocator.free(sub_fallback);
                        try result.appendSlice(self.allocator, sub_fallback);
                    }
                } else {
                    // Malformed var(), just append original
                    try result.appendSlice(self.allocator, value[call_start..i]);
                }
            } else {
                try result.append(self.allocator, value[i]);
                i += 1;
            }
        }

        return try result.toOwnedSlice(self.allocator);
    }

    fn collectMatchingDeclarations(self: *StyleResolver, node: *const dom.Node, stylesheets: []const parser_mod.Stylesheet) ![]MatchedDeclaration {
        var matched = std.ArrayListUnmanaged(MatchedDeclaration).empty;
        errdefer matched.deinit(self.allocator);

        var order: u32 = 0;
        for (stylesheets) |sheet| {
            for (sheet.rules) |rule| {
                for (rule.selectors) |sel| {
                    if (sel.matchesNode(node)) {
                        for (rule.declarations) |decl| {
                            try matched.append(self.allocator, .{
                                .declaration = decl,
                                .specificity = sel.specificity,
                                .source_order = order,
                            });
                        }
                    }
                }
                order += 1;
            }
        }
        
        // Add inline styles as MatchedDeclarations
        if (node.node_type == .element) {
            for (node.attributes.items) |attr| {
                if (std.mem.eql(u8, attr.name, "style")) {
                    const inline_decls = try parser_mod.Parser.parseInlineStyle(self.allocator, attr.value);
                    defer self.allocator.free(inline_decls);
                    for (inline_decls) |decl| {
                        try matched.append(self.allocator, .{
                            .declaration = decl,
                            .specificity = selector_mod.Specificity{},
                            .source_order = order,
                            .is_inline = true,
                        });
                        order += 1;
                    }
                }
            }
        }

        std.mem.sort(MatchedDeclaration, matched.items, {}, compareMatchedDeclarations);
        return try matched.toOwnedSlice(self.allocator);
    }

    pub fn freeStyledNode(self: *StyleResolver, sn: *StyledNode) void {
        for (sn.children) |child| {
            self.freeStyledNode(@constCast(child));
        }
        sn.style.deinit(self.allocator);
        self.allocator.free(sn.children);
        self.allocator.destroy(sn);
    }
};
