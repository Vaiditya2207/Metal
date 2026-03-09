const std = @import("std");
const tag_mod = @import("tag.zig");
const event_target_mod = @import("event_target.zig");

pub const TagName = tag_mod.TagName;

/// DOM Node types.
pub const NodeType = enum {
    document,
    element,
    text,
    comment,
    doctype,
};

/// A single attribute on an element.
pub const DomAttribute = struct {
    name: []const u8,
    value: []const u8,
};

/// A DOM node. All memory is owned by the document's arena.
pub const Node = struct {
    node_type: NodeType,
    tag: TagName = .unknown,
    tag_name_str: ?[]const u8 = null,
    attributes: std.ArrayListUnmanaged(DomAttribute),
    data: ?[]const u8 = null,
    parent: ?*Node = null,
    children: std.ArrayListUnmanaged(*Node),
    depth: u16 = 0,
    allocator: std.mem.Allocator,
    event_target: event_target_mod.EventTarget = .{},

    pub fn init(allocator: std.mem.Allocator, node_type: NodeType) Node {
        return Node{
            .node_type = node_type,
            .attributes = .empty,
            .children = .empty,
            .allocator = allocator,
        };
    }

    /// Append a child node. Enforces depth and children limits.
    pub fn appendChild(self: *Node, child: *Node, limits: anytype) !void {
        if (self.children.items.len >= limits.max_children) return error.TooManyChildren;
        if (self.depth + 1 >= limits.max_depth) return error.TreeTooDeep;

        child.parent = self;
        child.depth = self.depth + 1;
        try self.children.append(self.allocator, child);
    }

    /// Remove a child node by pointer.
    pub fn removeChild(self: *Node, child: *Node) void {
        for (self.children.items, 0..) |c, i| {
            if (c == child) {
                _ = self.children.orderedRemove(i);
                child.parent = null;
                return;
            }
        }
    }

    /// Insert new_child before ref_child. Appends if ref_child is null or not found.
    pub fn insertBefore(self: *Node, new_child: *Node, ref_child: ?*Node, limits: anytype) !void {
        if (self.children.items.len >= limits.max_children) return error.TooManyChildren;
        if (self.depth + 1 >= limits.max_depth) return error.TreeTooDeep;
        if (new_child.parent) |old_parent| {
            old_parent.removeChild(new_child);
        }
        new_child.parent = self;
        new_child.depth = self.depth + 1;
        if (ref_child) |ref| {
            for (self.children.items, 0..) |c, i| {
                if (c == ref) {
                    try self.children.insert(self.allocator, i, new_child);
                    return;
                }
            }
        }
        try self.children.append(self.allocator, new_child);
    }

    /// Replace old_child with new_child. Returns old_child, or null if not found.
    pub fn replaceChild(self: *Node, new_child: *Node, old_child: *Node) ?*Node {
        if (new_child.parent) |old_parent| {
            if (old_parent != self) {
                old_parent.removeChild(new_child);
            }
        }
        for (self.children.items, 0..) |c, i| {
            if (c == old_child) {
                self.children.items[i] = new_child;
                new_child.parent = self;
                new_child.depth = self.depth + 1;
                old_child.parent = null;
                return old_child;
            }
        }
        return null;
    }

    /// Find the first descendant element with the given id attribute.
    pub fn getElementById(self: *Node, id: []const u8) ?*Node {
        if (self.node_type == .element) {
            for (self.attributes.items) |attr| {
                if (std.mem.eql(u8, attr.name, "id") and std.mem.eql(u8, attr.value, id)) return self;
            }
        }
        for (self.children.items) |child| if (child.getElementById(id)) |found| return found;
        return null;
    }

    /// Find the first descendant element matching a tag name.
    pub fn querySelector(self: *Node, tag: TagName) ?*Node {
        if (self.node_type == .element and self.tag == tag) return self;
        for (self.children.items) |child| if (child.querySelector(tag)) |found| return found;
        return null;
    }

    /// Get the text content of this node and all descendants.
    pub fn getTextContent(self: *const Node, allocator: std.mem.Allocator) ![]const u8 {
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        try self.collectText(allocator, &buf);
        return try buf.toOwnedSlice(allocator);
    }

    /// Set text content, replacing all children with a single text node.
    pub fn setTextContent(self: *Node, text: []const u8, limits: anytype) !void {
        while (self.children.items.len > 0) {
            self.children.items[self.children.items.len - 1].parent = null;
            _ = self.children.pop();
        }
        if (text.len == 0) return;
        const text_node = try self.allocator.create(Node);
        text_node.* = Node.init(self.allocator, .text);
        text_node.data = try self.allocator.dupe(u8, text);
        try self.appendChild(text_node, limits);
    }

    fn collectText(self: *const Node, alloc: std.mem.Allocator, buf: *std.ArrayListUnmanaged(u8)) !void {
        if (self.node_type == .text) if (self.data) |d| try buf.appendSlice(alloc, d);
        for (self.children.items) |child| try child.collectText(alloc, buf);
    }

    pub fn getAttribute(self: *const Node, name: []const u8) ?[]const u8 {
        for (self.attributes.items) |attr| {
            if (std.mem.eql(u8, attr.name, name)) {
                return attr.value;
            }
        }
        return null;
    }

    /// Set an attribute value, updating in place if it already exists.
    pub fn setAttribute(self: *Node, name: []const u8, value: []const u8) !void {
        for (self.attributes.items) |*attr| {
            if (std.mem.eql(u8, attr.name, name)) {
                attr.value = try self.allocator.dupe(u8, value);
                return;
            }
        }
        try self.attributes.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, name),
            .value = try self.allocator.dupe(u8, value),
        });
    }

    /// Remove an attribute by name. No-op if the attribute does not exist.
    pub fn removeAttribute(self: *Node, name: []const u8) void {
        var i: usize = 0;
        while (i < self.attributes.items.len) {
            if (std.mem.eql(u8, self.attributes.items[i].name, name)) {
                _ = self.attributes.orderedRemove(i);
                return;
            }
            i += 1;
        }
    }

    /// Return whether this node has an attribute with the given name.
    pub fn hasAttribute(self: *const Node, name: []const u8) bool {
        return self.getAttribute(name) != null;
    }

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        self.attributes.deinit(allocator);
        for (self.children.items) |child| child.deinit(allocator);
        self.children.deinit(allocator);
    }

    /// Serialize this node and its children to an XML/HTML string.
    pub fn serialize(self: *const Node, allocator: std.mem.Allocator) ![]const u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        defer buf.deinit(allocator);
        try self.serializeToBuf(allocator, &buf);
        return try buf.toOwnedSlice(allocator);
    }

    fn serializeToBuf(self: *const Node, allocator: std.mem.Allocator, buf: *std.ArrayListUnmanaged(u8)) !void {
        switch (self.node_type) {
            .text => {
                if (self.data) |d| try buf.appendSlice(allocator, d);
            },
            .comment => {
                try buf.appendSlice(allocator, "<!--");
                if (self.data) |d| try buf.appendSlice(allocator, d);
                try buf.appendSlice(allocator, "-->");
            },
            .doctype => {
                try buf.appendSlice(allocator, "<!DOCTYPE ");
                if (self.data) |d| try buf.appendSlice(allocator, d);
                try buf.appendSlice(allocator, ">");
            },
            .element => {
                const tag = self.tag_name_str orelse "unknown";
                try buf.appendSlice(allocator, "<");
                try buf.appendSlice(allocator, tag);
                for (self.attributes.items) |attr| {
                    try buf.appendSlice(allocator, " ");
                    try buf.appendSlice(allocator, attr.name);
                    try buf.appendSlice(allocator, "=\"");
                    try buf.appendSlice(allocator, attr.value);
                    try buf.appendSlice(allocator, "\"");
                }
                
                if (self.children.items.len == 0 and tag_mod.TagName.fromString(tag).isVoid()) {
                    try buf.appendSlice(allocator, "/>");
                } else {
                    try buf.appendSlice(allocator, ">");
                    for (self.children.items) |child| {
                        try child.serializeToBuf(allocator, buf);
                    }
                    try buf.appendSlice(allocator, "</");
                    try buf.appendSlice(allocator, tag);
                    try buf.appendSlice(allocator, ">");
                }
            },
            .document => {
                for (self.children.items) |child| {
                    try child.serializeToBuf(allocator, buf);
                }
            },
        }
    }
};
