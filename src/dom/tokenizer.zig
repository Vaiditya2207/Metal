const std = @import("std");
const config = @import("../config.zig");
const entity = @import("entity.zig");

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
    data, tag_open, end_tag_open, tag_name,
    before_attribute_name, attribute_name, after_attribute_name,
    before_attribute_value,
    attribute_value_double_quoted, attribute_value_single_quoted, attribute_value_unquoted,
    self_closing_start_tag, bogus_comment, markup_declaration_open,
};

/// HTML5-compliant tokenizer with configurable security limits.
pub const Tokenizer = struct {
    input: []const u8,
    pos: usize,
    state: State,
    allocator: std.mem.Allocator,
    is_end_tag: bool,

    tag_name_buf: std.ArrayListUnmanaged(u8),
    attr_name_buf: std.ArrayListUnmanaged(u8),
    attr_value_buf: std.ArrayListUnmanaged(u8),
    attr_list: std.ArrayListUnmanaged(Attribute),
    text_buf: std.ArrayListUnmanaged(u8),
    self_closing: bool,

    max_tag_name_len: u16,
    max_attr_name_len: u16,
    max_attr_value_len: u32,
    max_attrs_per_element: u16,

    pub fn init(allocator: std.mem.Allocator, input: []const u8) Tokenizer {
        const cfg = config.getConfig();
        return .{
            .input = input, .pos = 0, .state = .data,
            .allocator = allocator, .is_end_tag = false,
            .tag_name_buf = .empty, .attr_name_buf = .empty,
            .attr_value_buf = .empty, .attr_list = .empty,
            .text_buf = .empty, .self_closing = false,
            .max_tag_name_len = cfg.parser.max_tag_name_length,
            .max_attr_name_len = cfg.parser.max_attribute_name_length,
            .max_attr_value_len = cfg.parser.max_attribute_value_length,
            .max_attrs_per_element = cfg.parser.max_attributes_per_element,
        };
    }

    // --- Internal helpers ---

    fn consume(self: *Tokenizer) ?u8 {
        if (self.pos >= self.input.len) return null;
        const c = self.input[self.pos];
        self.pos += 1;
        return c;
    }

    fn resetTagState(self: *Tokenizer) void {
        self.tag_name_buf.clearRetainingCapacity();
        self.attr_list.clearRetainingCapacity();
        self.self_closing = false;
        self.is_end_tag = false;
    }

    fn resetAttrState(self: *Tokenizer) void {
        self.attr_name_buf.clearRetainingCapacity();
        self.attr_value_buf.clearRetainingCapacity();
    }

    fn finalizeAttribute(self: *Tokenizer) !void {
        if (self.attr_name_buf.items.len == 0) return;
        if (self.attr_list.items.len >= self.max_attrs_per_element) return;
        const name = try self.allocator.dupe(u8, self.attr_name_buf.items);
        const value = try self.allocator.dupe(u8, self.attr_value_buf.items);
        try self.attr_list.append(self.allocator, .{ .name = name, .value = value });
        self.resetAttrState();
    }

    fn flushText(self: *Tokenizer) ?Token {
        if (self.text_buf.items.len == 0) return null;
        const data = self.allocator.dupe(u8, self.text_buf.items) catch return null;
        self.text_buf.clearRetainingCapacity();
        return Token{ .type = .character, .data = data };
    }

    fn buildTagToken(self: *Tokenizer) !Token {
        const name = try self.allocator.dupe(u8, self.tag_name_buf.items);
        const attrs = try self.allocator.dupe(Attribute, self.attr_list.items);
        return Token{
            .type = if (self.is_end_tag) .end_tag else .start_tag,
            .tag_name = name, .self_closing = self.self_closing, .attributes = attrs,
        };
    }

    fn decodeEntity(self: *Tokenizer) u8 {
        return entity.decode(self.input, &self.pos);
    }

    fn appendToTagName(self: *Tokenizer, c: u8) !void {
        if (self.tag_name_buf.items.len < self.max_tag_name_len)
            try self.tag_name_buf.append(self.allocator, std.ascii.toLower(c));
    }

    fn appendToAttrName(self: *Tokenizer, c: u8) !void {
        if (self.attr_name_buf.items.len < self.max_attr_name_len)
            try self.attr_name_buf.append(self.allocator, std.ascii.toLower(c));
    }

    fn appendToAttrValue(self: *Tokenizer, c: u8) !void {
        if (self.attr_value_buf.items.len < self.max_attr_value_len)
            try self.attr_value_buf.append(self.allocator, c);
    }

    fn isWhitespace(c: u8) bool {
        return c == ' ' or c == '\t' or c == '\n' or c == '\r';
    }

    // --- Main tokenization loop ---

    pub fn next(self: *Tokenizer) !Token {
        while (true) {
            switch (self.state) {
                .data => {
                    const c = self.consume() orelse {
                        if (self.flushText()) |t| return t;
                        return Token{ .type = .eof };
                    };
                    if (c == '<') {
                        if (self.flushText()) |t| { self.state = .tag_open; return t; }
                        self.state = .tag_open;
                    } else if (c == '&') {
                        try self.text_buf.append(self.allocator, self.decodeEntity());
                    } else {
                        try self.text_buf.append(self.allocator, c);
                    }
                },
                .tag_open => {
                    self.resetTagState();
                    const c = self.consume() orelse { try self.text_buf.append(self.allocator, '<'); self.state = .data; continue; };
                    if (c == '/') { self.is_end_tag = true; self.state = .end_tag_open; }
                    else if (c == '!') { self.state = .markup_declaration_open; }
                    else if (std.ascii.isAlphabetic(c)) { try self.appendToTagName(c); self.state = .tag_name; }
                    else { try self.text_buf.append(self.allocator, '<'); try self.text_buf.append(self.allocator, c); self.state = .data; }
                },
                .end_tag_open => {
                    const c = self.consume() orelse { try self.text_buf.appendSlice(self.allocator, "</"); self.state = .data; continue; };
                    if (std.ascii.isAlphabetic(c)) { try self.appendToTagName(c); self.state = .tag_name; }
                    else { self.state = .bogus_comment; }
                },
                .tag_name => {
                    const c = self.consume() orelse { self.state = .data; continue; };
                    if (isWhitespace(c)) { self.state = .before_attribute_name; }
                    else if (c == '/') { self.state = .self_closing_start_tag; }
                    else if (c == '>') { self.state = .data; return self.buildTagToken(); }
                    else { try self.appendToTagName(c); }
                },
                .before_attribute_name => {
                    const c = self.consume() orelse { self.state = .data; continue; };
                    if (isWhitespace(c)) { continue; }
                    else if (c == '/') { self.state = .self_closing_start_tag; }
                    else if (c == '>') { self.state = .data; return self.buildTagToken(); }
                    else { self.resetAttrState(); try self.appendToAttrName(c); self.state = .attribute_name; }
                },
                .attribute_name => {
                    const c = self.consume() orelse { self.state = .data; continue; };
                    if (c == '=') { self.state = .before_attribute_value; }
                    else if (isWhitespace(c)) { self.state = .after_attribute_name; }
                    else if (c == '/' or c == '>') {
                        try self.finalizeAttribute();
                        if (c == '/') { self.state = .self_closing_start_tag; } else { self.state = .data; return self.buildTagToken(); }
                    } else { try self.appendToAttrName(c); }
                },
                .after_attribute_name => {
                    const c = self.consume() orelse { self.state = .data; continue; };
                    if (isWhitespace(c)) { continue; }
                    else if (c == '=') { self.state = .before_attribute_value; }
                    else if (c == '/' or c == '>') {
                        try self.finalizeAttribute();
                        if (c == '/') { self.state = .self_closing_start_tag; } else { self.state = .data; return self.buildTagToken(); }
                    } else {
                        try self.finalizeAttribute();
                        self.resetAttrState();
                        try self.appendToAttrName(c);
                        self.state = .attribute_name;
                    }
                },
                .before_attribute_value => {
                    const c = self.consume() orelse { self.state = .data; continue; };
                    if (isWhitespace(c)) { continue; }
                    else if (c == '"') { self.state = .attribute_value_double_quoted; }
                    else if (c == '\'') { self.state = .attribute_value_single_quoted; }
                    else if (c == '>') { try self.finalizeAttribute(); self.state = .data; return self.buildTagToken(); }
                    else { try self.appendToAttrValue(c); self.state = .attribute_value_unquoted; }
                },
                .attribute_value_double_quoted => {
                    const c = self.consume() orelse { self.state = .data; continue; };
                    if (c == '"') { try self.finalizeAttribute(); self.state = .before_attribute_name; }
                    else if (c == '&') { try self.appendToAttrValue(self.decodeEntity()); }
                    else { try self.appendToAttrValue(c); }
                },
                .attribute_value_single_quoted => {
                    const c = self.consume() orelse { self.state = .data; continue; };
                    if (c == '\'') { try self.finalizeAttribute(); self.state = .before_attribute_name; }
                    else if (c == '&') { try self.appendToAttrValue(self.decodeEntity()); }
                    else { try self.appendToAttrValue(c); }
                },
                .attribute_value_unquoted => {
                    const c = self.consume() orelse { try self.finalizeAttribute(); self.state = .data; continue; };
                    if (isWhitespace(c)) { try self.finalizeAttribute(); self.state = .before_attribute_name; }
                    else if (c == '>') { try self.finalizeAttribute(); self.state = .data; return self.buildTagToken(); }
                    else if (c == '&') { try self.appendToAttrValue(self.decodeEntity()); }
                    else { try self.appendToAttrValue(c); }
                },
                .self_closing_start_tag => {
                    const c = self.consume() orelse { self.state = .data; continue; };
                    if (c == '>') { self.self_closing = true; self.state = .data; return self.buildTagToken(); }
                    else { self.state = .before_attribute_name; }
                },
                .bogus_comment => {
                    const c = self.consume() orelse { self.state = .data; continue; };
                    if (c == '>') self.state = .data;
                },
                .markup_declaration_open => {
                    if (self.pos + 1 < self.input.len and self.input[self.pos] == '-' and self.input[self.pos + 1] == '-') {
                        self.pos += 2;
                        while (self.pos + 2 < self.input.len) {
                            if (self.input[self.pos] == '-' and self.input[self.pos + 1] == '-' and self.input[self.pos + 2] == '>') { self.pos += 3; break; }
                            self.pos += 1;
                        } else { self.pos = self.input.len; }
                        self.state = .data;
                        return Token{ .type = .comment };
                    } else {
                        const remaining = self.input[self.pos..];
                        if (remaining.len >= 7 and std.ascii.eqlIgnoreCase(remaining[0..7], "DOCTYPE")) {
                            while (self.pos < self.input.len and self.input[self.pos] != '>') self.pos += 1;
                            if (self.pos < self.input.len) self.pos += 1;
                            self.state = .data;
                            return Token{ .type = .doctype };
                        } else { self.state = .bogus_comment; }
                    }
                },
            }
        }
    }
};
