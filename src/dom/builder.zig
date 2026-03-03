const std = @import("std");
const tokenizer_mod = @import("tokenizer.zig");
const document_mod = @import("document.zig");
const node_mod = @import("node.zig");
const tag_mod = @import("tag.zig");

const Tokenizer = tokenizer_mod.Tokenizer;
const TokenType = tokenizer_mod.TokenType;
const Document = document_mod.Document;
const Node = node_mod.Node;
const NodeType = node_mod.NodeType;
const TagName = tag_mod.TagName;

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

        if (tag != .html and !self.hasOpenElement(.html)) {
            try self.insertImplicitElement("html");
        }
        if (tag == .title or tag == .meta or tag == .link or tag == .style) {
            if (!self.head_inserted) {
                try self.insertImplicitElement("head");
                self.head_inserted = true;
            }
        }
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
        for (attributes) |attr| {
            try elem.attributes.append(self.allocator, .{
                .name = try self.allocator.dupe(u8, attr.name),
                .value = try self.allocator.dupe(u8, attr.value),
            });
        }

        const parent = self.currentNode();
        parent.appendChild(elem, self.doc.limits) catch return elem;

        if (!tag.isVoid()) {
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
                .end_tag => builder.processEndTag(token.tag_name orelse continue),
                .character => try builder.insertText(token.data orelse continue),
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
