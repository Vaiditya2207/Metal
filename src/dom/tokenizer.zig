const std = @import("std");
const config = @import("../config.zig");

/// HTML Token types emitted by the tokenizer.
pub const TokenType = enum {
    start_tag,
    end_tag,
    character,
    comment,
    doctype,
    eof,
};

/// A single HTML attribute (name = value).
pub const Attribute = struct {
    name: []const u8,
    value: []const u8,
};

/// Token produced by the tokenizer.
pub const Token = struct {
    type: TokenType,
    tag_name: ?[]const u8 = null,
    self_closing: bool = false,
    attributes: []const Attribute = &[_]Attribute{},
    data: ?[]const u8 = null,
};

/// Tokenizer states following the HTML5 spec.
const State = enum {
    data,
    tag_open,
    end_tag_open,
    tag_name,
    before_attribute_name,
    attribute_name,
    after_attribute_name,
    before_attribute_value,
    attribute_value_double_quoted,
    attribute_value_single_quoted,
    attribute_value_unquoted,
    self_closing_start_tag,
    bogus_comment,
    markup_declaration_open,
};

/// HTML5-compliant tokenizer with configurable security limits.
/// All allocations use the provided arena allocator for O(1) cleanup.
pub const Tokenizer = struct {
    input: []const u8,
    pos: usize,
    state: State,
    allocator: std.mem.Allocator,
    is_end_tag: bool,

    // Buffers for building tokens
    tag_name_buf: std.ArrayListUnmanaged(u8),
    attr_name_buf: std.ArrayListUnmanaged(u8),
    attr_value_buf: std.ArrayListUnmanaged(u8),
    attr_list: std.ArrayListUnmanaged(Attribute),
    text_buf: std.ArrayListUnmanaged(u8),
    self_closing: bool,

    // Configurable limits
    max_tag_name_len: u16,
    max_attr_name_len: u16,
    max_attr_value_len: u32,
    max_attrs_per_element: u16,

    pub fn init(allocator: std.mem.Allocator, input: []const u8) Tokenizer {
        const cfg = config.getConfig();
        return Tokenizer{
            .input = input,
            .pos = 0,
            .state = .data,
            .allocator = allocator,
            .is_end_tag = false,
            .tag_name_buf = .empty,
            .attr_name_buf = .empty,
            .attr_value_buf = .empty,
            .attr_list = .empty,
            .text_buf = .empty,
            .self_closing = false,
            .max_tag_name_len = cfg.parser.max_tag_name_length,
            .max_attr_name_len = cfg.parser.max_attribute_name_length,
            .max_attr_value_len = cfg.parser.max_attribute_value_length,
            .max_attrs_per_element = cfg.parser.max_attributes_per_element,
        };
    }

    /// Consume the next byte, returning null at EOF.
    fn consume(self: *Tokenizer) ?u8 {
        if (self.pos >= self.input.len) return null;
        const c = self.input[self.pos];
        self.pos += 1;
        return c;
    }

    /// Reset tag-building state for a new tag.
    fn resetTagState(self: *Tokenizer) void {
        self.tag_name_buf.clearRetainingCapacity();
        self.attr_list.clearRetainingCapacity();
        self.self_closing = false;
        self.is_end_tag = false;
    }

    /// Reset attribute-building state for a new attribute.
    fn resetAttrState(self: *Tokenizer) void {
        self.attr_name_buf.clearRetainingCapacity();
        self.attr_value_buf.clearRetainingCapacity();
    }

    /// Finalize the current attribute and push it to the list.
    fn finalizeAttribute(self: *Tokenizer) !void {
        if (self.attr_name_buf.items.len == 0) return;
        if (self.attr_list.items.len >= self.max_attrs_per_element) return;

        const name = try self.allocator.dupe(u8, self.attr_name_buf.items);
        const value = try self.allocator.dupe(u8, self.attr_value_buf.items);
        try self.attr_list.append(self.allocator, .{ .name = name, .value = value });
        self.resetAttrState();
    }

    /// Flush accumulated text as a character token.
    fn flushText(self: *Tokenizer) ?Token {
        if (self.text_buf.items.len == 0) return null;
        const data = self.allocator.dupe(u8, self.text_buf.items) catch return null;
        self.text_buf.clearRetainingCapacity();
        return Token{ .type = .character, .data = data };
    }

    /// Build a completed tag token.
    fn buildTagToken(self: *Tokenizer) !Token {
        const name = try self.allocator.dupe(u8, self.tag_name_buf.items);
        const attrs = try self.allocator.dupe(Attribute, self.attr_list.items);
        return Token{
            .type = if (self.is_end_tag) .end_tag else .start_tag,
            .tag_name = name,
            .self_closing = self.self_closing,
            .attributes = attrs,
        };
    }

    /// Decode a character reference (entity).
    fn decodeEntity(self: *Tokenizer) u8 {
        const start = self.pos;
        var buf: [32]u8 = undefined;
        var len: usize = 0;

        while (self.pos < self.input.len and len < 31) {
            const c = self.input[self.pos];
            self.pos += 1;
            if (c == ';') {
                const entity = buf[0..len];
                if (std.mem.eql(u8, entity, "amp")) return '&';
                if (std.mem.eql(u8, entity, "lt")) return '<';
                if (std.mem.eql(u8, entity, "gt")) return '>';
                if (std.mem.eql(u8, entity, "quot")) return '"';
                if (std.mem.eql(u8, entity, "apos")) return '\'';
                if (len > 1 and entity[0] == '#') {
                    if (entity[1] == 'x' or entity[1] == 'X') {
                        const val = std.fmt.parseInt(u8, entity[2..], 16) catch return '?';
                        return val;
                    } else {
                        const val = std.fmt.parseInt(u8, entity[1..], 10) catch return '?';
                        return val;
                    }
                }
                return '?';
            }
            buf[len] = c;
            len += 1;
        }

        self.pos = start;
        return '&';
    }

    /// Get the next token from the input.
    pub fn next(self: *Tokenizer) !Token {
        while (true) {
            switch (self.state) {
                .data => {
                    const c = self.consume() orelse {
                        if (self.flushText()) |t| return t;
                        return Token{ .type = .eof };
                    };

                    if (c == '<') {
                        if (self.flushText()) |t| {
                            self.state = .tag_open;
                            return t;
                        }
                        self.state = .tag_open;
                    } else if (c == '&') {
                        const decoded = self.decodeEntity();
                        try self.text_buf.append(self.allocator, decoded);
                    } else {
                        try self.text_buf.append(self.allocator, c);
                    }
                },

                .tag_open => {
                    self.resetTagState();
                    const c = self.consume() orelse {
                        try self.text_buf.append(self.allocator, '<');
                        self.state = .data;
                        continue;
                    };

                    if (c == '/') {
                        self.is_end_tag = true;
                        self.state = .end_tag_open;
                    } else if (c == '!') {
                        self.state = .markup_declaration_open;
                    } else if (std.ascii.isAlphabetic(c)) {
                        if (self.tag_name_buf.items.len < self.max_tag_name_len) {
                            try self.tag_name_buf.append(self.allocator, std.ascii.toLower(c));
                        }
                        self.state = .tag_name;
                    } else {
                        try self.text_buf.append(self.allocator, '<');
                        try self.text_buf.append(self.allocator, c);
                        self.state = .data;
                    }
                },

                .end_tag_open => {
                    const c = self.consume() orelse {
                        try self.text_buf.appendSlice(self.allocator, "</");
                        self.state = .data;
                        continue;
                    };

                    if (std.ascii.isAlphabetic(c)) {
                        if (self.tag_name_buf.items.len < self.max_tag_name_len) {
                            try self.tag_name_buf.append(self.allocator, std.ascii.toLower(c));
                        }
                        self.state = .tag_name;
                    } else {
                        self.state = .bogus_comment;
                    }
                },

                .tag_name => {
                    const c = self.consume() orelse {
                        self.state = .data;
                        continue;
                    };

                    if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                        self.state = .before_attribute_name;
                    } else if (c == '/') {
                        self.state = .self_closing_start_tag;
                    } else if (c == '>') {
                        self.state = .data;
                        return self.buildTagToken();
                    } else {
                        if (self.tag_name_buf.items.len < self.max_tag_name_len) {
                            try self.tag_name_buf.append(self.allocator, std.ascii.toLower(c));
                        }
                    }
                },

                .before_attribute_name => {
                    const c = self.consume() orelse {
                        self.state = .data;
                        continue;
                    };

                    if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                        continue;
                    } else if (c == '/') {
                        self.state = .self_closing_start_tag;
                    } else if (c == '>') {
                        self.state = .data;
                        return self.buildTagToken();
                    } else {
                        self.resetAttrState();
                        if (self.attr_name_buf.items.len < self.max_attr_name_len) {
                            try self.attr_name_buf.append(self.allocator, std.ascii.toLower(c));
                        }
                        self.state = .attribute_name;
                    }
                },

                .attribute_name => {
                    const c = self.consume() orelse {
                        self.state = .data;
                        continue;
                    };

                    if (c == '=') {
                        self.state = .before_attribute_value;
                    } else if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                        self.state = .after_attribute_name;
                    } else if (c == '/' or c == '>') {
                        try self.finalizeAttribute();
                        if (c == '/') {
                            self.state = .self_closing_start_tag;
                        } else {
                            self.state = .data;
                            return self.buildTagToken();
                        }
                    } else {
                        if (self.attr_name_buf.items.len < self.max_attr_name_len) {
                            try self.attr_name_buf.append(self.allocator, std.ascii.toLower(c));
                        }
                    }
                },

                .after_attribute_name => {
                    const c = self.consume() orelse {
                        self.state = .data;
                        continue;
                    };

                    if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                        continue;
                    } else if (c == '=') {
                        self.state = .before_attribute_value;
                    } else if (c == '/' or c == '>') {
                        try self.finalizeAttribute();
                        if (c == '/') {
                            self.state = .self_closing_start_tag;
                        } else {
                            self.state = .data;
                            return self.buildTagToken();
                        }
                    } else {
                        try self.finalizeAttribute();
                        self.resetAttrState();
                        if (self.attr_name_buf.items.len < self.max_attr_name_len) {
                            try self.attr_name_buf.append(self.allocator, std.ascii.toLower(c));
                        }
                        self.state = .attribute_name;
                    }
                },

                .before_attribute_value => {
                    const c = self.consume() orelse {
                        self.state = .data;
                        continue;
                    };

                    if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                        continue;
                    } else if (c == '"') {
                        self.state = .attribute_value_double_quoted;
                    } else if (c == '\'') {
                        self.state = .attribute_value_single_quoted;
                    } else if (c == '>') {
                        try self.finalizeAttribute();
                        self.state = .data;
                        return self.buildTagToken();
                    } else {
                        if (self.attr_value_buf.items.len < self.max_attr_value_len) {
                            try self.attr_value_buf.append(self.allocator, c);
                        }
                        self.state = .attribute_value_unquoted;
                    }
                },

                .attribute_value_double_quoted => {
                    const c = self.consume() orelse {
                        self.state = .data;
                        continue;
                    };

                    if (c == '"') {
                        try self.finalizeAttribute();
                        self.state = .before_attribute_name;
                    } else if (c == '&') {
                        const decoded = self.decodeEntity();
                        if (self.attr_value_buf.items.len < self.max_attr_value_len) {
                            try self.attr_value_buf.append(self.allocator, decoded);
                        }
                    } else {
                        if (self.attr_value_buf.items.len < self.max_attr_value_len) {
                            try self.attr_value_buf.append(self.allocator, c);
                        }
                    }
                },

                .attribute_value_single_quoted => {
                    const c = self.consume() orelse {
                        self.state = .data;
                        continue;
                    };

                    if (c == '\'') {
                        try self.finalizeAttribute();
                        self.state = .before_attribute_name;
                    } else if (c == '&') {
                        const decoded = self.decodeEntity();
                        if (self.attr_value_buf.items.len < self.max_attr_value_len) {
                            try self.attr_value_buf.append(self.allocator, decoded);
                        }
                    } else {
                        if (self.attr_value_buf.items.len < self.max_attr_value_len) {
                            try self.attr_value_buf.append(self.allocator, c);
                        }
                    }
                },

                .attribute_value_unquoted => {
                    const c = self.consume() orelse {
                        try self.finalizeAttribute();
                        self.state = .data;
                        continue;
                    };

                    if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                        try self.finalizeAttribute();
                        self.state = .before_attribute_name;
                    } else if (c == '>') {
                        try self.finalizeAttribute();
                        self.state = .data;
                        return self.buildTagToken();
                    } else if (c == '&') {
                        const decoded = self.decodeEntity();
                        if (self.attr_value_buf.items.len < self.max_attr_value_len) {
                            try self.attr_value_buf.append(self.allocator, decoded);
                        }
                    } else {
                        if (self.attr_value_buf.items.len < self.max_attr_value_len) {
                            try self.attr_value_buf.append(self.allocator, c);
                        }
                    }
                },

                .self_closing_start_tag => {
                    const c = self.consume() orelse {
                        self.state = .data;
                        continue;
                    };

                    if (c == '>') {
                        self.self_closing = true;
                        self.state = .data;
                        return self.buildTagToken();
                    } else {
                        self.state = .before_attribute_name;
                    }
                },

                .bogus_comment => {
                    const c = self.consume() orelse {
                        self.state = .data;
                        continue;
                    };
                    if (c == '>') {
                        self.state = .data;
                    }
                },

                .markup_declaration_open => {
                    if (self.pos + 1 < self.input.len and self.input[self.pos] == '-' and self.input[self.pos + 1] == '-') {
                        self.pos += 2;
                        while (self.pos + 2 < self.input.len) {
                            if (self.input[self.pos] == '-' and self.input[self.pos + 1] == '-' and self.input[self.pos + 2] == '>') {
                                self.pos += 3;
                                break;
                            }
                            self.pos += 1;
                        } else {
                            self.pos = self.input.len;
                        }
                        self.state = .data;
                        return Token{ .type = .comment };
                    } else {
                        const remaining = self.input[self.pos..];
                        if (remaining.len >= 7 and std.ascii.eqlIgnoreCase(remaining[0..7], "DOCTYPE")) {
                            while (self.pos < self.input.len and self.input[self.pos] != '>') {
                                self.pos += 1;
                            }
                            if (self.pos < self.input.len) self.pos += 1;
                            self.state = .data;
                            return Token{ .type = .doctype };
                        } else {
                            self.state = .bogus_comment;
                        }
                    }
                },
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "tokenize simple tag" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var tokenizer = Tokenizer.init(arena.allocator(), "<div>");
    const t1 = try tokenizer.next();
    try std.testing.expectEqual(TokenType.start_tag, t1.type);
    try std.testing.expectEqualStrings("div", t1.tag_name.?);
}

test "tokenize text content" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var tokenizer = Tokenizer.init(arena.allocator(), "Hello World");
    const t1 = try tokenizer.next();
    try std.testing.expectEqual(TokenType.character, t1.type);
    try std.testing.expectEqualStrings("Hello World", t1.data.?);
}

test "tokenize tag with attributes" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var tokenizer = Tokenizer.init(arena.allocator(), "<div class=\"main\" id=\"app\">");
    const t1 = try tokenizer.next();
    try std.testing.expectEqual(TokenType.start_tag, t1.type);
    try std.testing.expectEqualStrings("div", t1.tag_name.?);
    try std.testing.expectEqual(@as(usize, 2), t1.attributes.len);
    try std.testing.expectEqualStrings("class", t1.attributes[0].name);
    try std.testing.expectEqualStrings("main", t1.attributes[0].value);
}

test "tokenize self-closing tag" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var tokenizer = Tokenizer.init(arena.allocator(), "<br/>");
    const t1 = try tokenizer.next();
    try std.testing.expectEqual(TokenType.start_tag, t1.type);
    try std.testing.expectEqualStrings("br", t1.tag_name.?);
    try std.testing.expect(t1.self_closing);
}

test "tokenize entity references" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var tokenizer = Tokenizer.init(arena.allocator(), "&lt;div&gt;");
    const t1 = try tokenizer.next();
    try std.testing.expectEqual(TokenType.character, t1.type);
    try std.testing.expectEqualStrings("<div>", t1.data.?);
}

test "tokenize doctype" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var tokenizer = Tokenizer.init(arena.allocator(), "<!DOCTYPE html>");
    const t1 = try tokenizer.next();
    try std.testing.expectEqual(TokenType.doctype, t1.type);
}

test "tokenize comment" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var tokenizer = Tokenizer.init(arena.allocator(), "<!-- comment -->");
    const t1 = try tokenizer.next();
    try std.testing.expectEqual(TokenType.comment, t1.type);
}

test "tokenize eof" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var tokenizer = Tokenizer.init(arena.allocator(), "");
    const t1 = try tokenizer.next();
    try std.testing.expectEqual(TokenType.eof, t1.type);
}

test "tokenize mixed content" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var tokenizer = Tokenizer.init(arena.allocator(), "<p>Hello</p>");
    const t1 = try tokenizer.next();
    try std.testing.expectEqual(TokenType.start_tag, t1.type);
    const t2 = try tokenizer.next();
    try std.testing.expectEqual(TokenType.character, t2.type);
    try std.testing.expectEqualStrings("Hello", t2.data.?);
}

test "security: null bytes do not crash" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var tokenizer = Tokenizer.init(arena.allocator(), "<div\x00class=\"a\">");
    const t1 = try tokenizer.next();
    try std.testing.expectEqual(TokenType.start_tag, t1.type);
}

test "tokenize single quoted attributes" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var tokenizer = Tokenizer.init(arena.allocator(), "<a href='http://example.com'>");
    const t1 = try tokenizer.next();
    try std.testing.expectEqualStrings("href", t1.attributes[0].name);
    try std.testing.expectEqualStrings("http://example.com", t1.attributes[0].value);
}

test "tokenize unquoted attribute" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var tokenizer = Tokenizer.init(arena.allocator(), "<input type=text>");
    const t1 = try tokenizer.next();
    try std.testing.expectEqualStrings("type", t1.attributes[0].name);
    try std.testing.expectEqualStrings("text", t1.attributes[0].value);
}

test "tokenize end tag" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var tokenizer = Tokenizer.init(arena.allocator(), "</div>");
    const t1 = try tokenizer.next();
    try std.testing.expectEqual(TokenType.end_tag, t1.type);
    try std.testing.expectEqualStrings("div", t1.tag_name.?);
}

test "entity: numeric decimal reference" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var tokenizer = Tokenizer.init(arena.allocator(), "&#65;");
    const t1 = try tokenizer.next();
    try std.testing.expectEqualStrings("A", t1.data.?);
}

test "entity: numeric hex reference" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var tokenizer = Tokenizer.init(arena.allocator(), "&#x41;");
    const t1 = try tokenizer.next();
    try std.testing.expectEqualStrings("A", t1.data.?);
}

test "entity: all named entities" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var tokenizer = Tokenizer.init(arena.allocator(), "&amp;&lt;&gt;&quot;");
    const t1 = try tokenizer.next();
    try std.testing.expectEqualStrings("&<>\"", t1.data.?);
}

test "tokenize attribute with entity in value" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var tokenizer = Tokenizer.init(arena.allocator(), "<a title=\"a &amp; b\">");
    const t1 = try tokenizer.next();
    try std.testing.expectEqualStrings("a & b", t1.attributes[0].value);
}

test "security: malformed tag does not crash" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var tokenizer = Tokenizer.init(arena.allocator(), "< not a tag >");
    while (true) {
        const t = try tokenizer.next();
        if (t.type == .eof) break;
    }
}

test "security: deeply nested tags handled" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var input_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer input_buf.deinit(std.heap.page_allocator);
    for (0..1000) |_| {
        try input_buf.appendSlice(std.heap.page_allocator, "<div>");
    }
    var tokenizer = Tokenizer.init(arena.allocator(), input_buf.items);
    var count: usize = 0;
    while (true) {
        const t = try tokenizer.next();
        if (t.type == .eof) break;
        count += 1;
    }
    try std.testing.expect(count == 1000);
}

test "tokenize multiple attributes" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var tokenizer = Tokenizer.init(arena.allocator(), "<input type=\"text\" name=\"user\" value=\"hello\">");
    const t1 = try tokenizer.next();
    try std.testing.expectEqual(@as(usize, 3), t1.attributes.len);
}
