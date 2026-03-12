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

    pub fn insertElement(self: *TreeBuilder, tag_name: []const u8, attributes: []const tokenizer_mod.Attribute) !*Node {
        const tag = TagName.fromString(tag_name);

        // 1. Ensure html exists
        if (tag != .html and !self.hasOpenElement(.html)) {
            try self.insertImplicitElement("html");
        }

        // HTML5 §12.2.6.4: If a second <html> tag appears, ignore it
        // but adopt any new attributes onto the existing <html> element.
        if (tag == .html) {
            if (self.hasOpenElement(.html)) {
                const existing = self.findOpenElement(.html).?;
                self.adoptAttributes(existing, attributes);
                return existing;
            }
        }

        // 2. Handle explicit <head>: if already inserted, ignore the duplicate
        // but adopt attributes onto the existing <head>.
        if (tag == .head) {
            if (self.head_inserted) {
                if (self.findOpenElement(.head)) |existing| {
                    self.adoptAttributes(existing, attributes);
                    return existing;
                }
                // Head was closed — just ignore the duplicate <head>
                const existing = self.findChildByTag(self.doc.root, .head) orelse {
                    // Fallback: create normally if we can't find it
                    self.head_inserted = true;
                    return self.createAndAppend(tag_name, tag, attributes);
                };
                self.adoptAttributes(existing, attributes);
                return existing;
            }
            self.head_inserted = true;
        }

        // 3. Ensure head exists for head-content tags
        if (tag == .title or tag == .meta or tag == .link or tag == .style) {
            if (!self.head_inserted) {
                try self.insertImplicitElement("head");
                self.head_inserted = true;
            }
        }

        // 4. Handle explicit <body>: if body was already inserted (implicitly or
        // explicitly), ignore the duplicate per HTML5 spec — just adopt attributes
        // and ensure it's the current open element.
        if (tag == .body) {
            if (self.hasOpenElement(.head)) self.closeUpTo(.head);
            if (self.body_inserted) {
                // Find existing body and adopt attributes
                if (self.findOpenElement(.body)) |existing| {
                    self.adoptAttributes(existing, attributes);
                    return existing;
                }
                // Body was closed but body_inserted is true — find it in tree
                const existing = self.findChildByTag(self.doc.root, .body) orelse {
                    // Fallback: create normally
                    self.body_inserted = true;
                    return self.createAndAppend(tag_name, tag, attributes);
                };
                self.adoptAttributes(existing, attributes);
                // Re-open it so subsequent elements are children of body
                try self.open_elements.append(self.allocator, existing);
                return existing;
            }
            self.body_inserted = true;
        }

        // 5. Ensure body exists for body-content tags
        if (tag != .html and tag != .head and tag != .body and
            tag != .title and tag != .meta and tag != .link and tag != .style)
        {
            if (!self.body_inserted) {
                if (self.hasOpenElement(.head)) self.closeUpTo(.head);
                try self.insertImplicitElement("body");
                self.body_inserted = true;
            }
        }

        return self.createAndAppend(tag_name, tag, attributes);
    }

    /// Create element, adopt attributes, append to current parent, push to open stack.
    fn createAndAppend(self: *TreeBuilder, tag_name: []const u8, tag: TagName, attributes: []const tokenizer_mod.Attribute) !*Node {
        const elem = try self.doc.createElement(tag_name);
        elem.tag_name_str = try self.allocator.dupe(u8, tag_name);
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
        elem.tag_name_str = try self.allocator.dupe(u8, tag_name);
        const parent = self.currentNode();
        parent.appendChild(elem, self.doc.limits) catch return;
        try self.open_elements.append(self.allocator, elem);
    }

    pub fn hasOpenElement(self: *TreeBuilder, tag: TagName) bool {
        for (self.open_elements.items) |elem| {
            if (elem.tag == tag) return true;
        }
        return false;
    }

    /// Find an open element by tag name and return it (or null).
    fn findOpenElement(self: *TreeBuilder, tag: TagName) ?*Node {
        for (self.open_elements.items) |elem| {
            if (elem.tag == tag) return elem;
        }
        return null;
    }

    /// Find a direct child of `parent` by tag name (shallow search).
    /// Recursively searches up to 2 levels to find it in html > body structure.
    fn findChildByTag(_: *TreeBuilder, parent: *Node, tag: TagName) ?*Node {
        for (parent.children.items) |child| {
            if (child.tag == tag) return child;
            // Search one level deeper (e.g., html > body)
            for (child.children.items) |grandchild| {
                if (grandchild.tag == tag) return grandchild;
            }
        }
        return null;
    }

    /// Adopt attributes from a token onto an existing element.
    /// Per HTML5: only add attributes that don't already exist on the element.
    fn adoptAttributes(self: *TreeBuilder, elem: *Node, attributes: []const tokenizer_mod.Attribute) void {
        for (attributes) |attr| {
            var exists = false;
            for (elem.attributes.items) |existing| {
                if (std.mem.eql(u8, existing.name, attr.name)) {
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                elem.attributes.append(self.allocator, .{
                    .name = self.allocator.dupe(u8, attr.name) catch continue,
                    .value = self.allocator.dupe(u8, attr.value) catch continue,
                }) catch {};
            }
        }
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
        // Skip whitespace-only text before body is inserted (inter-element whitespace per HTML5)
        if (!self.body_inserted) {
            var all_ws = true;
            for (text) |c| {
                if (c != ' ' and c != '\t' and c != '\n' and c != '\r') {
                    all_ws = false;
                    break;
                }
            }
            if (all_ws) return;
        }
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
                    // Handle self-closing tags (e.g., <path d="..." />)
                    // Void elements are already excluded from open_elements in createAndAppend,
                    // so this only affects non-void self-closing elements like SVG children.
                    if (token.self_closing) {
                        const tag = TagName.fromString(token.tag_name orelse "");
                        if (!tag.isVoid() and builder.open_elements.items.len > 0) {
                            _ = builder.open_elements.pop();
                        }
                    }
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
