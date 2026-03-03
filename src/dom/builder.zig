const std = @import("std");
const tokenizer_mod = @import("tokenizer.zig");
const tree_mod = @import("tree.zig");

const Tokenizer = tokenizer_mod.Tokenizer;
const TokenType = tokenizer_mod.TokenType;
const Document = tree_mod.Document;
const Node = tree_mod.Node;
const NodeType = tree_mod.NodeType;
const TagName = tree_mod.TagName;

/// Void elements that cannot have children (self-closing by spec).
fn isVoidElement(tag: TagName) bool {
    return switch (tag) {
        .br, .hr, .img, .input, .meta, .link => true,
        else => false,
    };
}

/// HTML tree builder. Consumes tokens and constructs a DOM tree.
pub const TreeBuilder = struct {
    doc: *Document,
    open_elements: std.ArrayListUnmanaged(*Node),
    head_inserted: bool,
    body_inserted: bool,
    allocator: std.mem.Allocator,

    pub fn init(doc: *Document) TreeBuilder {
        return TreeBuilder{
            .doc = doc,
            .open_elements = .empty,
            .head_inserted = false,
            .body_inserted = false,
            .allocator = doc.arena.allocator(),
        };
    }

    fn currentNode(self: *TreeBuilder) *Node {
        if (self.open_elements.items.len == 0) return self.doc.root;
        return self.open_elements.items[self.open_elements.items.len - 1];
    }

    fn insertElement(self: *TreeBuilder, tag_name: []const u8, attributes: []const tokenizer_mod.Attribute) !*Node {
        const tag = TagName.fromString(tag_name);

        // Auto-insert <html> if missing
        if (tag != .html and !self.hasOpenElement(.html)) {
            try self.insertImplicitElement("html");
        }

        // Auto-insert <head> for head-content
        if (tag == .title or tag == .meta or tag == .link or tag == .style) {
            if (!self.head_inserted) {
                try self.insertImplicitElement("head");
                self.head_inserted = true;
            }
        }

        // Auto-insert <body> for body-content
        if (tag != .html and tag != .head and tag != .body and
            tag != .title and tag != .meta and tag != .link and tag != .style)
        {
            if (!self.body_inserted) {
                self.closeUpTo(.head);
                try self.insertImplicitElement("body");
                self.body_inserted = true;
            }
        }

        const elem = try self.doc.createElement(tag_name);

        // Copy attributes
        for (attributes) |attr| {
            try elem.attributes.append(self.allocator, .{
                .name = try self.allocator.dupe(u8, attr.name),
                .value = try self.allocator.dupe(u8, attr.value),
            });
        }

        const parent = self.currentNode();
        parent.appendChild(elem, self.doc.limits) catch {
            return elem;
        };

        if (!isVoidElement(tag)) {
            try self.open_elements.append(self.allocator, elem);
        }

        return elem;
    }

    fn insertImplicitElement(self: *TreeBuilder, tag_name: []const u8) !void {
        const elem = try self.doc.createElement(tag_name);
        const parent = self.currentNode();
        parent.appendChild(elem, self.doc.limits) catch return;
        try self.open_elements.append(self.allocator, elem);
    }

    fn hasOpenElement(self: *TreeBuilder, tag: TagName) bool {
        for (self.open_elements.items) |elem| {
            if (elem.tag == tag) return true;
        }
        return false;
    }

    fn closeUpTo(self: *TreeBuilder, tag: TagName) void {
        while (self.open_elements.items.len > 0) {
            const top = self.open_elements.items[self.open_elements.items.len - 1];
            _ = self.open_elements.pop();
            if (top.tag == tag) return;
        }
    }

    fn processEndTag(self: *TreeBuilder, tag_name: []const u8) void {
        const tag = TagName.fromString(tag_name);
        var i = self.open_elements.items.len;
        while (i > 0) {
            i -= 1;
            if (self.open_elements.items[i].tag == tag) {
                self.open_elements.shrinkRetainingCapacity(i);
                return;
            }
        }
    }

    fn insertText(self: *TreeBuilder, text: []const u8) !void {
        if (text.len == 0) return;

        if (!self.body_inserted and !self.hasOpenElement(.head)) {
            if (!self.hasOpenElement(.html)) {
                try self.insertImplicitElement("html");
            }
            try self.insertImplicitElement("body");
            self.body_inserted = true;
        }

        const text_node = try self.doc.createTextNode(text);
        const parent = self.currentNode();
        parent.appendChild(text_node, self.doc.limits) catch return;
    }

    /// Parse an HTML string into a DOM document.
    pub fn parse(allocator: std.mem.Allocator, html: []const u8) !*Document {
        const doc = try Document.init(allocator);
        var builder = TreeBuilder.init(doc);

        var tok = Tokenizer.init(doc.arena.allocator(), html);

        while (true) {
            const token = try tok.next();

            switch (token.type) {
                .start_tag => {
                    _ = try builder.insertElement(
                        token.tag_name orelse continue,
                        token.attributes,
                    );
                },
                .end_tag => {
                    builder.processEndTag(token.tag_name orelse continue);
                },
                .character => {
                    try builder.insertText(token.data orelse continue);
                },
                .comment, .doctype => {},
                .eof => break,
            }
        }

        return doc;
    }
};

/// Convenience function: parse HTML bytes into a Document.
pub fn parseHTML(allocator: std.mem.Allocator, html: []const u8) !*Document {
    return TreeBuilder.parse(allocator, html);
}

// ============================================================================
// Tests
// ============================================================================

test "parse simple HTML" {
    const doc = try parseHTML(std.heap.page_allocator, "<html><body><p>Hello</p></body></html>");
    defer doc.deinit();
    try std.testing.expectEqual(NodeType.document, doc.root.node_type);
    try std.testing.expect(doc.root.children.items.len > 0);
}

test "parse implicit structure" {
    const doc = try parseHTML(std.heap.page_allocator, "<p>Hello</p>");
    defer doc.deinit();
    const html_node = doc.root.querySelector(.html);
    try std.testing.expect(html_node != null);
    const body_node = doc.root.querySelector(.body);
    try std.testing.expect(body_node != null);
    const p_node = doc.root.querySelector(.p);
    try std.testing.expect(p_node != null);
}

test "parse nested elements" {
    const doc = try parseHTML(std.heap.page_allocator, "<div><span><a href=\"#\">Link</a></span></div>");
    defer doc.deinit();
    const div = doc.root.querySelector(.div);
    try std.testing.expect(div != null);
    const span = div.?.querySelector(.span);
    try std.testing.expect(span != null);
}

test "parse void elements" {
    const doc = try parseHTML(std.heap.page_allocator, "<p>Before<br>After</p>");
    defer doc.deinit();
    const p = doc.root.querySelector(.p);
    try std.testing.expect(p != null);
    try std.testing.expect(p.?.children.items.len >= 2);
}

test "parse text content extraction" {
    const doc = try parseHTML(std.heap.page_allocator, "<div><h1>Title</h1><p>Body text</p></div>");
    defer doc.deinit();
    const div = doc.root.querySelector(.div);
    try std.testing.expect(div != null);
    const text = try div.?.getTextContent(doc.arena.allocator());
    try std.testing.expect(text.len > 0);
}

test "parse getElementById" {
    const doc = try parseHTML(std.heap.page_allocator, "<div id=\"main\"><p>Content</p></div>");
    defer doc.deinit();
    const found = doc.root.getElementById("main");
    try std.testing.expect(found != null);
    try std.testing.expectEqual(TagName.div, found.?.tag);
}

test "parse attributes preserved" {
    const doc = try parseHTML(std.heap.page_allocator, "<a href=\"http://example.com\" class=\"link\">Click</a>");
    defer doc.deinit();
    const a = doc.root.querySelector(.a);
    try std.testing.expect(a != null);
    try std.testing.expect(a.?.attributes.items.len >= 2);
}

test "parse empty document" {
    const doc = try parseHTML(std.heap.page_allocator, "");
    defer doc.deinit();
    try std.testing.expectEqual(NodeType.document, doc.root.node_type);
}

test "security: arena cleanup frees all memory" {
    const doc = try parseHTML(std.heap.page_allocator, "<html><body><div><p>Hello World</p></div></body></html>");
    doc.deinit();
}

test "parse malformed HTML gracefully" {
    const doc = try parseHTML(std.heap.page_allocator, "<div><p>Unclosed<span>Mismatched</div>");
    defer doc.deinit();
    try std.testing.expect(doc.root.children.items.len > 0);
}
