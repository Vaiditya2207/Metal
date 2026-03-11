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

    pub fn sanitize(self: *Dimensions) void {
        const cap = 5000.0;
        self.content.x = @max(-cap, @min(cap, self.content.x));
        self.content.y = @max(-cap, @min(cap, self.content.y));
        self.content.width = @max(0, @min(cap, self.content.width));
        self.content.height = @max(0, @min(cap, self.content.height));
        
        self.padding.top = @max(0, @min(cap, self.padding.top));
        self.padding.bottom = @max(0, @min(cap, self.padding.bottom));
        self.padding.left = @max(0, @min(cap, self.padding.left));
        self.padding.right = @max(0, @min(cap, self.padding.right));
        
        self.border.top = @max(0, @min(cap, self.border.top));
        self.border.bottom = @max(0, @min(cap, self.border.bottom));
        self.border.left = @max(0, @min(cap, self.border.left));
        self.border.right = @max(0, @min(cap, self.border.right));
        
        self.margin.top = @max(-cap, @min(cap, self.margin.top));
        self.margin.bottom = @max(-cap, @min(cap, self.margin.bottom));
        self.margin.left = @max(-cap, @min(cap, self.margin.left));
        self.margin.right = @max(-cap, @min(cap, self.margin.right));
    }

    pub fn paddingBox(self: Dimensions) Rect {
        var d = self; d.sanitize();
        return .{
            .x = d.content.x - d.padding.left,
            .y = d.content.y - d.padding.top,
            .width = d.content.width + d.padding.left + d.padding.right,
            .height = d.content.height + d.padding.top + d.padding.bottom,
        };
    }

    pub fn borderBox(self: Dimensions) Rect {
        var d = self; d.sanitize();
        const p_box = d.paddingBox();
        return .{
            .x = p_box.x - d.border.left,
            .y = p_box.y - d.border.top,
            .width = p_box.width + d.border.left + d.border.right,
            .height = p_box.height + d.border.top + d.border.bottom,
        };
    }

    pub fn marginBox(self: Dimensions) Rect {
        var d = self; d.sanitize();
        const b_box = d.borderBox();
        return .{
            .x = b_box.x - d.margin.left,
            .y = b_box.y - d.margin.top,
            .width = b_box.width + d.margin.left + d.margin.right,
            .height = b_box.height + d.margin.top + d.margin.bottom,
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
    layout_box: *LayoutBox,
    x: f32,
    y: f32,
    width: f32,
    line_height: f32 = 0,
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

    pub fn calculateIntrinsicWidth(self: *LayoutBox) f32 {
        if (self.intrinsic_width > 0) return self.intrinsic_width;
        
        const tm = @import("text_measure.zig");
        
        if (self.styled_node) |sn| {
            if (sn.node.node_type == .text) {
                if (sn.node.data) |data| {
                   return tm.measureTextWidth(data, sn.style.font_size.value, sn.style.font_weight);
                }
            } else if (sn.node.tag == .input) {
                if (sn.node.getAttribute("value")) |val| {
                   // Input padding and borders should be accounted for in the caller if box-sizing is content-box,
                   // but intrinsic width provides the baseline text width.
                   return tm.measureTextWidth(val, sn.style.font_size.value, sn.style.font_weight);
                }
            }
        }
        
        var max_w: f32 = 0;
        var sum_inline_w: f32 = 0;
        
        var is_inline_flow = true;
        for (self.children.items) |child| {
            if (child.box_type != .inlineNode and child.box_type != .inlineBlockNode) {
                is_inline_flow = false;
                break;
            }
        }
        
        var is_flex_row = false;
        if (self.box_type == .flexNode) {
            if (self.styled_node) |sn| {
                if (sn.style.flex_direction == .row) is_flex_row = true;
            }
        }

        for (self.children.items) |child| {
            const w = child.calculateIntrinsicWidth();
            if (is_inline_flow or is_flex_row) {
                sum_inline_w += w;
            } else {
                max_w = @max(max_w, w);
            }
        }
        
        if (is_inline_flow or is_flex_row) return sum_inline_w;
        return max_w;
    }

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
                .inline_flex => .flexNode,
                .table => .tableNode,
                .table_row => .tableRowNode,
                .table_cell => .tableCellNode,
                .table_row_group => .blockNode, // Fallback
                .table_header_group => .blockNode, // Fallback
                .table_footer_group => .blockNode, // Fallback
                .inline_val => .inlineNode,
                .inline_block => .inlineBlockNode,
                .none => unreachable,
            };
            const root = try self.allocator.create(LayoutBox);
            root.* = LayoutBox.init(box_type, sn);
            
            // Set intrinsic size for replaced elements like <input> and <textarea>
            if (sn.node.node_type == .element) {
                if (sn.node.tag == .input or sn.node.tag == .textarea) {
                    root.intrinsic_height = sn.style.font_size.value * 1.2;
                    root.lock_content_width = true;
                    root.lock_content_height = true;
                } else if (sn.node.tag == .svg) {
                    root.intrinsic_width = 300.0;
                    root.intrinsic_height = 150.0;
                    if (sn.node.getAttribute("width")) |w| {
                        root.intrinsic_width = std.fmt.parseFloat(f32, w) catch 300.0;
                    }
                    if (sn.node.getAttribute("height")) |h| {
                        root.intrinsic_height = std.fmt.parseFloat(f32, h) catch 150.0;
                    }
                    root.lock_content_width = true;
                    root.lock_content_height = true;
                    root.svg_xml = sn.node.serialize(self.allocator) catch null;
                } else if (sn.node.tag == .img) {
                    // Default broken image fallback size
                    root.intrinsic_width = 20.0;
                    root.intrinsic_height = 20.0;
                    if (sn.node.getAttribute("width")) |w| {
                        root.intrinsic_width = std.fmt.parseFloat(f32, w) catch 20.0;
                    }
                    if (sn.node.getAttribute("height")) |h| {
                        root.intrinsic_height = std.fmt.parseFloat(f32, h) catch 20.0;
                    }
                    root.lock_content_width = true;
                    root.lock_content_height = true;
                }
            }
            
            errdefer {
                root.deinit(self.allocator);
                self.allocator.destroy(root);
            }

            for (sn.children) |child| {
                if (self.build(child, depth + 1)) |child_box| {
                    child_box.parent = root;
                    try root.children.append(self.allocator, child_box);
                } else |err| {
                    if (err == error.SkipNode) continue;
                    return err;
                }
            }

            if (root.box_type == .blockNode or root.box_type == .flexNode) {
                try self.wrapAnonymousBlocks(root);
            }

            return root;
        }

        fn wrapAnonymousBlocks(self: *@This(), parent: *LayoutBox) !void {
            var has_block = false;
            var has_naked_inline = false;
            var has_inline_level = false;
            for (parent.children.items) |child| {
                if (child.box_type == .blockNode or child.box_type == .flexNode or child.box_type == .tableNode) has_block = true;
                if (child.box_type == .inlineNode) {
                    has_naked_inline = true;
                    has_inline_level = true;
                }
                if (child.box_type == .inlineBlockNode) {
                    has_inline_level = true;
                }
            }

            if (parent.box_type == .flexNode) {
                if (!has_naked_inline) return;
            } else {
                if (!has_inline_level) return;
            }
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
                if (parent.children.items[i].box_type == .blockNode or parent.children.items[i].box_type == .flexNode) {
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
                    while (i < parent.children.items.len and parent.children.items[i].box_type != .blockNode and parent.children.items[i].box_type != .flexNode) {
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
