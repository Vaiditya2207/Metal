const std = @import("std");
const tag_mod = @import("tag.zig");

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

    /// Find the first descendant element with the given id attribute.
    pub fn getElementById(self: *Node, id: []const u8) ?*Node {
        if (self.node_type == .element) {
            for (self.attributes.items) |attr| {
                if (std.mem.eql(u8, attr.name, "id") and std.mem.eql(u8, attr.value, id)) {
                    return self;
                }
            }
        }
        for (self.children.items) |child| {
            if (child.getElementById(id)) |found| return found;
        }
        return null;
    }

    /// Find the first descendant element matching a tag name.
    pub fn querySelector(self: *Node, tag: TagName) ?*Node {
        if (self.node_type == .element and self.tag == tag) {
            return self;
        }
        for (self.children.items) |child| {
            if (child.querySelector(tag)) |found| return found;
        }
        return null;
    }

    /// Get the text content of this node and all descendants.
    pub fn getTextContent(self: *const Node, allocator: std.mem.Allocator) ![]const u8 {
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        try self.collectText(allocator, &buf);
        return try buf.toOwnedSlice(allocator);
    }

    fn collectText(self: *const Node, allocator: std.mem.Allocator, buf: *std.ArrayListUnmanaged(u8)) !void {
        if (self.node_type == .text) {
            if (self.data) |d| {
                try buf.appendSlice(allocator, d);
            }
        }
        for (self.children.items) |child| {
            try child.collectText(allocator, buf);
        }
    }
};
