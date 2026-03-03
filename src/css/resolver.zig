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
};

fn compareMatchedDeclarations(_: void, a: MatchedDeclaration, b: MatchedDeclaration) bool {
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

    pub fn resolve(self: *StyleResolver, root: *const dom.Node, stylesheets: []const parser_mod.Stylesheet) !*StyledNode {
        return try self.resolveNode(root, null, stylesheets);
    }

    fn resolveNode(self: *StyleResolver, node: *const dom.Node, parent_style: ?*const properties_mod.ComputedStyle, stylesheets: []const parser_mod.Stylesheet) !*StyledNode {
        var style = properties_mod.ComputedStyle{};

        if (parent_style) |ps| {
            style.color = ps.color;
            style.font_size = ps.font_size;
            style.font_family = ps.font_family;
            style.font_weight = ps.font_weight;
        }

        const matched = try self.collectMatchingDeclarations(node, stylesheets);
        defer self.allocator.free(matched);

        for (matched) |m| {
            try style.applyProperty(m.declaration.property, m.declaration.value, self.allocator);
        }

        if (node.node_type == .element) {
            for (node.attributes.items) |attr| {
                if (std.mem.eql(u8, attr.name, "style")) {
                    const inline_decls = try parser_mod.Parser.parseInlineStyle(self.allocator, attr.value);
                    defer self.allocator.free(inline_decls);
                    for (inline_decls) |decl| {
                        try style.applyProperty(decl.property, decl.value, self.allocator);
                    }
                }
            }
        }

        var children_list = std.ArrayListUnmanaged(*StyledNode).empty;
        errdefer {
            for (children_list.items) |child| self.freeStyledNode(@constCast(child));
            children_list.deinit(self.allocator);
        }

        for (node.children.items) |child| {
            const styled_child = try self.resolveNode(child, &style, stylesheets);
            try children_list.append(self.allocator, styled_child);
        }

        const sn = try self.allocator.create(StyledNode);
        sn.* = .{
            .node = node,
            .style = style,
            .children = try children_list.toOwnedSlice(self.allocator),
        };
        return sn;
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

        std.mem.sort(MatchedDeclaration, matched.items, {}, compareMatchedDeclarations);
        return try matched.toOwnedSlice(self.allocator);
    }

    pub fn freeStyledNode(self: *StyleResolver, sn: *StyledNode) void {
        for (sn.children) |child| {
            self.freeStyledNode(@constCast(child));
        }
        self.allocator.free(sn.children);
        self.allocator.destroy(sn);
    }
};
