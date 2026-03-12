const std = @import("std");
const resolver = @import("../css/resolver.zig");
const config = @import("../config.zig");

pub const Rect = struct {
    x: f32 = 0,
    y: f32 = 0,
    width: f32 = 0,
    height: f32 = 0,
};

pub const EdgeSizes = struct {
    top: f32 = 0,
    right: f32 = 0,
    bottom: f32 = 0,
    left: f32 = 0,
};

pub const Dimensions = struct {
    content: Rect = .{},
    padding: EdgeSizes = .{},
    border: EdgeSizes = .{},
    margin: EdgeSizes = .{},

    pub fn paddingBox(self: Dimensions) Rect {
        return .{
            .x = self.content.x - self.padding.left,
            .y = self.content.y - self.padding.top,
            .width = self.content.width + self.padding.left + self.padding.right,
            .height = self.content.height + self.padding.top + self.padding.bottom,
        };
    }

    pub fn borderBox(self: Dimensions) Rect {
        const p_box = self.paddingBox();
        return .{
            .x = p_box.x - self.border.left,
            .y = p_box.y - self.border.top,
            .width = p_box.width + self.border.left + self.border.right,
            .height = p_box.height + self.border.top + self.border.bottom,
        };
    }

    pub fn marginBox(self: Dimensions) Rect {
        const b_box = self.borderBox();
        return .{
            .x = b_box.x - self.margin.left,
            .y = b_box.y - self.margin.top,
            .width = b_box.width + self.margin.left + self.margin.right,
            .height = b_box.height + self.margin.top + self.margin.bottom,
        };
    }
};

pub const BoxType = enum {
    blockNode,
    inlineNode,
    inlineBlockNode,
    flexNode,
    tableNode,
    tableRowNode,
    tableCellNode,
    anonymousBlock,
};

pub const TextRun = struct {
    text: []const u8,
    styled_node: *const resolver.StyledNode,
    x: f32,
    y: f32,
    width: f32,
};

pub const LayoutBox = struct {
    box_type: BoxType,
    dimensions: Dimensions = .{},
    children: std.ArrayListUnmanaged(*LayoutBox) = .{},
    text_runs: std.ArrayListUnmanaged(TextRun) = .{},
    styled_node: ?*const resolver.StyledNode = null,
    parent: ?*LayoutBox = null,
    background_texture: ?*anyopaque = null,
    background_intrinsic_width: f32 = 0,
    background_intrinsic_height: f32 = 0,
    image_texture: ?*anyopaque = null,
    svg_xml: ?[]const u8 = null,
    intrinsic_width: f32 = 0,
    intrinsic_height: f32 = 0,
    lock_content_width: bool = false,
    lock_content_height: bool = false,

    pub fn init(box_type: BoxType, styled_node: ?*const resolver.StyledNode) LayoutBox {
        return .{
            .box_type = box_type,
            .styled_node = styled_node,
        };
    }

    pub fn deinit(self: *LayoutBox, allocator: std.mem.Allocator) void {
        for (self.children.items) |child| {
            child.deinit(allocator);
            allocator.destroy(child);
        }
        self.children.deinit(allocator);
        self.text_runs.deinit(allocator);
        if (self.svg_xml) |xml| allocator.free(xml);
    }
};

pub fn buildLayoutTree(allocator: std.mem.Allocator, styled_node: *const resolver.StyledNode) !*LayoutBox {
    const State = struct {
        allocator: std.mem.Allocator,
        node_count: u32 = 0,
        max_nodes: u32,
        max_depth: u16,

        fn build(self: *@This(), sn: *const resolver.StyledNode, depth: u16) !*LayoutBox {
            if (depth > self.max_depth) return error.LayoutDepthExceeded;
            if (self.node_count >= self.max_nodes) return error.LayoutMaxNodesExceeded;
            self.node_count += 1;
            if (sn.style.display == .none) return error.SkipNode;

            // Skip whitespace-only text nodes — they should not create layout boxes.
            // Without this, newlines between HTML tags create anonymous blocks
            // that each take up one line-height (19.2px) of vertical space.
            if (sn.node.node_type == .text) {
                if (sn.node.data) |data| {
                    const trimmed = std.mem.trim(u8, data, " \t\n\r");
                    if (trimmed.len == 0) return error.SkipNode;
                } else {
                    return error.SkipNode;
                }
            }

            const box_type: BoxType = switch (sn.style.display) {
                .block => .blockNode,
                .flex => .flexNode,
                .table => .tableNode,
                .table_row => .tableRowNode,
                .table_cell => .tableCellNode,
                .inline_val => .inlineNode,
                .inline_block => .inlineBlockNode,
                .none => unreachable,
            };
            const root = try self.allocator.create(LayoutBox);
            root.* = LayoutBox.init(box_type, sn);

            // Set intrinsic size for replaced elements like <input> and <textarea>
            if (sn.node.node_type == .element) {
                if (sn.node.tag == .input or sn.node.tag == .textarea) {
                    root.intrinsic_width = 140.0;
                    root.intrinsic_height = sn.style.font_size.value * 1.2;
                } else if (sn.node.tag == .svg) {
                    root.intrinsic_width = 300.0;
                    root.intrinsic_height = 150.0;
                    var has_explicit_width = false;
                    var has_explicit_height = false;
                    if (sn.node.getAttribute("width")) |w| {
                        root.intrinsic_width = std.fmt.parseFloat(f32, w) catch 300.0;
                        has_explicit_width = true;
                    }
                    if (sn.node.getAttribute("height")) |h| {
                        root.intrinsic_height = std.fmt.parseFloat(f32, h) catch 150.0;
                        has_explicit_height = true;
                    }
                    // If no explicit width/height, try viewBox
                    if (!has_explicit_width and !has_explicit_height) {
                        if (sn.node.getAttribute("viewBox") orelse sn.node.getAttribute("viewbox")) |vb| {
                            var iter = std.mem.tokenizeAny(u8, vb, " ,");
                            _ = iter.next(); // skip minX
                            _ = iter.next(); // skip minY
                            if (iter.next()) |vb_w| {
                                root.intrinsic_width = std.fmt.parseFloat(f32, vb_w) catch 300.0;
                            }
                            if (iter.next()) |vb_h| {
                                root.intrinsic_height = std.fmt.parseFloat(f32, vb_h) catch 150.0;
                            }
                        }
                    }
                    root.svg_xml = sn.node.serialize(self.allocator) catch null;
                }
            }

            errdefer {
                root.deinit(self.allocator);
                self.allocator.destroy(root);
            }

            // SVG elements are rendered as opaque replaced elements via svg_xml.
            // Skip building layout boxes for SVG children (path, circle, etc.)
            // which would create zero-size ghost boxes in the layout tree.
            const skip_children = sn.node.node_type == .element and sn.node.tag == .svg;
            if (!skip_children) {
                for (sn.children) |child| {
                    if (self.build(child, depth + 1)) |child_box| {
                        child_box.parent = root;
                        try root.children.append(self.allocator, child_box);
                    } else |err| {
                        if (err == error.SkipNode) continue;
                        return err;
                    }
                }
            }

            if (root.box_type == .blockNode or root.box_type == .flexNode or root.box_type == .inlineBlockNode) {
                try self.wrapAnonymousBlocks(root);
            }

            return root;
        }

        fn wrapAnonymousBlocks(self: *@This(), parent: *LayoutBox) !void {
            const is_flex = parent.box_type == .flexNode;
            var has_block = false;
            var has_inline = false;
            for (parent.children.items) |child| {
                if (child.box_type == .blockNode or child.box_type == .flexNode) has_block = true;
                // In flex containers, inline-block children are flex items (block-level)
                if (is_flex and child.box_type == .inlineBlockNode) {
                    has_block = true;
                } else if (child.box_type == .inlineNode or child.box_type == .inlineBlockNode or child.box_type == .anonymousBlock) {
                    has_inline = true;
                }
            }

            if (!has_inline) return;
            if (!has_block) {
                const anon = try self.allocator.create(LayoutBox);
                anon.* = LayoutBox.init(.anonymousBlock, null);
                errdefer {
                    anon.deinit(self.allocator);
                    self.allocator.destroy(anon);
                }
                for (parent.children.items) |child| {
                    child.parent = anon;
                }
                try anon.children.appendSlice(self.allocator, parent.children.items);

                parent.children.clearRetainingCapacity();
                try parent.children.append(self.allocator, anon);
                anon.parent = parent;
                return;
            }

            var new_children = std.ArrayListUnmanaged(*LayoutBox).empty;
            errdefer {
                for (new_children.items) |c| {
                    c.deinit(self.allocator);
                    self.allocator.destroy(c);
                }
                new_children.deinit(self.allocator);
            }

            var i: usize = 0;
            while (i < parent.children.items.len) {
                const child_type = parent.children.items[i].box_type;
                const is_block_level = child_type == .blockNode or child_type == .flexNode or
                    (is_flex and child_type == .inlineBlockNode);
                if (is_block_level) {
                    try new_children.append(self.allocator, parent.children.items[i]);
                    i += 1;
                } else {
                    const anon = try self.allocator.create(LayoutBox);
                    anon.* = LayoutBox.init(.anonymousBlock, null);
                    anon.parent = parent;
                    errdefer {
                        anon.deinit(self.allocator);
                        self.allocator.destroy(anon);
                    }
                    while (i < parent.children.items.len) {
                        const inner_type = parent.children.items[i].box_type;
                        const inner_is_block = inner_type == .blockNode or inner_type == .flexNode or
                            (is_flex and inner_type == .inlineBlockNode);
                        if (inner_is_block) break;
                        const child = parent.children.items[i];
                        child.parent = anon;
                        try anon.children.append(self.allocator, child);
                        i += 1;
                    }
                    try new_children.append(self.allocator, anon);
                }
            }
            parent.children.deinit(self.allocator);
            parent.children = new_children;
        }
    };
    const cfg = config.getConfig();
    var state = State{
        .allocator = allocator,
        .max_nodes = cfg.layout.max_layout_nodes,
        .max_depth = cfg.layout.max_layout_depth,
    };
    return state.build(styled_node, 0) catch |err| {
        if (err == error.SkipNode) return error.RootNodeSkipped;
        return err;
    };
}
