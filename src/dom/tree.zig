const std = @import("std");
const config = @import("../config.zig");

/// Known HTML tag names for fast comparison.
pub const TagName = enum {
    html, head, body, title, meta, link, style, script,
    div, span, p, a, img,
    h1, h2, h3, h4, h5, h6,
    ul, ol, li,
    table, tr, td, th, thead, tbody,
    form, input, button, textarea, select, option,
    br, hr,
    nav, header, footer, main, section, article, aside,
    strong, em, code, pre, blockquote,
    unknown,

    pub fn fromString(name: []const u8) TagName {
        const map = std.StaticStringMap(TagName).initComptime(.{
            .{ "html", .html }, .{ "head", .head }, .{ "body", .body },
            .{ "title", .title }, .{ "meta", .meta }, .{ "link", .link },
            .{ "style", .style }, .{ "script", .script },
            .{ "div", .div }, .{ "span", .span }, .{ "p", .p },
            .{ "a", .a }, .{ "img", .img },
            .{ "h1", .h1 }, .{ "h2", .h2 }, .{ "h3", .h3 },
            .{ "h4", .h4 }, .{ "h5", .h5 }, .{ "h6", .h6 },
            .{ "ul", .ul }, .{ "ol", .ol }, .{ "li", .li },
            .{ "table", .table }, .{ "tr", .tr }, .{ "td", .td },
            .{ "th", .th }, .{ "thead", .thead }, .{ "tbody", .tbody },
            .{ "form", .form }, .{ "input", .input }, .{ "button", .button },
            .{ "textarea", .textarea }, .{ "select", .select }, .{ "option", .option },
            .{ "br", .br }, .{ "hr", .hr },
            .{ "nav", .nav }, .{ "header", .header }, .{ "footer", .footer },
            .{ "main", .main }, .{ "section", .section }, .{ "article", .article },
            .{ "aside", .aside }, .{ "strong", .strong }, .{ "em", .em },
            .{ "code", .code }, .{ "pre", .pre }, .{ "blockquote", .blockquote },
        });
        return map.get(name) orelse .unknown;
    }
};

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
    pub fn appendChild(self: *Node, child: *Node, limits: Limits) !void {
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

/// Security and size limits for DOM operations.
pub const Limits = struct {
    max_depth: u16,
    max_children: u32,
    max_total_nodes: u32,

    pub fn fromConfig() Limits {
        const cfg = config.getConfig();
        return Limits{
            .max_depth = cfg.parser.max_tree_depth,
            .max_children = cfg.parser.max_children_per_node,
            .max_total_nodes = cfg.parser.max_total_nodes,
        };
    }
};

/// A parsed HTML document. Owns its arena allocator.
pub const Document = struct {
    arena: std.heap.ArenaAllocator,
    root: *Node,
    node_count: u32,
    limits: Limits,

    pub fn init(backing_allocator: std.mem.Allocator) !*Document {
        var arena = std.heap.ArenaAllocator.init(backing_allocator);

        // Allocate Document on the heap inside the arena.
        // We must move the arena into the Document first, then use
        // the Document's own stable allocator for all subsequent allocations.
        const doc = try arena.allocator().create(Document);
        doc.* = Document{
            .arena = arena,
            .root = undefined,
            .node_count = 0,
            .limits = Limits.fromConfig(),
        };

        // Now get the stable allocator from the heap-allocated arena
        const stable_alloc = doc.arena.allocator();
        const root = try stable_alloc.create(Node);
        root.* = Node.init(stable_alloc, .document);
        doc.root = root;
        doc.node_count = 1;

        return doc;
    }

    /// Allocate a new node within this document's arena.
    pub fn createNode(self: *Document, node_type: NodeType) !*Node {
        if (self.node_count >= self.limits.max_total_nodes) return error.TooManyNodes;
        const node = try self.arena.allocator().create(Node);
        node.* = Node.init(self.arena.allocator(), node_type);
        self.node_count += 1;
        return node;
    }

    /// Create an element node with the given tag.
    pub fn createElement(self: *Document, tag_name: []const u8) !*Node {
        const node = try self.createNode(.element);
        node.tag = TagName.fromString(tag_name);
        node.tag_name_str = try self.arena.allocator().dupe(u8, tag_name);
        return node;
    }

    /// Create a text node.
    pub fn createTextNode(self: *Document, text: []const u8) !*Node {
        const node = try self.createNode(.text);
        node.data = try self.arena.allocator().dupe(u8, text);
        return node;
    }

    /// Destroy the document and free all memory in O(1).
    pub fn deinit(self: *Document) void {
        self.arena.deinit();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "create document" {
    const doc = try Document.init(std.heap.page_allocator);
    defer doc.deinit();
    try std.testing.expectEqual(NodeType.document, doc.root.node_type);
}

test "create element" {
    const doc = try Document.init(std.heap.page_allocator);
    defer doc.deinit();
    const div = try doc.createElement("div");
    try std.testing.expectEqual(TagName.div, div.tag);
}

test "appendChild and relationships" {
    const doc = try Document.init(std.heap.page_allocator);
    defer doc.deinit();
    const body = try doc.createElement("body");
    try doc.root.appendChild(body, doc.limits);
    try std.testing.expectEqual(@as(usize, 1), doc.root.children.items.len);
    try std.testing.expect(body.parent == doc.root);
    try std.testing.expectEqual(@as(u16, 1), body.depth);
}

test "removeChild" {
    const doc = try Document.init(std.heap.page_allocator);
    defer doc.deinit();
    const body = try doc.createElement("body");
    try doc.root.appendChild(body, doc.limits);
    doc.root.removeChild(body);
    try std.testing.expectEqual(@as(usize, 0), doc.root.children.items.len);
}

test "getElementById" {
    const doc = try Document.init(std.heap.page_allocator);
    defer doc.deinit();
    const div = try doc.createElement("div");
    try div.attributes.append(doc.arena.allocator(), .{ .name = "id", .value = "main" });
    try doc.root.appendChild(div, doc.limits);
    const found = doc.root.getElementById("main");
    try std.testing.expect(found != null);
    try std.testing.expectEqual(TagName.div, found.?.tag);
}

test "querySelector by tag" {
    const doc = try Document.init(std.heap.page_allocator);
    defer doc.deinit();
    const body = try doc.createElement("body");
    try doc.root.appendChild(body, doc.limits);
    const p = try doc.createElement("p");
    try body.appendChild(p, doc.limits);
    const found = doc.root.querySelector(.p);
    try std.testing.expect(found != null);
}

test "getTextContent" {
    const doc = try Document.init(std.heap.page_allocator);
    defer doc.deinit();
    const p = try doc.createElement("p");
    try doc.root.appendChild(p, doc.limits);
    const text = try doc.createTextNode("Hello World");
    try p.appendChild(text, doc.limits);
    const content = try p.getTextContent(doc.arena.allocator());
    try std.testing.expectEqualStrings("Hello World", content);
}

test "node count tracking" {
    const doc = try Document.init(std.heap.page_allocator);
    defer doc.deinit();
    try std.testing.expect(doc.node_count == 1);
    _ = try doc.createElement("div");
    try std.testing.expect(doc.node_count == 2);
}
